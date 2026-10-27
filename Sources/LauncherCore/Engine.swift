import Foundation

/// The copy of nxnative shipped inside the launcher (`Contents/Resources/nxnative.tar.gz`, a git archive of `vendor/nxnative`).
/// A build writes into its checkout (the host's generated files, the profile's shader tables), so the copy is unpacked
/// into a writable folder once per version instead of being run from the signed app. A newer commit downloaded from GitHub
/// (EngineUpdate) is unpacked into the same folder.
public enum Engine {
    public static let stampName = ".nxl-version"

    /// An nxnative commit: its hash and, when known, its commit date. Stamps and `nxnative.version` hold it as two lines.
    public struct Version: Equatable, Sendable {
        public let sha: String
        public let date: Date?
        public init(sha: String, date: Date?) { self.sha = sha; self.date = date }

        init?(stamp: String) {
            let lines = stamp.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let sha = lines.first, !sha.isEmpty else { return nil }
            self.sha = sha
            date = lines.dropFirst().first.flatMap { try? Date($0, strategy: .iso8601) }
        }

        var stamp: String { date.map { "\(sha)\n\($0.formatted(.iso8601))" } ?? sha }
    }

    /// The tarball and the nxnative commit it holds, when the app bundle has them (a `swift run` build has not).
    public static func bundled(in bundle: Bundle = .main) -> (tarball: URL, version: Version)? {
        guard let tar = bundle.url(forResource: "nxnative", withExtension: "tar.gz"),
              let v = bundle.url(forResource: "nxnative", withExtension: "version"),
              let version = (try? String(contentsOf: v, encoding: .utf8)).flatMap(Version.init(stamp:)) else { return nil }
        return (tar, version)
    }

    public static var defaultFolder: URL { Store.default.folder.appending(path: "nxnative") }

    public static func installed(at folder: URL) -> Version? {
        (try? String(contentsOf: folder.appending(path: stampName), encoding: .utf8)).flatMap(Version.init(stamp:))
    }

    public static func installedVersion(at folder: URL) -> String? { installed(at: folder)?.sha }

    /// Whether the app's own copy should replace what is unpacked: nothing is there, or the app ships a newer commit than
    /// the one installed (a launcher update). An engine downloaded later than the app's copy is kept. Without both dates,
    /// any other commit is replaced.
    public static func shouldInstallBundled(installed: Version?, bundled: Version) -> Bool {
        guard let installed else { return true }
        if installed.sha == bundled.sha { return false }
        guard let a = installed.date, let b = bundled.date else { return true }
        return b > a
    }

    public static func shortVersion(_ v: String) -> String { String(v.prefix(7)) }

    public struct UnpackError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Unpacks the tarball into `folder` unless the folder already holds this version. The new copy is made beside the old one
    /// and swapped in only when complete, so a failed unpack leaves the old engine in place. GitHub's tarballs wrap the tree
    /// in one folder: `stripComponents` 1 drops it.
    public static func unpack(tarball: URL, version: Version, stripComponents: Int = 0, to folder: URL) async throws {
        if installedVersion(at: folder) == version.sha { return }
        let fm = FileManager.default
        let partial = folder.deletingLastPathComponent().appending(path: folder.lastPathComponent + ".partial")
        try? fm.removeItem(at: partial)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        let tail = TailLog()
        let status = await ProcessLines.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", tarball.path, "-C", partial.path, "--strip-components", String(stripComponents)]) { tail.append($0) }
        guard status == 0 else {
            try? fm.removeItem(at: partial)
            throw UnpackError(message: "could not unpack nxnative: \(tail.last ?? "tar exit \(status.map(String.init) ?? "?")")")
        }
        try version.stamp.write(to: partial.appending(path: stampName), atomically: true, encoding: .utf8)
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
