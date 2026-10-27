import Foundation

/// The state of one build, folded from its events: what the progress panel draws.
public struct BuildProgress: Equatable, Sendable {
    public struct Stage: Equatable, Sendable, Identifiable {
        public var id: Int { k }
        public var k: Int
        public var name: String
        public var ok: Bool?          // nil while running
        public var summary: String = ""
        public var elapsed: Double = 0
    }

    public enum Phase: Equatable, Sendable { case queued, running, succeeded, failed(String), cancelled }

    public var phase: Phase = .queued
    public var stageCount = 0
    public var stages: [Stage] = []
    public var step = ""
    public var stageFraction: Double?     // nil: the stage's work cannot be counted
    public var eta: Double?
    public var detail = ""                // "1.2 / 3.4 GB", the count and note of the current step
    public var messages: [String] = []

    public init() {}

    public var current: Stage? { stages.last { $0.ok == nil } }

    /// The whole build from 0 to 1: finished stages, plus the running stage's own fraction (half a stage when it cannot be counted).
    public var fraction: Double {
        if phase == .succeeded { return 1 }
        guard stageCount > 0 else { return 0 }
        let finished = stages.filter { $0.ok != nil }.count
        let running = current == nil ? 0 : (stageFraction ?? 0.5)
        return min(1, (Double(finished) + running) / Double(stageCount))
    }

    public mutating func apply(_ event: BuildEvent) {
        switch event {
        case let .stage(k, n, name, step):
            phase = .running; stageCount = max(n, k)
            stages.removeAll { $0.k == k }
            stages.append(Stage(k: k, name: name, ok: nil))
            self.step = step; stageFraction = nil; eta = nil; detail = ""
        case let .step(_, _, step):
            self.step = step; stageFraction = nil; eta = nil; detail = ""
        case let .progress(p):
            step = p.step; stageFraction = p.frac; eta = p.eta
            detail = Self.count(p)
        case let .stageEnd(k, _, ok, summary, elapsed):
            if let i = stages.firstIndex(where: { $0.k == k }) {
                stages[i].ok = ok; stages[i].summary = summary; stages[i].elapsed = elapsed
            }
            stageFraction = nil; eta = nil; detail = ""
        case let .say(msg):
            messages.append(msg)
        case .unknown:
            break
        }
    }

    static func count(_ p: BuildEvent.Progress) -> String {
        var parts: [String] = []
        if let done = p.done {
            let fmt: (Double) -> String = p.unit == "B"
                ? { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
                : { String(Int($0)) }
            parts.append(p.total.map { "\(fmt(done)) / \(p.estimated ? "~" : "")\(fmt($0))" } ?? fmt(done))
        }
        if !p.note.isEmpty { parts.append(p.note) }
        return parts.joined(separator: " · ")
    }
}
