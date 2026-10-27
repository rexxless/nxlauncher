import AppKit
import SwiftUI

@main
struct NxLauncherApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("nxnative Launcher", id: "main") {
            RootView()
                .environment(model)
                .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Game…") { model.showingAddGame = true }.keyboardShortcut("n")
            }
            CommandMenu("Library") {
                Button("Home") { model.detail = nil; model.route = .home }.keyboardShortcut("1")
                Button("All Games") { model.detail = nil; model.route = .all }.keyboardShortcut("2")
                Button("Builds") { model.detail = nil; model.route = .builds }.keyboardShortcut("3")
                Button("Playtime") { model.detail = nil; model.route = .playtime }.keyboardShortcut("4")
                Divider()
                Button("Rescan Library") { model.rescan() }.keyboardShortcut("r")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.detail = nil; model.route = .settings }.keyboardShortcut(",")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run from `swift run` (no bundle): still a regular app with a Dock icon and focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
