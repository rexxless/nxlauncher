import Foundation

/// Checks that a build can start: the checkout, Python and its modules, the keys file, an Apple silicon Mac.
public struct Preflight: Sendable {
    public struct Check: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String
        public var ok: Bool
        public var detail: String
    }

    public static let pythonCandidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]

    /// The first Python 3 that exists, preferring Homebrew's (the system one usually lacks the modules nxnative needs).
    public static func findPython(fileManager fm: FileManager = .default) -> URL? {
        pythonCandidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    public static func isCheckout(_ url: URL, fileManager fm: FileManager = .default) -> Bool {
        fm.fileExists(atPath: url.appending(path: "scripts/build_ipa_from_nsp.py").path)
            && fm.fileExists(atPath: url.appending(path: "dm/games/README.md").path)
    }

    public static var isAppleSilicon: Bool {
        var v: Int32 = 0; var n = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &v, &n, nil, 0) == 0 && v == 1
    }

    /// Runs every check. The keys file is only tested for being readable: its contents are never opened here.
    public static func run(checkout: URL?, python: URL?, keys: URL?) async -> [Check] {
        let fm = FileManager.default
        var out: [Check] = []
        out.append(Check(name: "Apple silicon", ok: isAppleSilicon, detail: isAppleSilicon ? "" : "nxnative's Mac host needs an Apple silicon Mac"))
        if let checkout, isCheckout(checkout) {
            out.append(Check(name: "nxnative checkout", ok: true, detail: checkout.lastPathComponent))
        } else {
            out.append(Check(name: "nxnative checkout", ok: false, detail: "choose the folder of a clone of the nxnative repository"))
        }
        if let python, fm.isExecutableFile(atPath: python.path) {
            let missing = await missingModules(python: python)
            out.append(Check(name: "Python modules", ok: missing.isEmpty,
                             detail: missing.isEmpty ? "lz4, capstone, fontTools" : "missing: \(missing.joined(separator: ", ")) — pip3 install \(missing.map(pipName).joined(separator: " "))"))
        } else {
            out.append(Check(name: "Python modules", ok: false, detail: "Python 3 not found — brew install python"))
        }
        if let keys, fm.isReadableFile(atPath: keys.path) {
            out.append(Check(name: "Keys file", ok: true, detail: "readable"))
        } else {
            out.append(Check(name: "Keys file", ok: false, detail: "choose your prod.keys file"))
        }
        return out
    }

    static func pipName(_ module: String) -> String { module == "fontTools" ? "fonttools" : module }

    static func missingModules(python: URL) async -> [String] {
        let modules = ["lz4", "capstone", "fontTools"]
        let code = "import importlib.util as u\nprint(' '.join(m for m in \(modules.map { "'\($0)'" }) if u.find_spec(m) is None))"
        let p = Process(); p.executableURL = python; p.arguments = ["-c", code]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return modules }
        let data = await Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return modules }
        return String(decoding: data, as: UTF8.self).split(separator: " ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
