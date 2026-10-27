import Foundation

/// A private Python environment with the modules nxnative's build script imports, so the system's or Homebrew's
/// Python is never changed (Homebrew's refuses a plain pip install anyway).
public enum PythonSetup {
    public static var venvFolder: URL { Store.default.folder.appending(path: "python") }

    public static func python(in venv: URL) -> URL { venv.appending(path: "bin/python3") }

    /// The pip packages for the missing modules (`fontTools` installs as `fonttools`, `backports.zstd` as `backports.zstd`).
    public static func packages(for modules: [String]) -> [String] { modules.map(Preflight.pipName) }

    /// Makes the venv from `base` (or reuses it) and installs `packages` into it. Returns the venv's Python, or the last line of the failing step.
    public static func install(base: URL, packages: [String], venv: URL = venvFolder,
                               onLine: @escaping @Sendable (String) -> Void) async -> Result<URL, InstallError> {
        let env = BuildRunner.environment()
        let py = python(in: venv)
        let tail = TailLog()
        let log: @Sendable (String) -> Void = { tail.append($0); onLine($0) }
        var steps: [(URL, [String])] = []
        if !FileManager.default.isExecutableFile(atPath: py.path) { steps.append((base, ["-m", "venv", venv.path])) }
        steps.append((py, ["-m", "pip", "install", "--disable-pip-version-check", "--upgrade", "pip"]))
        steps.append((py, ["-m", "pip", "install", "--disable-pip-version-check"] + packages))
        for (exe, args) in steps {
            onLine("$ \(exe.lastPathComponent) \(args.joined(separator: " "))")
            let status = await ProcessLines.run(exe, args, environment: env, onLine: log)
            guard status == 0 else {
                return .failure(InstallError(message: tail.last ?? "\(exe.lastPathComponent) could not start"))
            }
        }
        return .success(py)
    }

    public struct InstallError: Error, Equatable {
        public let message: String
        public init(message: String) { self.message = message }
    }
}
