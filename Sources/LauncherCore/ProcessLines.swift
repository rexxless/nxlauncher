import Foundation

/// Child processes whose output is read line by line as it arrives.
public enum ProcessLines {
    /// Runs a tool to its end, its stdout and stderr merged into `onLine`. Returns the exit status, or nil when it could not start.
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                           directory: URL? = nil, onLine: @escaping @Sendable (String) -> Void) async -> Int32? {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        if let environment { p.environment = environment }
        if let directory { p.currentDirectoryURL = directory }
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let done = read(pipe.fileHandleForReading) { if !$0.isEmpty { onLine($0) } }
        // The termination handler, not waitUntilExit: that spins a run loop, and blocking threads can starve Swift's concurrency pool.
        let exited = AsyncStream<Void> { c in p.terminationHandler = { _ in c.yield(); c.finish() } }
        do { try p.run() } catch { try? pipe.fileHandleForWriting.close(); await done.value; return nil }
        for await _ in exited { break }
        await done.value
        return p.terminationStatus
    }

    /// Splits a pipe's output into lines as it arrives. (FileHandle.bytes can hold a pipe's output back until it fills or closes,
    /// which would freeze a progress bar; the readability handler sees every write.)
    static func read(_ handle: FileHandle, _ each: @escaping @Sendable (String) -> Void) -> Task<Void, Never> {
        let splitter = LineSplitter(each)
        return Task.detached {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                handle.readabilityHandler = { h in
                    let data = h.availableData
                    if data.isEmpty {
                        h.readabilityHandler = nil
                        splitter.finish()
                        done.resume()
                    } else {
                        splitter.feed(data)
                    }
                }
            }
        }
    }
}

private final class LineSplitter: @unchecked Sendable {
    private var pending = Data()
    private let each: @Sendable (String) -> Void

    init(_ each: @escaping @Sendable (String) -> Void) { self.each = each }

    // Called only from the handle's serial readability queue.
    func feed(_ data: Data) {
        pending.append(data)
        while let nl = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<nl]
            pending.removeSubrange(pending.startIndex...nl)
            each(String(decoding: line, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
        }
    }

    func finish() {
        if !pending.isEmpty { each(String(decoding: pending, as: UTF8.self)); pending.removeAll() }
    }
}
