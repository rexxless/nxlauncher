import Foundation

/// The games nxnative has a profile for, read from the checkout's games table (`dm/games/README.md`, section "Games").
public struct Catalog: Sendable {
    public struct Entry: Equatable, Sendable {
        public var titleID: String
        public var name: String
        public var build: String
        public var sdk: String
        public var engine: String
        public var graphics: String
        public var note: String   // the note's path relative to dm/games
    }

    public private(set) var entries: [String: Entry] = [:]

    public init(entries: [Entry] = []) {
        for e in entries { self.entries[e.titleID] = e }
    }

    public subscript(titleID: String) -> Entry? { entries[titleID.uppercased()] }

    public static func load(checkout: URL) -> Catalog {
        let url = checkout.appending(path: "dm/games/README.md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return Catalog() }
        return parse(text)
    }

    /// Rows look like: | [Name](0100…/README.md) | `0100…` | 1.0.1 | 6.4.0 | Engine | NVN |
    public static func parse(_ markdown: String) -> Catalog {
        var out: [Entry] = []
        for line in markdown.split(separator: "\n") where line.hasPrefix("| [") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 8 else { continue }
            let link = cells[1]
            guard let close = link.range(of: "]("), link.hasSuffix(")") else { continue }
            let name = String(link[link.index(after: link.startIndex)..<close.lowerBound])
            let note = String(link[close.upperBound..<link.index(before: link.endIndex)])
            let id = cells[2].trimmingCharacters(in: CharacterSet(charactersIn: "`")).uppercased()
            guard id.count == 16 else { continue }
            out.append(Entry(titleID: id, name: name, build: cells[3], sdk: cells[4], engine: cells[5], graphics: cells[6], note: note))
        }
        return Catalog(entries: out)
    }

    /// The base game's title ID named in an NSP folder's file names ("Game [0100ABCD12345800][v65536].nsp"): an update's or DLC's ID maps to its base game's.
    public static func titleID(inFolder folder: URL) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return titleID(inNames: names)
    }

    public static func titleID(inNames names: [String]) -> String? {
        var found: [String] = []
        for n in names where [".nsp", ".nsz", ".xci", ".xcz"].contains(where: n.lowercased().hasSuffix) {
            if let r = n.range(of: "0100[0-9A-Fa-f]{12}", options: .regularExpression) { found.append(String(n[r]).uppercased()) }
        }
        // The base game's ID ends in 000; an update's in 800, a DLC's in its own digits with the 13th digit one higher.
        let bases = found.map(baseID)
        return bases.isEmpty ? nil : Dictionary(grouping: bases, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }

    public static func baseID(_ id: String) -> String {
        guard id.count == 16, let v = UInt64(id, radix: 16) else { return id }
        let low = v & 0xFFF
        // DLC: …X001-…XFFF with bit 12 set relative to the base (base | 0x1000 | n); updates: base | 0x800.
        let base = low == 0x800 ? v & ~0xFFF : (low != 0 ? (v & ~0xFFF) - 0x1000 : v)
        return String(format: "%016llX", base)
    }
}
