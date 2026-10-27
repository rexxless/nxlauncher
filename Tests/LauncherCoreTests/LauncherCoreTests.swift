import Foundation
import Testing
@testable import LauncherCore

// Fixtures are made up: no real game's files, names, icons or keys.

private func tempDir() throws -> URL {
    let u = FileManager.default.temporaryDirectory.appending(path: "nxl-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

private func fakeApp(in dir: URL, name: String, titleID: String) throws -> URL {
    let app = dir.appending(path: "\(name).app")
    try FileManager.default.createDirectory(at: app.appending(path: "Contents/Resources"), withIntermediateDirectories: true)
    let info: [String: Any] = ["CFBundleName": name, "CFBundleDisplayName": name, "CFBundleShortVersionString": "1.0.2",
                               "CFBundleIdentifier": "org.nxnative.\(titleID.lowercased())", "DMTitleID": titleID, "DMLanguage": "en-US"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appending(path: "Contents/Info.plist"))
    return app
}

@Suite struct Events {
    @Test func parsesEveryEvent() {
        #expect(BuildEvent.parse(#"{"ev":"stage","k":2,"n":7,"name":"extract","step":"base","t":1.0}"#) == .stage(k: 2, n: 7, name: "extract", step: "base"))
        #expect(BuildEvent.parse(#"{"ev":"step","k":2,"name":"extract","step":"update"}"#) == .step(k: 2, name: "extract", step: "update"))
        #expect(BuildEvent.parse(#"{"ev":"say","msg":"hello\nworld"}"#) == .say("hello\nworld"))
        #expect(BuildEvent.parse(#"{"ev":"stage_end","k":2,"name":"extract","ok":false,"summary":"x","elapsed":3.5}"#)
                == .stageEnd(k: 2, name: "extract", ok: false, summary: "x", elapsed: 3.5))
        #expect(BuildEvent.parse(#"{"ev":"later"}"#) == .unknown("later"))
        #expect(BuildEvent.parse("plain text") == nil)
        guard case let .progress(p)? = BuildEvent.parse(#"{"ev":"progress","k":1,"name":"a","step":"","done":5,"total":10,"unit":"B","est":true,"note":"","frac":0.5,"eta":null,"elapsed":2}"#)
        else { Issue.record("not a progress event"); return }
        #expect(p.frac == 0.5 && p.eta == nil && p.estimated && p.unit == "B")
    }

    @Test func foldsAStreamToCompletion() {
        let lines = [
            #"{"ev":"stage","k":1,"n":2,"name":"extract","step":""}"#,
            #"{"ev":"progress","k":1,"name":"extract","step":"","done":1,"total":4,"unit":"","est":false,"note":"","frac":0.25,"eta":9,"elapsed":1}"#,
            #"{"ev":"stage_end","k":1,"name":"extract","ok":true,"summary":"","elapsed":4}"#,
            #"{"ev":"stage","k":2,"n":2,"name":"pack","step":""}"#,
        ]
        var p = BuildProgress()
        lines.forEach { p.apply(BuildEvent.parse($0)!) }
        #expect(p.phase == .running)
        #expect(p.fraction == 0.75)   // one stage done, the running one uncountable (half)
        p.apply(.stageEnd(k: 2, name: "pack", ok: true, summary: "", elapsed: 1))
        #expect(p.fraction == 1.0)
        #expect(p.stages.map(\.ok) == [true, true])
    }

    @Test func outcomes() {
        let msgs = ["app name: G; version: 1.0; bundle ID: org.nxnative.x; app: /Volumes/Games/G/G.app",
                    "done: /Volumes/Games/G/G (Deluxe).app (2.1 GB, its game files APFS clones of the extracted ones, which take no space of their own); open it from Finder"]
        #expect(BuildOutcome.from(exitCode: 0, messages: msgs) == .succeeded(app: URL(fileURLWithPath: "/Volumes/Games/G/G (Deluxe).app")))
        #expect(BuildOutcome.from(exitCode: 0, messages: [msgs[0]]) == .succeeded(app: URL(fileURLWithPath: "/Volumes/Games/G/G.app")))
        #expect(BuildOutcome.from(exitCode: 130, messages: []) == .cancelled)
        #expect(BuildOutcome.from(exitCode: 1, messages: ["[RED] no NSP in the folder", "x"]) == .failed("no NSP in the folder"))
    }
}

@Suite struct Runner {
    /// A stand-in checkout whose build script is a shell script, run by /bin/sh in place of Python.
    private func checkout(script: String) throws -> URL {
        let dir = try tempDir()
        try FileManager.default.createDirectory(at: dir.appending(path: "scripts"), withIntermediateDirectories: true)
        try script.write(to: dir.appending(path: "scripts/build_ipa_from_nsp.py"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func streamsEventsAndSucceeds() async throws {
        let dir = try checkout(script: """
        echo '{"ev":"stage","k":1,"n":1,"name":"pack","step":""}'
        echo 'stray line'
        echo '{"ev":"stage_end","k":1,"name":"pack","ok":true,"summary":"","elapsed":0.1}'
        echo '{"ev":"say","msg":"done: /tmp/x/Fake Game.app (0.1 GB)"}'
        echo "args: $*" >&2
        """)
        let req = BuildRequest(nspFolder: dir, keysFile: dir.appending(path: "k"), checkout: dir, python: URL(fileURLWithPath: "/bin/sh"))
        let events = Box<[BuildEvent]>([]), logs = Box<[String]>([])
        let outcome = await BuildRunner(request: req).run(onEvent: { e in events.mutate { $0.append(e) } }, onLog: { l in logs.mutate { $0.append(l) } })
        #expect(outcome == .succeeded(app: URL(fileURLWithPath: "/tmp/x/Fake Game.app")))
        #expect(events.value.count == 3)
        #expect(logs.value.contains("stray line"))
        #expect(logs.value.contains { $0.contains("--platform mac-app --progress json") })
    }

    @Test func cancelEndsTheBuild() async throws {
        let dir = try checkout(script: """
        trap 'exit 130' INT
        echo '{"ev":"stage","k":1,"n":3,"name":"extract","step":""}'
        i=0; while [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done
        """)
        let req = BuildRequest(nspFolder: dir, keysFile: dir, checkout: dir, python: URL(fileURLWithPath: "/bin/sh"))
        let runner = BuildRunner(request: req)
        let started = Box(false)
        let task = Task { await runner.run(onEvent: { _ in started.mutate { $0 = true } }, onLog: { _ in }) }
        while !started.value { try await Task.sleep(for: .milliseconds(20)) }
        runner.cancel()
        #expect(await task.value == .cancelled)
    }

    @Test func eventsArriveWhileTheBuildRuns() async throws {
        let dir = try checkout(script: """
        echo '{"ev":"stage","k":1,"n":1,"name":"pack","step":""}'
        sleep 2
        """)
        let req = BuildRequest(nspFolder: dir, keysFile: dir, checkout: dir, python: URL(fileURLWithPath: "/bin/sh"))
        let start = Date(), firstEvent = Box<Date?>(nil)
        _ = await BuildRunner(request: req).run(onEvent: { _ in firstEvent.mutate { if $0 == nil { $0 = Date() } } }, onLog: { _ in })
        let at = try #require(firstEvent.value)
        #expect(at.timeIntervalSince(start) < 1.5)   // the progress bar moves during the build, not only at its end
    }

    @Test func pathIncludesHomebrew() {
        let env = BuildRunner.environment(base: ["PATH": "/usr/bin:/bin"])
        #expect(env["PATH"]!.hasPrefix("/opt/homebrew/bin:"))
    }
}

final class Box<T>: @unchecked Sendable {
    private let lock = NSLock(); private var v: T
    init(_ v: T) { self.v = v }
    var value: T { lock.withLock { v } }
    func mutate(_ f: (inout T) -> Void) { lock.withLock { f(&v) } }
}

@Suite struct Bundles {
    @Test func readsAndScans() throws {
        let dir = try tempDir()
        let nsp = dir.appending(path: "Some Game")
        try FileManager.default.createDirectory(at: nsp.appending(path: "0100000000AB0000_build"), withIntermediateDirectories: true)
        _ = try fakeApp(in: nsp, name: "Some Game", titleID: "0100000000AB0000")
        _ = try fakeApp(in: nsp.appending(path: "0100000000AB0000_build"), name: "Ignored", titleID: "0100000000AC0000")
        try FileManager.default.createDirectory(at: dir.appending(path: "Other.app/Contents"), withIntermediateDirectories: true)   // not nxnative

        var lib = LibraryState(); lib.folders = [dir]
        let games = lib.scan()
        #expect(games.map(\.titleID) == ["0100000000AB0000"])
        #expect(games[0].name == "Some Game" && games[0].version == "1.0.2")
        lib.remove(titleID: "0100000000AB0000")
        #expect(lib.scan().isEmpty)
        lib.add(app: games[0].url, titleID: "0100000000AB0000")
        #expect(lib.scan().count == 1)
    }
}

@Suite struct CatalogTests {
    let table = """
    ## Games

    | Game | Title ID | Build | SDK | Engine | Graphics |
    |---|---|---|---|---|---|
    | [Example Quest](0100000000AB0000/README.md) | `0100000000AB0000` | 1.0.1 | 6.4.0 | An engine | NVN |
    | [Example Racer, Asian release](0100000000CD0000/README.md) | `0100000000CD0000` | 1.00 (base) | 11.4.3 | Unity 2020.3 IL2CPP | Vulkan |
    """

    @Test func parsesRows() {
        let c = Catalog.parse(table)
        #expect(c.entries.count == 2)
        let e = c["0100000000ab0000"]
        #expect(e?.name == "Example Quest" && e?.graphics == "NVN" && e?.sdk == "6.4.0" && e?.note == "0100000000AB0000/README.md")
        #expect(c["0100000000CD0000"]?.build == "1.00 (base)")
    }

    @Test func baseIDs() {
        #expect(Catalog.baseID("0100000000AB0800") == "0100000000AB0000")   // update
        #expect(Catalog.baseID("0100000000AB1001") == "0100000000AB0000")   // DLC 1
        #expect(Catalog.baseID("0100000000AB0000") == "0100000000AB0000")
        #expect(Catalog.titleID(inNames: ["Example [0100000000AB0000][v0].nsp", "Example [0100000000AB0800][v65536].nsp", "readme.txt"]) == "0100000000AB0000")
        #expect(Catalog.titleID(inNames: ["notes.txt"]) == nil)
    }
}

@Suite struct PlaytimeTests {
    @Test func sessionsAndTotals() {
        var log = PlaytimeLog()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        log.begin("A", at: t0)
        #expect(log.isPlaying("A"))
        log.beat(at: t0 + 60)
        log.end("A", at: t0 + 3_700)
        log.begin("A", at: t0 + 4_000); log.end("A", at: t0 + 4_005)   // a failed start: dropped
        #expect(log.sessions.count == 1)
        #expect(log.total("A") == 3_700)
        #expect(PlaytimeLog.format(log.total("A")) == "1 h 1 m")
        #expect(log.lastPlayed("A") == t0 + 3_700)

        log.begin("B", at: t0); log.beat(at: t0 + 120); log.closeStale()   // the launcher quit mid-game
        #expect(log.total("B") == 120 && !log.isPlaying("B"))
        let weeks = log.weekly("A", weeks: 2, now: t0 + 3_700)
        #expect(weeks.count == 2 && weeks[1].seconds == 3_700 && weeks[0].seconds == 0)
    }

    @Test func storeRoundTrip() throws {
        let store = Store(folder: try tempDir())
        var log = PlaytimeLog(); log.begin("A", at: Date(timeIntervalSince1970: 0)); log.end("A", at: Date(timeIntervalSince1970: 100))
        store.save(log, "playtime.json")
        #expect(store.load(PlaytimeLog.self, "playtime.json") == log)
    }
}

@Suite struct PaletteTests {
    @Test func picksTheVividCluster() {
        let red = RGB(0.85, 0.1, 0.1), grey = RGB(0.5, 0.5, 0.5), blue = RGB(0.1, 0.3, 0.9)
        let p = Palette.from(pixels: Array(repeating: grey, count: 500) + Array(repeating: red, count: 400) + Array(repeating: blue, count: 124))
        #expect(p.base.r > p.base.g && p.base.r > p.base.b)   // red, not the grey majority
        #expect(p.deep.luminance < p.base.luminance)
        #expect(!p.isLight)
        #expect(Palette.from(pixels: []) == .fallback)
    }
}

@Suite struct FallbackColor {
    @Test func isACalmIndigo() {
        let b = Palette.fallback.base
        #expect(b.b > b.r && b.b > b.g)          // blue-violet, not red
        #expect(b.hsb.s < 0.7 && b.hsb.v < 0.7)  // muted
        #expect(!Palette.fallback.isLight)
    }

    @Test func buttonIsAVioletUnderWhiteText() {
        let f = Palette.fallback, b = f.button
        #expect(b.b > b.r && b.r > b.g)                  // violet
        #expect(b.hsb.v > f.base.hsb.v + 0.15)           // stands out from the base
        #expect(b.luminance <= 0.4)
    }
}

@Suite struct ButtonColor {
    @Test(arguments: [0.0, 0.15, 0.33, 0.5, 0.67, 0.85])
    func staysDarkEnoughForWhiteText(hue: Double) {
        var p = Palette.fallback
        p.accent = RGB(h: hue, s: 0.7, v: 1)
        #expect(p.button.luminance <= 0.4 + 1e-9)
        #expect(abs(p.button.hsb.h - p.accent.hsb.h) < 0.01)
    }
}

@Suite struct AppearanceTests {
    @Test func solidKeepsTheColor() {
        let main = RGB(0.2, 0.5, 0.4), p = Palette.solid(main)
        #expect(p.base == main)
        #expect(p.deep.luminance < p.base.luminance)
        #expect(abs(p.deep.hsb.h - main.hsb.h) < 0.01)
    }

    @Test func defaultsAndRoundTrip() throws {
        let empty = try JSONDecoder().decode(Appearance.self, from: Data("{}".utf8))
        #expect(empty == Appearance())
        #expect(empty.defaultPalette == .fallback)
        var a = Appearance()
        a.buttonLook = .solid; a.buttonColor = RGB(1, 0.9, 0.2); a.buttonOpacity = 0.8; a.mainColor = RGB(0.1, 0.4, 0.3); a.tintOpacity = 0.3
        #expect(try JSONDecoder().decode(Appearance.self, from: JSONEncoder().encode(a)) == a)
        #expect(a.defaultPalette.base == RGB(0.1, 0.4, 0.3))
    }

    @Test func tintScalesAndClamps() {
        var a = Appearance()
        #expect(a.tint(0.25) == 0.25)
        a.tintOpacity = 1
        #expect(a.tint(0.8) == 1)
        a.tintOpacity = 0
        #expect(a.tint(0.5) == 0)
    }

    @Test func darkInkOnlyOnLightOpaqueButtons() {
        var a = Appearance()
        #expect(a.darkInk(on: RGB(1, 0.95, 0.6)))
        #expect(!a.darkInk(on: Palette.fallback.button))
        a.buttonOpacity = 0.4
        #expect(!a.darkInk(on: RGB(1, 0.95, 0.6)))
    }
}

private func script(_ dir: URL, _ name: String, _ body: String) throws -> URL {
    let u = dir.appending(path: name)
    try ("#!/bin/sh\n" + body + "\n").write(to: u, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
    return u
}

@Suite struct EngineTests {
    private func tarball(_ dir: URL, _ text: String) async throws -> URL {
        let src = dir.appending(path: "src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: src.appending(path: "scripts"), withIntermediateDirectories: true)
        try text.write(to: src.appending(path: "scripts/build_ipa_from_nsp.py"), atomically: true, encoding: .utf8)
        let tar = dir.appending(path: "\(UUID().uuidString).tar.gz")
        let status = await ProcessLines.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-czf", tar.path, "-C", src.path, "."]) { _ in }
        #expect(status == 0)
        return tar
    }

    @Test func unpacksOncePerVersion() async throws {
        let dir = try tempDir(), folder = dir.appending(path: "nxnative")
        let v1 = try await tarball(dir, "one")
        try await Engine.unpack(tarball: v1, version: .init(sha: "aaaa", date: nil), to: folder)
        #expect(Engine.installedVersion(at: folder) == "aaaa")
        let file = folder.appending(path: "scripts/build_ipa_from_nsp.py")
        #expect(try String(contentsOf: file, encoding: .utf8) == "one")

        try "built".write(to: folder.appending(path: "gen.txt"), atomically: true, encoding: .utf8)
        try await Engine.unpack(tarball: v1, version: .init(sha: "aaaa", date: nil), to: folder)   // same version: left alone
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "gen.txt").path))

        let v2 = try await tarball(dir, "two")
        try await Engine.unpack(tarball: v2, version: .init(sha: "bbbb", date: nil), to: folder)
        #expect(try String(contentsOf: file, encoding: .utf8) == "two")
        #expect(Engine.installedVersion(at: folder) == "bbbb")
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "gen.txt").path))
    }

    @Test func aBadTarballKeepsTheOldEngine() async throws {
        let dir = try tempDir(), folder = dir.appending(path: "nxnative")
        try await Engine.unpack(tarball: try await tarball(dir, "one"), version: .init(sha: "aaaa", date: nil), to: folder)
        let bad = dir.appending(path: "bad.tar.gz")
        try "not a tarball".write(to: bad, atomically: true, encoding: .utf8)
        await #expect(throws: Engine.UnpackError.self) { try await Engine.unpack(tarball: bad, version: .init(sha: "cccc", date: nil), to: folder) }
        #expect(Engine.installedVersion(at: folder) == "aaaa")
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "nxnative.partial").path))
    }
}

