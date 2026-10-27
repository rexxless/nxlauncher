import Foundation

/// What a build is asked to do: one NSP folder packed into a Mac app by the nxnative checkout's script.
public struct BuildRequest: Equatable, Sendable, Codable {
    public var nspFolder: URL
    public var keysFile: URL
    public var checkout: URL
    public var python: URL
    public var output: URL?       // a path ending in .app; nil = the script's default, <NSP folder>/<game name>.app
    public var language: String?  // a code such as "ja"; nil = the script's default (English)

    public init(nspFolder: URL, keysFile: URL, checkout: URL, python: URL, output: URL? = nil, language: String? = nil) {
        self.nspFolder = nspFolder; self.keysFile = keysFile; self.checkout = checkout; self.python = python
        self.output = output; self.language = language
    }

    public var script: URL { checkout.appending(path: "scripts/build_ipa_from_nsp.py") }

    public var arguments: [String] {
        var a = [script.path, nspFolder.path, "-k", keysFile.path, "--platform", "mac-app", "--progress", "json"]
        if let output { a += ["-o", output.path] }
        if let language, !language.isEmpty { a += ["--language", language] }
        return a
    }
}

/// How a finished build ended. The script exits with 0 on success, 1 on error and 130 when interrupted.
public enum BuildOutcome: Equatable, Sendable {
    case succeeded(app: URL?)
    case failed(String)
    case cancelled

    public static func from(exitCode: Int32, messages: [String]) -> BuildOutcome {
        switch exitCode {
        case 0: return .succeeded(app: appPath(in: messages))
        case 130, -2: return .cancelled
        default:
            let red = messages.last { $0.hasPrefix("[RED] ") }.map { String($0.dropFirst(6)) }
            return .failed(red ?? "the build stopped (exit \(exitCode))")
        }
    }

    /// The app the script reports: "done: <path>.app (1.2 GB, …)" or, earlier, "…; app: <path>.app".
    public static func appPath(in messages: [String]) -> URL? {
        for msg in messages.reversed() {
            for pattern in [#"^done: (/.+?\.app) \("#, #"; app: (/.+?\.app)$"#] {
                if let r = msg.range(of: pattern, options: .regularExpression) {
                    let m = String(msg[r])
                    let start = m.range(of: "/")!.lowerBound
                    let end = m.range(of: ".app", options: .backwards)!.upperBound
                    return URL(fileURLWithPath: String(m[start..<end]))
                }
            }
        }
        return nil
    }
}

/// Runs one build as a child process and streams its events. Not reentrant: one runner per build.
public final class BuildRunner: @unchecked Sendable {
    public let request: BuildRequest
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    public init(request: BuildRequest) { self.request = request }

    /// The environment of the build: GUI apps do not get the shell's PATH, so the usual tool folders are added.
    public static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/local/share/dotnet"]
        let path = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        env["PATH"] = (extra.filter { !path.contains($0) } + path).joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    /// Starts the build. Events arrive on `onEvent` (any thread); `onLog` gets every line that is not an event (stderr, stray output).
    public func run(onEvent: @escaping @Sendable (BuildEvent) -> Void,
                    onLog: @escaping @Sendable (String) -> Void) async -> BuildOutcome {
        process.executableURL = request.python
        process.arguments = request.arguments
        process.currentDirectoryURL = request.checkout
        process.environment = Self.environment()
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let messages = MessageLog()
        let stdoutDone = ProcessLines.read(out.fileHandleForReading) { line in
            if let ev = BuildEvent.parse(line) {
                if case let .say(msg) = ev { messages.append(msg) }
                onEvent(ev)
            } else if !line.isEmpty { onLog(line) }
        }
        let stderrDone = ProcessLines.read(err.fileHandleForReading) { line in if !line.isEmpty { onLog(line) } }

        do {
            try process.run()
        } catch {
            return .failed("could not start \(request.python.lastPathComponent): \(error.localizedDescription)")
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { self.process.waitUntilExit(); c.resume() }
        }
        await stdoutDone.value
        await stderrDone.value
        if lock.withLock({ cancelled }) { return .cancelled }
        let code = process.terminationReason == .uncaughtSignal ? -process.terminationStatus : process.terminationStatus
        return BuildOutcome.from(exitCode: code, messages: messages.all)
    }

    /// Interrupts the build as Ctrl-C would (the script cleans up and exits with 130), then terminates it if it is still running 10 s later.
    public func cancel() {
        lock.withLock { cancelled = true }
        guard process.isRunning else { return }
        process.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [process] in
            if process.isRunning { process.terminate() }
        }
    }
}

private final class MessageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func append(_ s: String) { lock.withLock { items.append(s) } }
    var all: [String] { lock.withLock { items } }
}
