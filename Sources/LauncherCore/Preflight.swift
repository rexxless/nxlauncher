import Foundation

/// Checks that a build can start: the engine, Python and its modules, the keys file, the build tools, an Apple silicon Mac.
public struct Preflight: Sendable {
    /// What fixes a failed check: the launcher shows it as a button beside the check.
    public enum Fix: Equatable, Sendable {
        case chooseKeys
        case chooseEngine
        case installModules([String])          // into the launcher's own venv (PythonSetup)
        case brewInstall([String])
        case openURL(URL, label: String)
    }

    public struct Check: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String
        public var ok: Bool
        public var detail: String
        public var fix: Fix?

        public init(name: String, ok: Bool, detail: String, fix: Fix? = nil) {
            self.name = name; self.ok = ok; self.detail = detail; self.fix = fix
        }
    }

    /// Where the engine comes from: the copy shipped in the app (unpacked, unpacking, or failed to unpack) or the user's own clone.
    public enum EngineSource: Equatable, Sendable {
        case bundled(version: String)
        case unpacking
        case updating
        case failed(String)
        case custom
    }

    public static let engineName = "nxnative engine", pythonName = "Python modules", keysName = "Keys file", toolsName = "Build tools"

    public static let pythonCandidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]

    /// The first Python 3 that exists, preferring Homebrew's (the system one usually lacks the modules nxnative needs).
    public static func findPython(fileManager fm: FileManager = .default) -> URL? {
        pythonCandidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    public static func isCheckout(_ url: URL, fileManager fm: FileManager = .default) -> Bool {
        fm.fileExists(atPath: url.appending(path: "scripts/build_ipa_from_nsp.py").path)
            && fm.fileExists(atPath: url.appending(path: "dm/games/README.md").path)
    }

    public static var isAppleSilicon: Bool {
        var v: Int32 = 0; var n = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &v, &n, nil, 0) == 0 && v == 1
    }

    /// Runs every check. The keys file is only tested for being readable: its contents are never opened here.
    public static func run(checkout: URL?, source: EngineSource, python: URL?, keys: URL?,
                           environment: [String: String] = BuildRunner.environment(),
                           developerDir: String? = activeDeveloperDir()) async -> [Check] {
        let fm = FileManager.default
        var out: [Check] = []
        out.append(Check(name: "Apple silicon", ok: isAppleSilicon, detail: isAppleSilicon ? "" : "nxnative's Mac host needs an Apple silicon Mac"))
        out.append(engineCheck(checkout: checkout, source: source))
        if let python, fm.isExecutableFile(atPath: python.path) {
            let missing = await missingModules(python: python)
            out.append(Check(name: pythonName, ok: missing.isEmpty,
                             detail: missing.isEmpty ? "lz4, capstone, fontTools" : "missing: \(missing.joined(separator: ", "))",
                             fix: missing.isEmpty ? nil : .installModules(missing)))
        } else {
            out.append(Check(name: pythonName, ok: false, detail: "Python 3 not found",
                             fix: .openURL(URL(string: "https://www.python.org/downloads/macos/")!, label: "Get Python")))
        }
        if let keys, fm.isReadableFile(atPath: keys.path) {
            out.append(Check(name: keysName, ok: true, detail: "readable"))
        } else {
            out.append(Check(name: keysName, ok: false, detail: "choose your prod.keys file", fix: .chooseKeys))
        }
        out.append(toolsCheck(environment: environment, developerDir: developerDir))
        return out
    }

    static func engineCheck(checkout: URL?, source: EngineSource) -> Check {
        switch source {
        case .unpacking: return Check(name: engineName, ok: false, detail: "unpacking…")
        case .updating: return Check(name: engineName, ok: false, detail: "updating…")
        case .failed(let msg): return Check(name: engineName, ok: false, detail: msg, fix: .chooseEngine)
        case .bundled, .custom: break
        }
        guard let checkout, isCheckout(checkout) else {
            return Check(name: engineName, ok: false, detail: "choose the folder of a clone of the nxnative repository", fix: .chooseEngine)
        }
        if case .bundled(let v) = source { return Check(name: engineName, ok: true, detail: "bundled · \(Engine.shortVersion(v))") }
        return Check(name: engineName, ok: true, detail: "custom · \(checkout.lastPathComponent)")
    }

    /// Homebrew formulae the build script runs.
    public static let brewTools = ["zstd", "spirv-cross"]

    /// The tools the build script checks for (its check_prereqs) that are missing: Xcode (not the Command Line Tools alone), .NET and the Homebrew ones.
    public static func missingTools(environment: [String: String], developerDir: String?) -> [String] {
        var missing: [String] = []
        if developerDir.map({ !$0.contains(".app/") }) ?? true { missing.append("Xcode") }
        if which("dotnet", environment: environment) == nil { missing.append(".NET SDK 10") }
        missing += brewTools.filter { which($0, environment: environment) == nil }
        return missing
    }

    static func toolsCheck(environment: [String: String], developerDir: String?) -> Check {
        let missing = missingTools(environment: environment, developerDir: developerDir)
        guard !missing.isEmpty else { return Check(name: toolsName, ok: true, detail: "Xcode, .NET, zstd, spirv-cross") }
        let brew = brewTools.filter(missing.contains)
        let fix: Fix
        if !brew.isEmpty, let _ = which("brew", environment: environment) { fix = .brewInstall(brew) }
        else if missing.contains("Xcode") { fix = .openURL(URL(string: "macappstore://apps.apple.com/app/id497799835")!, label: "Get Xcode") }
        else if missing.contains(".NET SDK 10") { fix = .openURL(URL(string: "https://dotnet.microsoft.com/download/dotnet/10.0")!, label: "Get .NET") }
        else { fix = .openURL(URL(string: "https://brew.sh")!, label: "Get Homebrew") }
        return Check(name: toolsName, ok: false, detail: "missing: \(missing.joined(separator: ", "))", fix: fix)
    }

    /// The first executable named `tool` on the environment's PATH.
    public static func which(_ tool: String, environment: [String: String]) -> URL? {
        (environment["PATH"] ?? "").split(separator: ":").lazy
            .map { URL(fileURLWithPath: String($0)).appending(path: tool) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// `xcode-select -p`: an Xcode app's Developer folder, or the Command Line Tools'.
    public static func activeDeveloperDir() -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select"); p.arguments = ["-p"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && !s.isEmpty ? s : nil
    }

    static func pipName(_ module: String) -> String { module == "fontTools" ? "fonttools" : module }

    // zstd is built into Python from 3.14 (compression.zstd); before that the script needs backports.zstd.
    static let moduleProbe = """
        import importlib.util as u
        def has(m):
            try: return u.find_spec(m) is not None
            except ModuleNotFoundError: return False
        miss = [m for m in ('lz4', 'capstone', 'fontTools') if not has(m)]
        if not (has('compression.zstd') or has('backports.zstd')): miss.append('backports.zstd')
        print('missing:', ' '.join(miss))
        """

    static func missingModules(python: URL) async -> [String] {
        let modules = ["lz4", "capstone", "fontTools", "backports.zstd"]
        let out = TailLog()
        guard await ProcessLines.run(python, ["-c", moduleProbe], onLine: { out.append($0) }) == 0 else { return modules }
        // stderr is merged in (a warning, say): the answer is the line the probe marks.
        guard let line = out.all.last(where: { $0.hasPrefix("missing:") }) else { return modules }
        return line.dropFirst(8).split(separator: " ").map(String.init)
    }
}
