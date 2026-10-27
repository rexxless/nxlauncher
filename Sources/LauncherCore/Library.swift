import Foundation

/// The games the launcher shows: apps the user added or built, and the apps found in the library folders.
public struct LibraryState: Codable, Equatable, Sendable {
    public var folders: [URL] = []      // scanned for nxnative apps (two levels deep: an NSP folder's app sits beside its NSPs)
    public var apps: [URL] = []         // added one by one, or produced by a build
    public var hidden: [String] = []    // title IDs removed from the library (the app itself is left alone)
    public var favorites: [String] = []

    public init() {}

    /// Every nxnative game reachable now, one per title ID (an app added by hand wins over one found by a scan), sorted by name.
    public func scan(fileManager fm: FileManager = .default) -> [GameBundle] {
        var byID: [String: GameBundle] = [:]
        for folder in folders {
            for app in Self.apps(in: folder, depth: 2, fileManager: fm) {
                if let g = GameBundle.read(app), byID[g.titleID] == nil { byID[g.titleID] = g }
            }
        }
        for app in apps { if let g = GameBundle.read(app) { byID[g.titleID] = g } }
        for id in hidden { byID[id] = nil }
        return byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func apps(in folder: URL, depth: Int, fileManager fm: FileManager) -> [URL] {
        guard depth > 0, let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for item in items where (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            if item.pathExtension == "app" { out.append(item) }
            else if !item.lastPathComponent.hasSuffix("_build") && !item.lastPathComponent.hasSuffix("-work") {
                out += apps(in: item, depth: depth - 1, fileManager: fm)   // nxnative's own build and work folders are large and hold no apps
            }
        }
        return out
    }

    public mutating func add(app: URL, titleID: String) {
        if !apps.contains(app) { apps.append(app) }
        hidden.removeAll { $0 == titleID }
    }

    public mutating func remove(titleID: String) {
        if !hidden.contains(titleID) { hidden.append(titleID) }
        apps.removeAll { GameBundle.read($0)?.titleID == titleID }
    }

    public mutating func toggleFavorite(_ titleID: String) {
        if let i = favorites.firstIndex(of: titleID) { favorites.remove(at: i) } else { favorites.append(titleID) }
    }
}
