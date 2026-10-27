import AppKit
import LauncherCore
import Observation
import SwiftUI

enum Route: Hashable {
    case home, all, recent, favorites, graphics(String), builds, playtime, settings
}

/// A Settings row to scroll to and highlight, when a fix button elsewhere sends the user there.
enum SettingsFocus: Hashable { case engine, keys }

/// One build in the queue: its request, its folded progress and its log.
@MainActor @Observable
final class BuildJob: Identifiable {
    let id = UUID()
    let request: BuildRequest
    let title: String
    let titleID: String?
    let started = Date()
    var progress = BuildProgress()
    var log: [String] = []
    var outcome: BuildOutcome?
    var app: GameBundle?
    @ObservationIgnored var runner: BuildRunner?

    init(request: BuildRequest, title: String, titleID: String?) {
        self.request = request; self.title = title; self.titleID = titleID
    }

    var isActive: Bool { outcome == nil }

    func appendLog(_ line: String) {
        log.append(line)
        if log.count > 2_000 { log.removeFirst(log.count - 2_000) }
    }
}

@MainActor @Observable
final class AppModel {
    // Settings: paths and the appearance, kept in UserDefaults (never in the repository; the keys file is never read by the launcher).
    // An empty checkoutPath means the nxnative shipped in the app.
    var checkoutPath: String { didSet { defaults.set(checkoutPath, forKey: "checkoutPath"); reloadCatalog() } }
    var keysPath: String { didSet { defaults.set(keysPath, forKey: "keysPath") } }
    var pythonPath: String { didSet { defaults.set(pythonPath, forKey: "pythonPath") } }
    var appearance: Appearance { didSet { defaults.set(try? JSONEncoder().encode(appearance), forKey: "appearance") } }

    var route: Route = .home
    var detail: GameBundle?
    var search = ""
    var showingAddGame = false
    var settingsFocus: SettingsFocus?

    private(set) var games: [GameBundle] = []
    private(set) var catalog = Catalog()
    private(set) var playtime = PlaytimeLog()
    private(set) var library = LibraryState()
    private(set) var builds: [BuildJob] = []
    private(set) var icons: [String: NSImage] = [:]
    private(set) var palettes: [String: Palette] = [:]
    private(set) var sizes: [String: Int64] = [:]
    var preflight: [Preflight.Check] = []
    private(set) var engineSource: Preflight.EngineSource = .custom
    /// The checks whose fix is running, and the last line each one wrote (or its error).
    private(set) var fixing: Set<String> = []
    private(set) var fixStatus: [String: String] = [:]

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let store = Store.default
    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private var launcher: GameLauncher?

