import AppKit
import LauncherCore
import SwiftUI

extension RGB {
    var color: Color { Color(red: r, green: g, blue: b) }
}

extension Palette {
    /// Foreground on the base color.
    var ink: Color { isLight ? .black : .white }
}

/// The window's backdrop: a mesh gradient of the game's colors under a huge, blurred copy of its icon, so the glass on top has color to pick up.
struct ThemeBackground: View {
    let palette: Palette
    let icon: NSImage?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let s = palette.swatches.map(\.color) + [palette.base.color, palette.deep.color, palette.accent.color]
        ZStack {
            palette.deep.color
            if !reduceTransparency {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.6, 0.4], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: [
                    palette.deep.color, palette.base.color, s[0],
                    palette.base.color, palette.base.color, s[min(1, s.count - 1)],
                    palette.deep.color, palette.deep.color, palette.base.color.opacity(0.9),
                ])
                if let icon {
                    // Filled into the backdrop's own size: a bare scaledToFill would size the window's stack to the image's aspect.
                    Color.clear.overlay {
                        Image(nsImage: icon).resizable().scaledToFill()
                            .blur(radius: 90).opacity(0.35).saturation(1.4)
                    }
                    .clipped()
                    .blendMode(.plusLighter)
                }
                // Grain-free darkening toward the bottom keeps the rows readable.
                LinearGradient(colors: [.clear, palette.deep.color.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: palette)
    }
}

/// The game's art: its icon on its own colors, square. Switch icons are 256 px, so larger sizes are drawn smooth, not sharp.
struct GameArt: View {
    let icon: NSImage?
    let palette: Palette
    var corner: CGFloat = 22

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.base.color, palette.deep.color], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFill()
            } else {
                Image(systemName: "gamecontroller.fill").font(.system(size: 48)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .clipShape(.rect(cornerRadius: corner, style: .continuous))
    }
}

/// The hero's art, as the reference's full-bleed key art: the icon large against the window's right and top edges,
/// fading into the backdrop toward the title on the left and the rows below.
struct HeroArt: View {
    let icon: NSImage?
    let palette: Palette
    /// How far the art reaches past the page's padding, to the window's edge.
    var bleed: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.height + bleed * 2, geo.size.width * 0.62)
            GameArt(icon: icon, palette: palette, corner: 0)
                .frame(width: side, height: side)
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.45)], startPoint: .leading, endPoint: .trailing)
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                }
                .position(x: geo.size.width + bleed - side / 2, y: side / 2 - bleed * 2)
        }
        .allowsHitTesting(false)
    }
}

/// A portrait cover card: the icon over a blurred bleed of itself, the title and a meta line under it.
struct CoverCard: View {
    @Environment(AppModel.self) private var model
    let game: GameBundle
    var width: CGFloat = 190
    @State private var hover = false

    var body: some View {
        let palette = model.palette(game), icon = model.icons[game.titleID]
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                LinearGradient(colors: [palette.base.color, palette.deep.color], startPoint: .top, endPoint: .bottom)
                if let icon {
                    Image(nsImage: icon).resizable().scaledToFill().blur(radius: 24).opacity(0.75).scaleEffect(1.4)
                }
                VStack {
                    Spacer(minLength: 0)
                    GameArt(icon: icon, palette: palette, corner: 18)
                        .frame(width: width * 0.78, height: width * 0.78)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                    Spacer(minLength: 0)
                }
                if model.isPlaying(game) {
                    VStack { HStack { Spacer(); PlayingPill() }; Spacer() }.padding(10)
                }
                if hover {
                    Button { model.play(game) } label: {
                        Image(systemName: "play.fill").font(.title2).frame(width: 54, height: 54)
                    }
                    .buttonStyle(.plain)
                    .roundButton(fill: .black.opacity(0.4))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: width, height: width * 1.36)
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(hover ? 0.45 : 0.12), lineWidth: 1))
            .shadow(color: .black.opacity(hover ? 0.45 : 0.25), radius: hover ? 22 : 10, y: hover ? 14 : 6)
            .scaleEffect(hover ? 1.035 : 1)

            Text(game.name).font(.headline).lineLimit(1).foregroundStyle(.white)
            HStack(spacing: 5) {
                Image(systemName: "gamecontroller.fill").font(.caption2)
                Text(model.metaLine(game)).lineLimit(1)
            }
            .font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: width)
        .contentShape(.rect)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { hover = h } }
        .onTapGesture(count: 2) { model.play(game) }
        .onTapGesture { withAnimation(.smooth) { model.detail = game } }
        .contextMenu { GameMenu(game: game) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct PlayingPill: View {
    var body: some View {
        Label("Playing", systemImage: "waveform").font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassEffect(.regular.tint(.green.opacity(0.5)), in: .capsule)
            .foregroundStyle(.white)
    }
}

/// The actions of a game, shared by the context menu and the detail page's ⋯ menu.
struct GameMenu: View {
    @Environment(AppModel.self) private var model
    let game: GameBundle

    var body: some View {
        Button("Play") { model.play(game) }
        Button(model.isFavorite(game) ? "Remove from Favorites" : "Add to Favorites") { model.toggleFavorite(game) }
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([game.url]) }
        Button("Open Save Folder") { NSWorkspace.shared.open(game.saveFolder()) }
            .disabled(!FileManager.default.fileExists(atPath: game.saveFolder().path))
        Button("Open Game Log") { NSWorkspace.shared.open(game.logFile()) }
            .disabled(!FileManager.default.fileExists(atPath: game.logFile().path))
        if let note = model.catalog[game.titleID]?.note, let checkout = model.checkoutURL {
            Button("Open nxnative Note") { NSWorkspace.shared.open(checkout.appending(path: "dm/games").appending(path: note)) }
        }
        Divider()
        Button("Remove from Library", role: .destructive) { model.remove(game) }
    }
}

