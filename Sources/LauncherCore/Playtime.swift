import Foundation

/// Play sessions of every game, kept as a small JSON file. A session that is still open has a heartbeat instead of an end,
/// so a launcher that quits or crashes mid-game loses at most one heartbeat interval.
public struct PlaytimeLog: Codable, Equatable, Sendable {
    public struct Session: Codable, Equatable, Sendable {
        public var titleID: String
        public var start: Date
        public var end: Date
        public var open: Bool = false

        public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    }

    public static let minimumSession: TimeInterval = 10
    public static let heartbeat: TimeInterval = 60

    public var sessions: [Session] = []

    public init(sessions: [Session] = []) { self.sessions = sessions }

    public mutating func begin(_ titleID: String, at now: Date = .now) {
        end(titleID, at: now)
        sessions.append(Session(titleID: titleID, start: now, end: now, open: true))
    }

    public mutating func beat(at now: Date = .now) {
        for i in sessions.indices where sessions[i].open { sessions[i].end = now }
    }

    public mutating func end(_ titleID: String, at now: Date = .now) {
        for i in sessions.indices.reversed() where sessions[i].open && sessions[i].titleID == titleID {
            sessions[i].end = now; sessions[i].open = false
        }
        prune()
    }

    /// Sessions left open by a launcher that did not see the game quit end at their last heartbeat.
    public mutating func closeStale() {
        for i in sessions.indices where sessions[i].open { sessions[i].open = false }
        prune()
    }

    private mutating func prune() {
        sessions.removeAll { !$0.open && $0.duration < Self.minimumSession }
    }

    public func total(_ titleID: String) -> TimeInterval {
        sessions.filter { $0.titleID == titleID }.reduce(0) { $0 + $1.duration }
    }

    public var total: TimeInterval { sessions.reduce(0) { $0 + $1.duration } }

    public func lastPlayed(_ titleID: String) -> Date? {
        sessions.filter { $0.titleID == titleID }.map(\.end).max()
    }

    public func isPlaying(_ titleID: String) -> Bool { sessions.contains { $0.open && $0.titleID == titleID } }

    /// Seconds played in each of the last `weeks` weeks (oldest first), each starting on the calendar's first weekday.
    public func weekly(_ titleID: String? = nil, weeks: Int = 8, now: Date = .now, calendar: Calendar = .current) -> [(week: Date, seconds: TimeInterval)] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let starts = (0..<weeks).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
        return starts.map { start in
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            let secs = sessions.filter { titleID == nil || $0.titleID == titleID }.reduce(0.0) { acc, s in
                let overlap = min(s.end, end).timeIntervalSince(max(s.start, start))
                return acc + max(0, overlap)
            }
            return (start, secs)
        }
    }

    /// "12 h 34 m", "34 m", "0 m".
    public static func format(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? "\(m / 60) h \(m % 60) m" : "\(m) m"
    }
}

/// Loads and saves JSON documents in the launcher's Application Support folder.
public struct Store: Sendable {
    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    public static var `default`: Store {
        Store(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "NxLauncher"))
    }

    public func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appending(path: name)) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(type, from: data)
    }

    public func save<T: Encodable>(_ value: T, _ name: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? e.encode(value) { try? data.write(to: folder.appending(path: name), options: .atomic) }
    }
}