@Suite struct EngineVersionTests {
    private func date(_ s: String) -> Date { try! Date(s, strategy: .iso8601) }

    @Test func unpacksAGitHubTarballAndStampsTheDate() async throws {
        let dir = try tempDir(), folder = dir.appending(path: "nxnative")
        let src = dir.appending(path: "src/seedds-nxnative-abc")
        try FileManager.default.createDirectory(at: src.appending(path: "scripts"), withIntermediateDirectories: true)
        try "gh".write(to: src.appending(path: "scripts/build_ipa_from_nsp.py"), atomically: true, encoding: .utf8)
        let tar = dir.appending(path: "gh.tar.gz")
        #expect(await ProcessLines.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-czf", tar.path, "-C", dir.appending(path: "src").path, "seedds-nxnative-abc"]) { _ in } == 0)
        let v = Engine.Version(sha: "abc", date: date("2026-10-20T12:00:00Z"))
        try await Engine.unpack(tarball: tar, version: v, stripComponents: 1, to: folder)
        #expect(try String(contentsOf: folder.appending(path: "scripts/build_ipa_from_nsp.py"), encoding: .utf8) == "gh")
        #expect(Engine.installed(at: folder) == v)
    }

    @Test func readsStamps() {
        #expect(Engine.Version(stamp: "abc\n") == Engine.Version(sha: "abc", date: nil))   // a 1.0.0 stamp
        #expect(Engine.Version(stamp: "abc\n2026-10-20T15:00:00+03:00\n")?.date == date("2026-10-20T12:00:00Z"))
        #expect(Engine.Version(stamp: "  \n") == nil)
    }

