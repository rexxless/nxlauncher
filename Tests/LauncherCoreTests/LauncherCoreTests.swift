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
