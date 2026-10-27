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
                            Button("Remove") { model.removeFolder(f) }.launcherButton()
                        }
                    }
                    HStack {
                        Button("Add Folder…") { if let u = pick(directory: true) { model.addFolder(u) } }.launcherButton()
                        Button("Add Game App…") { addApps() }.launcherButton()
                        Button("Rescan") { model.rescan() }.launcherButton()
                    }
                }
                card("Appearance", footer: "The window color is shown when no game is chosen; games tint the window with their icon's colors.") {
                    AppearanceSettings()
                }
                card("Ready to Build", footer: nil) {
                    PreflightList()
                    Button("Check Again") { Task { await model.runPreflight() } }.launcherButton()
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
        .glassEffect(.regular.tint(model.surface(model.theme.deep, 0.2)), in: .rect(cornerRadius: 20))
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

/// Buttons glass or solid, their color, and the window's own color and tint.
struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Buttons").frame(width: 150, alignment: .leading)
                Picker("Buttons", selection: $model.appearance.buttonLook) {
                    Text("Liquid Glass").tag(Appearance.ButtonLook.glass)
                    Text("Solid").tag(Appearance.ButtonLook.solid)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                Spacer()
            }
            HStack {
                Text("Button color").frame(width: 150, alignment: .leading)
                Toggle("Match game colors", isOn: Binding(
                    get: { model.appearance.buttonColor == nil },
                    set: { model.appearance.buttonColor = $0 ? nil : model.theme.button }))
                Spacer()
                if model.appearance.buttonColor == nil { Swatch(color: model.buttonRGB.color) }
            }
            if let color = model.appearance.buttonColor {
                ColorSliders(rgb: Binding(get: { color }, set: { model.appearance.buttonColor = $0 })).padding(.leading, 158)
            }
            PercentSlider(label: "Button opacity", value: $model.appearance.buttonOpacity, range: 0.2...1)

            Divider().overlay(.white.opacity(0.15))

            HStack {
                Text("Window color").frame(width: 150, alignment: .leading)
                Spacer()
                Button("Reset to Indigo") { model.appearance.mainColor = nil }.launcherButton()
                    .disabled(model.appearance.mainColor == nil)
            }
            ColorSliders(rgb: Binding(get: { model.appearance.defaultPalette.base }, set: { model.appearance.mainColor = $0 }))
                .padding(.leading, 158)
            PercentSlider(label: "Tint opacity", value: $model.appearance.tintOpacity, range: 0...1)

            Divider().overlay(.white.opacity(0.15))

            HStack {
                Text("Preview").frame(width: 150, alignment: .leading)
                Button {} label: { Label("Add Game", systemImage: "plus").font(.callout.weight(.semibold)) }.launcherButton(prominent: true)
                Button("Cancel") {}.launcherButton()
                GlassCircleButton(systemImage: "star", size: 30) {}
                Spacer()
                Button("Restore Defaults") { model.appearance = Appearance() }.launcherButton()
                    .disabled(model.appearance == Appearance())
            }
        }
    }
}

private struct Swatch: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 44, height: 22)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.3)))
    }
}

private struct PercentSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(label).frame(width: 150, alignment: .leading)
            Slider(value: $value, in: range)
            Text("\(Int((value * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing).foregroundStyle(.white.opacity(0.75))
        }
    }
}

/// Hue, saturation and brightness sliders on their own gradients, with the system color well for exact picks.
/// The three values are kept here, so the hue survives at zero saturation or brightness.
struct ColorSliders: View {
    @Binding var rgb: RGB
    @State private var h = 0.0
    @State private var s = 0.0
    @State private var v = 0.0

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 8) {
                track("Hue", $h, (0...12).map { Color(hue: Double($0) / 12, saturation: s, brightness: max(v, 0.3)) })
                track("Saturation", $s, [Color(hue: h, saturation: 0, brightness: v), Color(hue: h, saturation: 1, brightness: v)])
                track("Brightness", $v, [.black, Color(hue: h, saturation: s, brightness: 1)])
            }
            ColorPicker("Color", selection: Binding(get: { rgb.color }, set: { c in
                guard let n = NSColor(c).usingColorSpace(.sRGB) else { return }
                rgb = RGB(Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent))
                (h, s, v) = rgb.hsb
            }), supportsOpacity: false)
            .labelsHidden()
        }
        .onAppear { (h, s, v) = rgb.hsb }
        .onChange(of: rgb) { _, c in if RGB(h: h, s: s, v: v).distance(c) > 1e-6 { (h, s, v) = c.hsb } }
    }

    private func track(_ name: String, _ value: Binding<Double>, _ colors: [Color]) -> some View {
        Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; rgb = RGB(h: h, s: s, v: v) }), in: 0...1)
            .tint(.clear)
            .background(Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)).frame(height: 6))
            .accessibilityLabel(name)
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
            Button("Choose…") { if let u = pick(directory: directory) { path = u.path } }.launcherButton()
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
            if !model.usesBundledEngine { Button("Use Bundled") { model.useBundledEngine() }.launcherButton() }
            Button("Choose Clone…") { model.choose(.engine) }.launcherButton()
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
                .launcherButton().controlSize(.small)
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
