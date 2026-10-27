import Foundation

/// Newer versions of the launcher itself, from the GitHub releases of its repository: the latest release's tag is
/// compared with the running version, and installing one downloads its disk image, checks the app inside and swaps it
/// in for the running app after the launcher quits.
public enum LauncherUpdate {
    public static let repo = "rexxless/nxlauncher"

    public struct Release: Equatable, Sendable {
        /// The tag without its v: v1.2.0 → 1.2.0.
        public let version: String
        public let notes: String
        public let page: URL
        public let dmg: URL?
    }

    public typealias UpdateError = EngineUpdate.UpdateError

    /// The latest release, or nil when it is not newer than `current`.
    public static func check(current: String, session: URLSession = .shared) async throws -> Release? {
        let data: Data
        do {
            data = try await EngineUpdate.get("https://api.github.com/repos/\(repo)/releases/latest", session)
        } catch let e as UpdateError where e.status == 404 {
            throw UpdateError(message: "no published release found on GitHub")
        }
        let release = try parseRelease(data)
        return isNewer(release.version, than: current) ? release : nil
    }

    /// Compares dotted versions number by number. Whatever follows a dash (a build past a tag: 1.1.0-3-gabc) is ignored.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            let core = v.hasPrefix("v") ? v.dropFirst() : Substring(v)
            return (core.split(separator: "-").first ?? "").split(separator: ".").map { Int($0) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private struct ReleaseJSON: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let body: String?
        let html_url: URL
        let draft: Bool?
        let assets: [Asset]
    }

    static func parseRelease(_ data: Data) throws -> Release {
        guard let r = try? JSONDecoder().decode(ReleaseJSON.self, from: data), r.draft != true else {
            throw UpdateError(message: "GitHub's answer could not be read")
        }
        let version = r.tag_name.hasPrefix("v") ? String(r.tag_name.dropFirst()) : r.tag_name
        return Release(version: version, notes: r.body ?? "", page: r.html_url,
                       dmg: r.assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url)
    }

    /// Release notes up to the line of dashes before the checksum, without their install steps (the update does those).
    public static func changes(in notes: String) -> String {
        var out: [Substring] = [], skipping = false
        for line in notes.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("---") { break }
            if line.hasPrefix("## ") { skipping = line.lowercased().contains("install") }
            if !skipping { out.append(line) }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Downloads the release's disk image and copies the app inside it into `folder`, after checking that it is this
    /// launcher (same bundle ID) at the release's version. Returns the copied app.
    public static func download(_ release: Release, bundleID: String, to folder: URL, session: URLSession = .shared) async throws -> URL {
        guard let url = release.dmg else { throw UpdateError(message: "the release has no disk image") }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let (tmp, response) = try await session.download(from: url)
        try EngineUpdate.checkResponse(response)
        let dmg = folder.appending(path: "NxLauncher-\(release.version).dmg")
        try? fm.removeItem(at: dmg)
        try fm.moveItem(at: tmp, to: dmg)
        defer { try? fm.removeItem(at: dmg) }
        return try await stage(dmg: dmg, version: release.version, bundleID: bundleID, to: folder)
    }

    static func stage(dmg: URL, version: String, bundleID: String, to folder: URL) async throws -> URL {
        let fm = FileManager.default
        let mount = folder.appending(path: "mount-\(UUID().uuidString)")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: mount) }
        let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")
        let tail = TailLog()
        guard await ProcessLines.run(hdiutil, ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path], onLine: { tail.append($0) }) == 0 else {
            throw UpdateError(message: "could not open the disk image: \(tail.last ?? "hdiutil failed")")
        }
        let staged = folder.appending(path: "NxLauncher.app")
        let copied: Result<Void, UpdateError>
        do {
            try check(appIn: mount, version: version, bundleID: bundleID)
            try? fm.removeItem(at: staged)
            let status = await ProcessLines.run(URL(fileURLWithPath: "/usr/bin/ditto"), [mount.appending(path: "NxLauncher.app").path, staged.path]) { tail.append($0) }
            copied = status == 0 ? .success(()) : .failure(UpdateError(message: "could not copy the new app: \(tail.last ?? "ditto failed")"))
        } catch {
            copied = .failure(error as? UpdateError ?? UpdateError(message: error.localizedDescription))
        }
        _ = await ProcessLines.run(hdiutil, ["detach", mount.path, "-force"]) { _ in }
        try copied.get()
        // The copy's signature must still match its contents.
        guard await ProcessLines.run(URL(fileURLWithPath: "/usr/bin/codesign"), ["--verify", "--deep", "--strict", staged.path], onLine: { tail.append($0) }) == 0 else {
            try? fm.removeItem(at: staged)
            throw UpdateError(message: "the new app's signature does not match its contents")
        }
        return staged
    }

    /// The disk image must hold NxLauncher.app with this launcher's bundle ID and the release's version.
    static func check(appIn folder: URL, version: String, bundleID: String) throws {
        let plist = folder.appending(path: "NxLauncher.app/Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw UpdateError(message: "the disk image holds no NxLauncher app")
        }
        guard info["CFBundleIdentifier"] as? String == bundleID else { throw UpdateError(message: "the disk image holds another app") }
        guard info["CFBundleShortVersionString"] as? String == version else {
            throw UpdateError(message: "the app in the disk image is not version \(version)")
        }
    }

    /// Why the running app cannot be replaced in place, if it cannot: macOS runs a downloaded app that was never moved
    /// from a read-only copy (App Translocation), and an app in a folder the user cannot write to cannot be swapped.
    public static func cannotReplace(_ app: URL, fileManager fm: FileManager = .default) -> String? {
        if app.path.contains("/AppTranslocation/") { return "move NxLauncher to Applications first, then update" }
        if !fm.isWritableFile(atPath: app.deletingLastPathComponent().path) { return "the folder holding NxLauncher cannot be written to" }
        return nil
    }

    /// Starts a helper that waits for this process to quit, puts `staged` in place of `app` and opens it. Quit right after.
    public static func relaunch(replacing app: URL, with staged: URL, pid: Int32 = ProcessInfo.processInfo.processIdentifier) throws {
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$2.old" && mv "$2" "$2.old" && mv "$3" "$2" && rm -rf "$2.old"
        [ -e "$2" ] || mv "$2.old" "$2"
        /usr/bin/open "$2"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", String(pid), app.path, staged.path]
        try p.run()
    }
}