    init() {
        checkoutPath = defaults.string(forKey: "checkoutPath") ?? ""
        keysPath = defaults.string(forKey: "keysPath") ?? ""
        pythonPath = defaults.string(forKey: "pythonPath") ?? Preflight.findPython()?.path ?? ""
        appearance = defaults.data(forKey: "appearance").flatMap { try? JSONDecoder().decode(Appearance.self, from: $0) } ?? Appearance()
        library = store.load(LibraryState.self, "library.json") ?? LibraryState()
        playtime = store.load(PlaytimeLog.self, "playtime.json") ?? PlaytimeLog()
        playtime.closeStale()
        reloadCatalog()
        rescan()
        prepareEngine()
        launcher = GameLauncher(
            began: { [weak self] id in self?.sessionBegan(id) },
            ended: { [weak self] id in self?.sessionEnded(id) })
        launcher?.adoptRunning()
        heartbeat = Timer.scheduledTimer(withTimeInterval: PlaytimeLog.heartbeat, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
        Task { await runPreflight() }
    }

    // MARK: Library

    var usesBundledEngine: Bool { checkoutPath.isEmpty }

    var checkoutURL: URL? {
        if !checkoutPath.isEmpty { return URL(fileURLWithPath: checkoutPath) }
        if case .bundled = engineSource { return Engine.defaultFolder }
        return nil
    }

    /// Unpacks the shipped nxnative when this version is not unpacked yet. A build without the tarball (swift run) has no bundled engine.
    func prepareEngine() {
        guard usesBundledEngine else { engineSource = .custom; return }
        guard let (tarball, version) = Engine.bundled() else {
            engineSource = .failed("this build of the launcher has no nxnative inside: choose a clone"); return
        }
        if Engine.installedVersion(at: Engine.defaultFolder) == version { engineSource = .bundled(version: version); reloadCatalog(); return }
        engineSource = .unpacking
        Task {
            do {
                try await Engine.unpack(tarball: tarball, version: version, to: Engine.defaultFolder)
                engineSource = .bundled(version: version)
            } catch {
                engineSource = .failed(error.localizedDescription)
            }
            reloadCatalog()
            await runPreflight()
        }
    }

    func useBundledEngine() {
        checkoutPath = ""
        prepareEngine()
        Task { await runPreflight() }
    }

    func reloadCatalog() {
        catalog = checkoutURL.map(Catalog.load) ?? Catalog()
    }

    func rescan() {
        games = library.scan()
        for g in games { loadArt(g) }
    }

    private func loadArt(_ g: GameBundle) {
        let id = g.titleID, icon = g.iconURL, url = g.url
        guard icons[id] == nil else { return }
        if let img = NSImage(contentsOf: icon) { icons[id] = img }
        Task.detached(priority: .utility) {
            // No palette for an icon without color: such a game wears the default window color.
            let p = Palette.from(imageAt: icon).flatMap { $0 == .fallback ? nil : $0 }
            let size = BundleSize.of(url)
            await MainActor.run { self.palettes[id] = p; self.sizes[id] = size }
        }
    }

    func palette(_ g: GameBundle?) -> Palette { g.flatMap { palettes[$0.titleID] } ?? appearance.defaultPalette }

    var libraryFolders: [URL] { library.folders }

    func addFolder(_ url: URL) {
        guard !library.folders.contains(url) else { return }
        library.folders.append(url); saveLibrary(); rescan()
    }

    func removeFolder(_ url: URL) {
        library.folders.removeAll { $0 == url }; saveLibrary(); rescan()
    }

    /// Adds .app bundles the user picked; reports how many were not nxnative games.
    @discardableResult
    func addApps(_ urls: [URL]) -> Int {
        var rejected = 0
        for u in urls {
            if let g = GameBundle.read(u) { library.add(app: u, titleID: g.titleID) } else { rejected += 1 }
        }
        saveLibrary(); rescan()
        return rejected
    }

    func remove(_ g: GameBundle) {
        library.remove(titleID: g.titleID); saveLibrary()
        if detail?.titleID == g.titleID { detail = nil }
        rescan()
    }

    func isFavorite(_ g: GameBundle) -> Bool { library.favorites.contains(g.titleID) }
    func toggleFavorite(_ g: GameBundle) { library.toggleFavorite(g.titleID); saveLibrary() }

    private func saveLibrary() { store.save(library, "library.json") }

    // MARK: Views of the library

    var recentGames: [GameBundle] {
        games.filter { playtime.lastPlayed($0.titleID) != nil }
            .sorted { (playtime.lastPlayed($0.titleID) ?? .distantPast) > (playtime.lastPlayed($1.titleID) ?? .distantPast) }
    }

    var favoriteGames: [GameBundle] { games.filter(isFavorite) }

    /// The hero of Home: the game played last, else the first game.
    var heroGame: GameBundle? { recentGames.first ?? games.first }

    func graphics(_ g: GameBundle) -> String? { catalog[g.titleID]?.graphics }

    var graphicsGroups: [(name: String, count: Int)] {
        let names = games.compactMap(graphics)
        return Dictionary(grouping: names, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.count > $1.count }
    }

    func games(for route: Route) -> [GameBundle] {
        switch route {
        case .recent: recentGames
        case .favorites: favoriteGames
        case let .graphics(name): games.filter { graphics($0) == name }
        default: games
        }
    }

    var searchResults: [GameBundle] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return games.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.titleID.localizedCaseInsensitiveContains(q)
            || (catalog[$0.titleID]?.engine.localizedCaseInsensitiveContains(q) ?? false) }
    }

    /// The colors the window wears: the open game's, else Home's hero.
    var theme: Palette { palette(detail ?? heroGame) }

    /// The filled buttons: the chosen color, else the theme's.
    var buttonRGB: RGB { appearance.buttonColor ?? theme.button }
    var buttonTint: Color { buttonRGB.color.opacity(appearance.buttonOpacity) }
    var buttonInk: Color { appearance.darkInk(on: buttonRGB) ? .black : .white }
    /// A tinted surface (sidebar, cards, search field), as strong as the user's tint opacity.
    func surface(_ c: RGB, _ alpha: Double) -> Color { c.color.opacity(appearance.tint(alpha)) }

    func metaLine(_ g: GameBundle) -> String {
        var parts: [String] = []
        if let gx = graphics(g) { parts.append(gx) }
        if let s = sizes[g.titleID] { parts.append(ByteCountFormatter.string(fromByteCount: s, countStyle: .file)) }
        return parts.isEmpty ? "v\(g.version)" : parts.joined(separator: " · ")
    }

    // MARK: Playing

    func play(_ g: GameBundle) { launcher?.open(g) }
    func isPlaying(_ g: GameBundle) -> Bool { playtime.isPlaying(g.titleID) }

    private func sessionBegan(_ titleID: String) {
        playtime.begin(titleID); store.save(playtime, "playtime.json")
    }

    private func sessionEnded(_ titleID: String) {
        playtime.end(titleID); store.save(playtime, "playtime.json")
    }

    private func beat() {
        guard playtime.sessions.contains(where: \.open) else { return }
        playtime.beat(); store.save(playtime, "playtime.json")
    }

    // MARK: Builds

    var activeBuild: BuildJob? { builds.first { $0.isActive && $0.runner != nil } }
    var activeCount: Int { builds.filter(\.isActive).count }

    func runPreflight() async {
        preflight = await Preflight.run(checkout: checkoutURL, source: engineSource,
                                        python: pythonPath.isEmpty ? nil : URL(fileURLWithPath: pythonPath),
                                        keys: keysPath.isEmpty ? nil : URL(fileURLWithPath: keysPath))
    }

    var readyToBuild: Bool { !preflight.isEmpty && preflight.allSatisfy(\.ok) }

    // MARK: Fixing what preflight found

    /// Runs a check's fix. Choosing a file happens in Settings: from anywhere else the button goes there and points at the row.
    func perform(_ fix: Preflight.Fix, for check: String) {
        switch fix {
        case .chooseKeys, .chooseEngine:
            let focus: SettingsFocus = fix == .chooseKeys ? .keys : .engine
            if route == .settings && !showingAddGame { choose(focus) } else {
                showingAddGame = false; detail = nil; route = .settings; settingsFocus = focus
            }
        case .installModules(let modules):
            let base = pythonPath.isEmpty ? Preflight.findPython() : URL(fileURLWithPath: pythonPath)
            guard let base else { return }
            runFix(check) { log in
                switch await PythonSetup.install(base: base, packages: PythonSetup.packages(for: modules), onLine: log) {
                case .success(let py): return .success(py)
                case .failure(let e): return .failure(e)
                }
            } done: { py in self.pythonPath = py.path }
        case .brewInstall(let formulae):
            let env = BuildRunner.environment()
            guard let brew = Preflight.which("brew", environment: env) else { return }
            runFix(check) { log in
                let status = await ProcessLines.run(brew, ["install"] + formulae, environment: env, onLine: log)
                return status == 0 ? .success(brew) : .failure(PythonSetup.InstallError(message: "brew install stopped (exit \(status.map(String.init) ?? "?"))"))
            } done: { _ in }
        case .openURL(let url, _):
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens the picker for a Settings row and keeps the choice.
    func choose(_ focus: SettingsFocus) {
        switch focus {
        case .keys:
            if let u = pick(directory: false) { keysPath = u.path }
        case .engine:
            if let u = pick(directory: true) { checkoutPath = u.path; prepareEngine() }
        }
        Task { await runPreflight() }
    }

    private func runFix(_ check: String, _ work: @escaping @Sendable (@escaping @Sendable (String) -> Void) async -> Result<URL, PythonSetup.InstallError>,
                        done: @escaping (URL) -> Void) {
        guard !fixing.contains(check) else { return }
        fixing.insert(check); fixStatus[check] = "starting…"
        Task {
            let result = await work { line in Task { @MainActor in self.fixStatus[check] = line } }
            fixing.remove(check)
            switch result {
            case .success(let url): fixStatus[check] = nil; done(url)
            case .failure(let e): fixStatus[check] = "failed: \(e.message)"
            }
            await runPreflight()
        }
    }

    func enqueueBuild(nspFolder: URL, language: String?) {
        guard let checkout = checkoutURL else { return }
        let id = Catalog.titleID(inFolder: nspFolder)
        let title = id.flatMap { catalog[$0]?.name } ?? nspFolder.lastPathComponent
        let req = BuildRequest(nspFolder: nspFolder, keysFile: URL(fileURLWithPath: keysPath), checkout: checkout,
                               python: URL(fileURLWithPath: pythonPath), language: language)
        builds.insert(BuildJob(request: req, title: title, titleID: id), at: 0)
        route = .builds; detail = nil
        startNextBuild()
    }

    /// Builds run one at a time: each uses every core and a lot of memory.
    private func startNextBuild() {
        guard activeBuild == nil, let job = builds.last(where: { $0.isActive && $0.runner == nil }) else { return }
        let runner = BuildRunner(request: job.request)
        job.runner = runner
        job.progress.phase = .running
        Task {
            let outcome = await runner.run(
                onEvent: { ev in Task { @MainActor in job.progress.apply(ev); if case let .say(m) = ev { job.appendLog(m) }; self.updateDock() } },
                onLog: { line in Task { @MainActor in job.appendLog(line) } })
            await MainActor.run { self.finish(job, outcome) }
        }
        updateDock()
    }

    private func finish(_ job: BuildJob, _ outcome: BuildOutcome) {
        var outcome = outcome
        if case .succeeded(nil) = outcome { outcome = .succeeded(app: findBuiltApp(job)) }
        job.outcome = outcome
        switch outcome {
        case let .succeeded(app):
            job.progress.phase = .succeeded
            if let app, let g = GameBundle.read(app) {
                job.app = g
                library.add(app: app, titleID: g.titleID); saveLibrary(); rescan()
                Notifier.post(title: "\(g.name) is ready", body: "Built with nxnative. Press Play in the launcher.")
            }
        case let .failed(msg):
            job.progress.phase = .failed(msg)
            Notifier.post(title: "Build failed: \(job.title)", body: msg)
        case .cancelled:
            job.progress.phase = .cancelled
        }
        job.runner = nil
        updateDock()
        startNextBuild()
    }

    /// No path in the script's output: the newest nxnative app in the NSP folder (or beside -o) changed since the build started.
    private func findBuiltApp(_ job: BuildJob) -> URL? {
        let folder = job.request.output?.deletingLastPathComponent() ?? job.request.nspFolder
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items.filter { $0.pathExtension == "app" }
            .compactMap { u -> (URL, Date)? in
                guard let g = GameBundle.read(u), job.titleID == nil || g.titleID == job.titleID,
                      let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d >= job.started.addingTimeInterval(-5)
                else { return nil }
                return (u, d)
            }
            .max { $0.1 < $1.1 }?.0
    }

    func cancel(_ job: BuildJob) {
        if let runner = job.runner { runner.cancel() }
        else if job.isActive { job.outcome = .cancelled; job.progress.phase = .cancelled }
    }

    func clearFinishedBuilds() { builds.removeAll { !$0.isActive } }

    private func updateDock() {
        NSApp?.dockTile.badgeLabel = activeBuild.map { "\(Int($0.progress.fraction * 100))%" }
    }
}