    @Test func bundledReplacesOnlyOlderEngines() {
        let old = Engine.Version(sha: "old", date: date("2026-10-01T00:00:00Z"))
        let new = Engine.Version(sha: "new", date: date("2026-10-20T00:00:00Z"))
        #expect(Engine.shouldInstallBundled(installed: nil, bundled: old))
        #expect(!Engine.shouldInstallBundled(installed: old, bundled: old))
        #expect(Engine.shouldInstallBundled(installed: old, bundled: new))          // a launcher update
        #expect(!Engine.shouldInstallBundled(installed: new, bundled: old))         // downloaded since: kept
        #expect(Engine.shouldInstallBundled(installed: .init(sha: "x", date: nil), bundled: old))
    }
}

@Suite struct EngineUpdateTests {
    @Test func parsesTheHeadCommit() throws {
        let json = #"{"sha":"def456","commit":{"committer":{"date":"2026-10-25T08:30:00Z"},"message":"Port a game\n\nDetails"}}"#
        let r = try EngineUpdate.parseCommit(Data(json.utf8))
        #expect(r.version.sha == "def456")
        #expect(r.message == "Port a game")
        #expect(r.version.date == (try Date("2026-10-25T08:30:00Z", strategy: .iso8601)))
        #expect(throws: EngineUpdate.UpdateError.self) { try EngineUpdate.parseCommit(Data("{}".utf8)) }
    }

