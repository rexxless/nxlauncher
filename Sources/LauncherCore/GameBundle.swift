import Foundation

/// A Mac app packed by nxnative (`dm/mac/pack_app.py`): its Info.plist carries DMTitleID beside the usual bundle keys.
public struct GameBundle: Equatable, Hashable, Sendable, Codable, Identifiable {
    public var id: String { titleID }
    public var url: URL
    public var titleID: String
    public var name: String
    public var version: String
    public var bundleID: String
    public var language: String

    public init(url: URL, titleID: String, name: String, version: String, bundleID: String, language: String) {
        self.url = url; self.titleID = titleID; self.name = name; self.version = version; self.bundleID = bundleID; self.language = language
    }

    /// Reads an app bundle; nil when it is not an nxnative game.
    public static func read(_ url: URL) -> GameBundle? {
        let plist = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let titleID = info["DMTitleID"] as? String, !titleID.isEmpty else { return nil }
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        return GameBundle(url: url, titleID: titleID.uppercased(), name: name,
                          version: info["CFBundleShortVersionString"] as? String ?? "",
                          bundleID: info["CFBundleIdentifier"] as? String ?? "org.nxnative.\(titleID.lowercased())",
                          language: info["DMLanguage"] as? String ?? "")
    }

    public var iconURL: URL { url.appending(path: "Contents/Resources/AppIcon.icns") }

    /// Where the packed app keeps the game's save and its log (`dm/mac/launcher.c`).
    public func saveFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Application Support/nxnative/\(titleID)")
    }
    public func logFile(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Logs/nxnative/\(titleID).log")
    }

    /// The nxnative bundle-ID prefix: games opened outside the launcher are recognised by it.
    public static let bundlePrefix = "org.nxnative."
}

public enum BundleSize {
    /// Allocated size of a folder tree; APFS clones are counted at full size, as Finder does.
    public static func of(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true { total += Int64(v.totalFileAllocatedSize ?? 0) }
        }
        return total
    }
}
