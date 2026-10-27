import LauncherCore
import SwiftUI

/// Add a game: choose its NSP folder; the launcher names the game from the folder's files and nxnative's table, then queues the build.
struct AddGameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var folder: URL?
    @State private var language = ""

    private static let languages: [(String, String)] = [
        ("", "English (default)"), ("en-GB", "English (UK)"), ("ja", "Japanese"), ("fr", "French"), ("fr-CA", "French (Canada)"),
        ("de", "German"), ("es", "Spanish"), ("es-419", "Spanish (Latin America)"), ("it", "Italian"), ("nl", "Dutch"),
        ("pt", "Portuguese"), ("pt-BR", "Portuguese (Brazil)"), ("ru", "Russian"), ("ko", "Korean"),
        ("zh-Hans", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)"),
    ]

    var body: some View {
        let titleID = folder.flatMap(Catalog.titleID(inFolder:))
        let entry = titleID.flatMap { model.catalog[$0] }
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "plus.app.fill").font(.largeTitle).foregroundStyle(model.theme.accent.color)
                VStack(alignment: .leading) {
                    Text("Add Game").font(.title.weight(.bold))
                    Text("nxnative builds it into a Mac app in the background.").foregroundStyle(.secondary)
                }
            }

            Button { if let u = pick(directory: true) { folder = u } } label: {
                HStack(spacing: 14) {
                    Image(systemName: folder == nil ? "folder.badge.plus" : "folder.fill").font(.title)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(folder?.lastPathComponent ?? "Choose the game's NSP folder…").font(.headline)
                        Text(folder == nil ? "The base game, its update and DLC NSPs (or NSZ / XCI) in one folder" : "Click to choose another folder")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))

            if folder != nil {
                Group {
                    if let entry {
                        Label { Text("**\(entry.name)** — supported (\(entry.engine), \(entry.graphics))") } icon: {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        }
                    } else if let titleID {
                        Label("\(titleID) has no nxnative profile yet: the build makes a provisional one, and the app may not boot.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    } else {
                        Label("No title ID in the file names: nxnative identifies the game from the files themselves.", systemImage: "questionmark.circle")
                    }
                }
                .font(.callout)
            }

            Picker("Language", selection: $language) {
                ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
            }
            .frame(maxWidth: 360)

            if !model.readyToBuild {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Before building").font(.headline)
                    PreflightList()
                    Button("Open Settings") { model.route = .settings; dismiss() }.buttonStyle(.glass)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.glass)
                Button("Build") {
                    if let folder { model.enqueueBuild(nspFolder: folder, language: language.isEmpty ? nil : language) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent).tint(model.theme.accent.color)
                .disabled(folder == nil || !model.readyToBuild)
            }
        }
        .padding(28)
        .frame(width: 560)
        .task { await model.runPreflight() }
    }
}
