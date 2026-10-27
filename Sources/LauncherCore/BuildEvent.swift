import Foundation

/// One line of `build_ipa_from_nsp.py --progress json` output.
/// The script writes the events stage, step, progress, stage_end and say; anything else is kept as `.unknown`.
public enum BuildEvent: Equatable, Sendable {
    case stage(k: Int, n: Int, name: String, step: String)
    case step(k: Int, name: String, step: String)
    case progress(Progress)
    case stageEnd(k: Int, name: String, ok: Bool, summary: String, elapsed: Double)
    case say(String)
    case unknown(String)

    public struct Progress: Equatable, Sendable {
        public var k: Int
        public var name: String
        public var step: String
        public var done: Double?
        public var total: Double?
        public var unit: String
        public var estimated: Bool
        public var note: String
        public var frac: Double?
        public var eta: Double?
        public var elapsed: Double

        public init(k: Int, name: String, step: String = "", done: Double? = nil, total: Double? = nil, unit: String = "",
                    estimated: Bool = false, note: String = "", frac: Double? = nil, eta: Double? = nil, elapsed: Double = 0) {
            self.k = k; self.name = name; self.step = step; self.done = done; self.total = total; self.unit = unit
            self.estimated = estimated; self.note = note; self.frac = frac; self.eta = eta; self.elapsed = elapsed
        }
    }

    /// Parses one stdout line. A line that is not a JSON object (a tool printing past the progress view) is `nil`.
    public static func parse(_ line: String) -> BuildEvent? {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ev = obj["ev"] as? String else { return nil }
        func int(_ k: String) -> Int { (obj[k] as? NSNumber)?.intValue ?? 0 }
        func num(_ k: String) -> Double? { (obj[k] as? NSNumber)?.doubleValue }
        func str(_ k: String) -> String { obj[k] as? String ?? "" }
        switch ev {
        case "stage": return .stage(k: int("k"), n: int("n"), name: str("name"), step: str("step"))
        case "step": return .step(k: int("k"), name: str("name"), step: str("step"))
        case "progress":
            return .progress(Progress(k: int("k"), name: str("name"), step: str("step"), done: num("done"), total: num("total"),
                                      unit: str("unit"), estimated: obj["est"] as? Bool ?? false, note: str("note"),
                                      frac: num("frac"), eta: num("eta"), elapsed: num("elapsed") ?? 0))
        case "stage_end":
            return .stageEnd(k: int("k"), name: str("name"), ok: obj["ok"] as? Bool ?? true, summary: str("summary"), elapsed: num("elapsed") ?? 0)
        case "say": return .say(str("msg"))
        default: return .unknown(ev)
        }
    }
}
