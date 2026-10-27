import AppKit
import LauncherCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var highlighted: SettingsFocus?

    var body: some View {
        @Bindable var model = model
        ScrollViewReader { proxy in
        PageScroll {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings").font(.system(size: 34, weight: .heavy, design: .rounded))

                card("Engine", focus: .engine, footer: "nxnative ships inside the launcher and is unpacked once per version. To build with your own clone instead, choose its folder.") {
                    EngineRow()
                    PathRow(label: "Python 3", path: $model.pythonPath, directory: false)
                }
                card("Keys", focus: .keys, footer: "Only the file's location is stored, on this Mac. The launcher passes it to nxnative and never opens or shows the file.") {
                    PathRow(label: "prod.keys", path: $model.keysPath, directory: false, showsPath: false)
                }
                card("Library Folders", footer: "Folders searched for games built by nxnative: an NSP folder, or a folder of them. Built games are also added on their own.") {
                    ForEach(model.libraryFolders, id: \.self) { f in
                        HStack {
                            Image(systemName: "folder.fill")
                            Text(f.path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Remove") { model.removeFolder(f) }.buttonStyle(.glass)
                        }
                    }
                    HStack {
                        Button("Add Folder…") { if let u = pick(directory: true) { model.addFolder(u) } }.buttonStyle(.glass)
                        Button("Add Game App…") { addApps() }.buttonStyle(.glass)
                        Button("Rescan") { model.rescan() }.buttonStyle(.glass)
                    }
                }
                card("Ready to Build", footer: nil) {
                    PreflightList()
                    Button("Check Again") { Task { await model.runPreflight() } }.buttonStyle(.glass)
                }
                Credits()
            }
            .padding(.horizontal, 48).padding(.top, 70).padding(.bottom, 40)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .onChange(of: model.settingsFocus, initial: true) { _, focus in
            guard let focus else { return }
            withAnimation(.smooth) { proxy.scrollTo(Optional(focus), anchor: .center) }
            highlighted = focus
            model.settingsFocus = nil
            Task { try? await Task.sleep(for: .seconds(2.5)); withAnimation(.easeOut(duration: 0.6)) { highlighted = nil } }
        }
        }
        .onChange(of: model.checkoutPath) { Task { await model.runPreflight() } }
        .onChange(of: model.pythonPath) { Task { await model.runPreflight() } }
        .onChange(of: model.keysPath) { Task { await model.runPreflight() } }
    }

    private func card<C: View>(_ title: String, focus: SettingsFocus? = nil, footer: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.bold))
            content()
            if let footer { Text(footer).font(.caption).foregroundStyle(.white.opacity(0.65)) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(model.theme.deep.color.opacity(0.2)), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(model.theme.accent.color, lineWidth: 2)
                .opacity(focus != nil && highlighted == focus ? 1 : 0)
        }
        .id(focus)
    }

    private func addApps() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]; p.allowsMultipleSelection = true
        p.message = "Choose game apps built by nxnative"
        guard p.runModal() == .OK else { return }
        let rejected = model.addApps(p.urls)
        if rejected > 0 {
            let a = NSAlert()
            a.messageText = rejected == 1 ? "That app is not an nxnative game" : "\(rejected) apps are not nxnative games"
            a.informativeText = "Only apps packed by nxnative (--platform mac-app) can be added."
            a.runModal()
        }
    }
}

struct PathRow: View {
    let label: String
    @Binding var path: String
    let directory: Bool
    var showsPath = true

    var body: some View {
        HStack {
            Text(label).frame(width: 150, alignment: .leading)
            Group {
                if path.isEmpty { Text("Not set").foregroundStyle(.white.opacity(0.5)) }
                else if showsPath { Text(path).lineLimit(1).truncationMode(.middle) }
                else { Label("Chosen", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Choose…") { if let u = pick(directory: directory) { path = u.path } }.buttonStyle(.glass)
        }
    }
}

@MainActor
func pick(directory: Bool) -> URL? {
    let p = NSOpenPanel()
    p.canChooseDirectories = directory; p.canChooseFiles = !directory; p.allowsMultipleSelection = false
    p.showsHiddenFiles = true
    return p.runModal() == .OK ? p.url : nil
}

/// Where nxnative comes from: the copy in the app, or the user's own clone.
struct EngineRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Text("nxnative").frame(width: 150, alignment: .leading)
            Group {
                if !model.usesBundledEngine { Text(model.checkoutPath).lineLimit(1).truncationMode(.middle) }
                else {
                    switch model.engineSource {
                    case .bundled(let v): Label("Bundled · \(Engine.shortVersion(v))", systemImage: "shippingbox.fill")
                    case .unpacking: Label("Unpacking…", systemImage: "shippingbox")
                    case .failed(let msg): Text(msg).foregroundStyle(.yellow)
                    case .custom: Text("Not set").foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !model.usesBundledEngine { Button("Use Bundled") { model.useBundledEngine() }.buttonStyle(.glass) }
            Button("Choose Clone…") { model.choose(.engine) }.buttonStyle(.glass)
        }
    }
}

struct Credits: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill").foregroundStyle(.pink)
            Text("Powered by")
            Link("nxnative", destination: URL(string: "https://github.com/seedds/nxnative")!).fontWeight(.semibold)
            Text("by seedds, MIT License.")
        }
        .font(.callout).foregroundStyle(.white.opacity(0.75))
        .frame(maxWidth: .infinity)
    }
}

/// The checks before a build, each failed one with the button that fixes it.
struct PreflightList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.preflight) { c in
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: c.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(c.ok ? .green : .yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(c.name).fontWeight(.semibold)
                            Text(c.detail).foregroundStyle(.white.opacity(0.7)).textSelection(.enabled)
                        }
                        if let status = model.fixStatus[c.name] {
                            Text(status).font(.caption).foregroundStyle(status.hasPrefix("failed") ? .yellow : .white.opacity(0.6))
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 8)
                    if !c.ok, let fix = c.fix { FixButton(check: c.name, fix: fix) }
                }
                .font(.callout)
            }
        }
    }
}

struct FixButton: View {
    @Environment(AppModel.self) private var model
    let check: String
    let fix: Preflight.Fix

    var body: some View {
        if model.fixing.contains(check) {
            ProgressView().controlSize(.small).frame(width: 28)
        } else {
            Button { model.perform(fix, for: check) } label: { Label(title, systemImage: symbol) }
                .buttonStyle(.glass).controlSize(.small)
        }
    }

    private var inSettings: Bool { model.route == .settings && !model.showingAddGame }

    private var title: String {
        switch fix {
        case .chooseKeys: inSettings ? "Choose prod.keys…" : "Set in Settings"
        case .chooseEngine: inSettings ? "Choose Clone…" : "Set in Settings"
        case .installModules: "Install"
        case .brewInstall: "Install with Homebrew"
        case .openURL(_, let label): label
        }
    }

    private var symbol: String {
        switch fix {
        case .chooseKeys: "key.fill"
        case .chooseEngine: "folder"
        case .installModules, .brewInstall: "arrow.down.circle"
        case .openURL: "arrow.up.right.square"
        }
    }
}