/// A white (or, on light colors, black) capsule Play button, as in the reference.
struct PlayButton: View {
    @Environment(AppModel.self) private var model
    let game: GameBundle
    let palette: Palette

    var body: some View {
        let playing = model.isPlaying(game)
        Button { model.play(game) } label: {
            Label(playing ? "Playing" : "Play", systemImage: playing ? "waveform" : "play.fill")
                .font(.title3.weight(.semibold))
                .frame(width: 130, height: 46)
                .foregroundStyle(palette.isLight ? .white : .black)
                .background(palette.isLight ? Color.black.opacity(0.85) : .white, in: .capsule)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [])
        .help(playing ? "Bring the game to the front" : "Play \(game.name)")
    }
}

/// A round toolbar button, glass or solid as the buttons are.
struct GlassCircleButton: View {
    let systemImage: String
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: size * 0.36, weight: .semibold)).frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .roundButton()
    }
}

extension View {
    /// The launcher's buttons, Liquid Glass or solid as chosen in Settings; a prominent one wears the button color.
    func launcherButton(prominent: Bool = false) -> some View { modifier(LauncherButton(prominent: prominent)) }

    /// A round button's backing: interactive glass, or a flat circle of `fill`.
    func roundButton(fill: Color = .white.opacity(0.14)) -> some View { modifier(RoundButton(fill: fill)) }
}

struct LauncherButton: ViewModifier {
    @Environment(AppModel.self) private var model
    let prominent: Bool

    func body(content: Content) -> some View {
        switch model.appearance.buttonLook {
        case .glass:
            if prominent { content.buttonStyle(.glassProminent).tint(model.buttonTint).foregroundStyle(model.buttonInk) }
            else { content.buttonStyle(.glass) }
        case .solid:
            content.buttonStyle(SolidButtonStyle(fill: prominent ? model.buttonTint : .white.opacity(0.14), ink: prominent ? model.buttonInk : .white))
        }
    }
}

struct RoundButton: ViewModifier {
    @Environment(AppModel.self) private var model
    let fill: Color

    func body(content: Content) -> some View {
        if model.appearance.buttonLook == .glass {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.background(fill, in: .circle).overlay(Circle().strokeBorder(.white.opacity(0.12)))
        }
    }
}

/// A plain capsule button, padded per control size as the glass buttons are.
struct SolidButtonStyle: ButtonStyle {
    let fill: Color
    let ink: Color
    @Environment(\.controlSize) private var size
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let (h, v): (CGFloat, CGFloat) = switch size {
        case .mini: (8, 2)
        case .small: (10, 3)
        case .large: (16, 7)
        case .extraLarge: (20, 10)
        default: (12, 5)
        }
        configuration.label
            .padding(.horizontal, h).padding(.vertical, v)
            .foregroundStyle(ink)
            .background(fill, in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .contentShape(.capsule)
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
    }
}

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.weight(.bold)).foregroundStyle(.white)
            Spacer()
            if let action { Button("See All", action: action).buttonStyle(.plain).foregroundStyle(.white.opacity(0.75)) }
        }
    }
}

/// Small uppercase labels over large values, as in the reference's stats strip.
struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced)).kerning(1.2).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.title3.weight(.medium)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14).padding(.horizontal, 14)
    }
}

extension Date {
    /// "2 days ago" for the last fortnight, then the date.
    var playedText: String {
        if Date.now.timeIntervalSince(self) < 14 * 86_400 {
            return RelativeDateTimeFormatter().localizedString(for: self, relativeTo: .now)
        }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}
