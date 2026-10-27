import AppKit
import LauncherCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PageScroll {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings").font(.system(size: 34, weight: .heavy, design: .rounded))

                card("Engine", footer: "A clone of the nxnative repository. The launcher runs its scripts/build_ipa_from_nsp.py and reads its games table.") {
                    PathRow(label: "nxnative checkout", path: $model.checkoutPath, directory: true)
                    PathRow(label: "Python 3", path: $model.pythonPath, directory: false)
                }
                card("Keys", footer: "Only the file's location is stored, on this Mac. The launcher passes it to nxnative and never opens or shows the file.") {
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
            }
            .padding(.horizontal, 48).padding(.top, 70).padding(.bottom, 40)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .onChange(of: model.checkoutPath) { Task { await model.runPreflight() } }
        .onChange(of: model.pythonPath) { Task { await model.runPreflight() } }
        .onChange(of: model.keysPath) { Task { await model.runPreflight() } }
    }

    private func card<C: View>(_ title: String, footer: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.bold))
            content()
            if let footer { Text(footer).font(.caption).foregroundStyle(.white.opacity(0.65)) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(model.theme.deep.color.opacity(0.2)), in: .rect(cornerRadius: 20))
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

struct PreflightList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.preflight) { c in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: c.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(c.ok ? .green : .yellow)
                    Text(c.name).fontWeight(.semibold)
                    Text(c.detail).foregroundStyle(.white.opacity(0.7)).textSelection(.enabled)
                }
                .font(.callout)
            }
        }
    }
}