    @Test func comparesWithTheInstalledCommit() throws {
        let c = try EngineUpdate.parseCompare(Data(#"{"status":"ahead","ahead_by":12,"behind_by":0}"#.utf8))
        #expect(c.status == "ahead" && c.aheadBy == 12)
        let latest = EngineUpdate.Release(version: .init(sha: "b", date: Date(timeIntervalSince1970: 200)), message: "")
        let installed = Engine.Version(sha: "a", date: Date(timeIntervalSince1970: 100))
        #expect(EngineUpdate.status(latest: latest, installed: installed, compare: ("ahead", 12)).isNewer)
        #expect(!EngineUpdate.status(latest: latest, installed: installed, compare: ("behind", 0)).isNewer)
        #expect(EngineUpdate.status(latest: latest, installed: installed, compare: nil).isNewer)       // dates decide
        #expect(!EngineUpdate.status(latest: latest, installed: .init(sha: "a", date: Date(timeIntervalSince1970: 300)), compare: nil).isNewer)
    }

    @Test func rateLimitIsExplained() {
        let r = HTTPURLResponse(url: URL(string: "https://api.github.com")!, statusCode: 403, httpVersion: nil, headerFields: nil)!
        #expect(throws: EngineUpdate.UpdateError(message: "GitHub's rate limit was reached, try again later")) { try EngineUpdate.checkResponse(r) }
    }
}

@Suite struct PreflightFixes {
    @Test func eachFailureHasItsFix() async throws {
        let dir = try tempDir()
        let py = try script(dir, "python3", "echo 'a warning' >&2; echo 'missing: capstone backports.zstd'")
        let bin = dir.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let checks = await Preflight.run(checkout: nil, source: .custom, python: py, keys: dir.appending(path: "none.keys"),
                                         environment: ["PATH": bin.path], developerDir: "/Library/Developer/CommandLineTools")
        let byName = Dictionary(uniqueKeysWithValues: checks.map { ($0.name, $0) })
        #expect(byName[Preflight.engineName]?.fix == .chooseEngine)
        #expect(byName[Preflight.pythonName]?.fix == .installModules(["capstone", "backports.zstd"]))
        #expect(byName[Preflight.keysName]?.fix == .chooseKeys)
        // No brew on PATH: the first missing tool is Xcode.
        #expect(byName[Preflight.toolsName]?.detail == "missing: Xcode, .NET SDK 10, zstd, spirv-cross")
        if case .openURL(_, let label)? = byName[Preflight.toolsName]?.fix { #expect(label == "Get Xcode") } else { Issue.record("no Xcode link") }
    }

    @Test func toolsFoundOnPath() throws {
        let dir = try tempDir()
        for t in ["dotnet", "zstd", "brew"] { _ = try script(dir, t, "exit 0") }
        #expect(Preflight.missingTools(environment: ["PATH": dir.path], developerDir: "/Applications/Xcode.app/Contents/Developer") == ["spirv-cross"])
        #expect(Preflight.toolsCheck(environment: ["PATH": dir.path], developerDir: "/Applications/Xcode.app/Contents/Developer").fix == .brewInstall(["spirv-cross"]))
    }

    @Test func engineStates() throws {
        let dir = try tempDir()
        try FileManager.default.createDirectory(at: dir.appending(path: "scripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appending(path: "dm/games"), withIntermediateDirectories: true)
        try "".write(to: dir.appending(path: "scripts/build_ipa_from_nsp.py"), atomically: true, encoding: .utf8)
        try "".write(to: dir.appending(path: "dm/games/README.md"), atomically: true, encoding: .utf8)
        #expect(Preflight.engineCheck(checkout: dir, source: .bundled(version: "0123456789abcdef")).detail == "bundled · 0123456")
        #expect(Preflight.engineCheck(checkout: dir, source: .custom).ok)
        #expect(Preflight.engineCheck(checkout: nil, source: .unpacking).fix == nil)
        #expect(Preflight.engineCheck(checkout: nil, source: .failed("x")).fix == .chooseEngine)
    }
}

@Suite struct PythonSetupTests {
    @Test func makesTheVenvThenInstalls() async throws {
        let dir = try tempDir(), venv = dir.appending(path: "venv"), record = dir.appending(path: "calls.txt")
        // The fake base Python makes a venv whose python3 records each call.
        let base = try script(dir, "base", """
            echo "base $*" >> '\(record.path)'
            mkdir -p "$3/bin"
            printf '#!/bin/sh\\necho "venv $*" >> %s\\n' '\(record.path)' > "$3/bin/python3"
            chmod +x "$3/bin/python3"
            """)
        let result = await PythonSetup.install(base: base, packages: PythonSetup.packages(for: ["fontTools", "backports.zstd"]), venv: venv) { _ in }
        #expect(result == .success(venv.appending(path: "bin/python3")))
        let calls = try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(calls == ["base -m venv \(venv.path)",
                          "venv -m pip install --disable-pip-version-check --upgrade pip",
                          "venv -m pip install --disable-pip-version-check fonttools backports.zstd"])
    }

    @Test func reportsTheFailingLine() async throws {
        let dir = try tempDir()
        let base = try script(dir, "base", "echo 'ERROR: no network'; exit 1")
        let result = await PythonSetup.install(base: base, packages: ["lz4"], venv: dir.appending(path: "venv")) { _ in }
        #expect(result == .failure(PythonSetup.InstallError(message: "ERROR: no network")))
    }
}
