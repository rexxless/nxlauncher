import Foundation

/// The copy of nxnative shipped inside the launcher (`Contents/Resources/nxnative.tar.gz`, a git archive of `vendor/nxnative`).
/// A build writes into its checkout (the host's generated files, the profile's shader tables), so the copy is unpacked
/// into a writable folder once per version instead of being run from the signed app.
public enum Engine {
    public static let stampName = ".nxl-version"

    /// The tarball and the nxnative commit it holds, when the app bundle has them (a `swift run` build has not).
    public static func bundled(in bundle: Bundle = .main) -> (tarball: URL, version: String)? {
        guard let tar = bundle.url(forResource: "nxnative", withExtension: "tar.gz"),
              let v = bundle.url(forResource: "nxnative", withExtension: "version"),
              let version = try? String(contentsOf: v, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else { return nil }
        return (tar, version)
    }

    public static var defaultFolder: URL { Store.default.folder.appending(path: "nxnative") }

    public static func installedVersion(at folder: URL) -> String? {
        (try? String(contentsOf: folder.appending(path: stampName), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func shortVersion(_ v: String) -> String { String(v.prefix(7)) }

    public struct UnpackError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Unpacks the tarball into `folder` unless the folder already holds this version. The new copy is made beside the old one
    /// and swapped in only when complete, so a failed unpack leaves the old engine in place.
    public static func unpack(tarball: URL, version: String, to folder: URL) async throws {
        if installedVersion(at: folder) == version { return }
        let fm = FileManager.default
        let partial = folder.deletingLastPathComponent().appending(path: folder.lastPathComponent + ".partial")
        try? fm.removeItem(at: partial)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        let tail = TailLog()
        let status = await ProcessLines.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", tarball.path, "-C", partial.path]) { tail.append($0) }
        guard status == 0 else {
            try? fm.removeItem(at: partial)
            throw UnpackError(message: "could not unpack nxnative: \(tail.last ?? "tar exit \(status.map(String.init) ?? "?")")")
        }
        try version.write(to: partial.appending(path: stampName), atomically: true, encoding: .utf8)
        try? fm.removeItem(at: folder)
        try fm.moveItem(at: partial, to: folder)
    }
}

final class TailLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ s: String) { lock.withLock { lines.append(s); if lines.count > 50 { lines.removeFirst() } } }
    var last: String? { lock.withLock { lines.last } }
    var all: [String] { lock.withLock { lines } }
}
