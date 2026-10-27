import AppKit
import SwiftUI

/// NXL_SNAPSHOT=<folder>: show each screen in turn, save the window as <folder>/<screen>.png, then quit.
/// For checking the layout without a screen recorder, and for the README's pictures.
enum Snapshot {
    @MainActor private static var running = false

    @MainActor
    static func runIfRequested(_ model: AppModel) async {
        // The renderer builds its own RootView, whose task would start another run.
        guard let dir = ProcessInfo.processInfo.environment["NXL_SNAPSHOT"], !running else { return }
        running = true
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(2))
        var shots: [(String, () -> Void)] = [
            ("home", { model.detail = nil; model.route = .home }),
            ("all", { model.route = .all }),
            ("playtime", { model.route = .playtime }),
            ("builds", { model.route = .builds }),
            ("settings", { model.route = .settings }),
        ]
        // NXL_SNAPSHOT_BUILD=<NSP folder>: queue a build of it with the configured checkout, and show the Builds page during and after it.
        if let nsp = ProcessInfo.processInfo.environment["NXL_SNAPSHOT_BUILD"] {
            model.enqueueBuild(nspFolder: URL(fileURLWithPath: nsp), language: nil)
            shots.insert(("build-running", { model.detail = nil; model.route = .builds }), at: 0)
            shots.append(("build-done", { model.detail = nil; model.route = .builds }))
        }
        if let g = model.heroGame { shots.append(("detail", { model.detail = g })) }
        if model.games.count > 1 { shots.append(("detail2", { model.detail = model.games[1] })) }
        for (name, show) in shots {
            show()
            try? await Task.sleep(for: .seconds(1.5))
            // ImageRenderer draws the view tree itself (the window's layers cannot be read back); glass is drawn as its fallback fill.
            let renderer = ImageRenderer(content: RootView().environment(model).environment(\.snapshotting, true).frame(width: 1320, height: 860))
            renderer.scale = 2
            guard let cg = renderer.cgImage else { continue }
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: out.appending(path: "\(name).png"))
        }
        NSApp.terminate(nil)
    }
}

/// True while Snapshot renders: ImageRenderer leaves scroll views empty, so pages lay out as plain stacks.
/// (A plain key, not @Entry: SwiftUI's macros need Xcode's plugin, and the package builds with the Command Line Tools.)
private struct SnapshottingKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var snapshotting: Bool {
        get { self[SnapshottingKey.self] }
        set { self[SnapshottingKey.self] = newValue }
    }
}

/// A page's vertical scroll view; a plain stack while snapshotting.
struct PageScroll<Content: View>: View {
    var axis: Axis.Set = .vertical
    @ViewBuilder var content: Content
    @Environment(\.snapshotting) private var snapshotting

    var body: some View {
        if snapshotting {
            content.fixedSize(horizontal: axis == .horizontal, vertical: axis == .vertical)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading).clipped()
        } else {
            ScrollView(axis) { content }
        }
    }
}
