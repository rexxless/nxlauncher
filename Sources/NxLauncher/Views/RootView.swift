import LauncherCore
import SwiftUI

/// The window: a tinted glass sidebar beside the content, both over the game-colored backdrop.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var sidebarShown = true

    var body: some View {
        @Bindable var model = model
        let theme = model.theme
        ZStack {
            ThemeBackground(palette: theme, icon: model.icons[(model.detail ?? model.heroGame)?.titleID ?? ""])
            HStack(spacing: 0) {
                if sidebarShown {
                    Sidebar()
                        .frame(width: 240)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ZStack(alignment: .top) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    TopBar(sidebarShown: $sidebarShown)
                }
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 980, minHeight: 640)
        .sheet(isPresented: $model.showingAddGame) { AddGameSheet() }
        .animation(.smooth(duration: 0.35), value: model.detail)
        .animation(.smooth(duration: 0.3), value: model.route)
        .task { await Snapshot.runIfRequested(model) }
    }

    @ViewBuilder private var content: some View {
        if !model.search.isEmpty {
            GameGridView(title: "Results for “\(model.search)”", games: model.searchResults, emptyText: "No game matches.")
        } else if let game = model.detail {
            GameDetailView(game: game).id(game.titleID).transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            switch model.route {
            case .home: HomeView()
            case .all: GameGridView(title: "All Games", games: model.games, emptyText: "No games yet. Add one with ＋.")
            case .recent: GameGridView(title: "Recently Played", games: model.recentGames, emptyText: "Games you play show up here.")
            case .favorites: GameGridView(title: "Favorites", games: model.favoriteGames, emptyText: "Right-click a game to add it to your favorites.")
            case let .graphics(name): GameGridView(title: name, games: model.games(for: .graphics(name)), emptyText: "")
            case .builds: BuildsView()
            case .playtime: PlaytimeView()
            case .settings: SettingsView()
            }
        }
    }
}

struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Binding var sidebarShown: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            if !sidebarShown { Spacer().frame(width: 70) }   // room for the traffic lights
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    GlassCircleButton(systemImage: "sidebar.left", size: 34) { withAnimation(.smooth) { sidebarShown.toggle() } }
                    if model.detail != nil {
                        GlassCircleButton(systemImage: "chevron.left", size: 34) { model.detail = nil }
                            .keyboardShortcut("[", modifiers: .command)
                    }
                }
            }
            Text(title).font(.headline).lineLimit(1)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.7))
                TextField("Search games", text: $model.search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 14).frame(width: 300, height: 36)
            .glassEffect(.regular.tint(model.theme.base.color.opacity(0.25)).interactive(), in: .capsule)
            Button { model.showingAddGame = true } label: {
                Label("Add Game", systemImage: "plus").font(.callout.weight(.semibold)).padding(.horizontal, 6).frame(height: 28)
            }
            .buttonStyle(.glassProminent)
            .tint(model.theme.accent.color)
            .keyboardShortcut("n", modifiers: .command)
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden().frame(width: 0)
        }
        .padding(.horizontal, 20).padding(.top, 12)
    }

    private var title: String {
        if let d = model.detail { return d.name }
        switch model.route {
        case .home: return "Home"
        case .all: return ""
        default: return ""
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer().frame(height: 52)   // the traffic lights
            row(.home, "Home", "house")
            group("Library")
            row(.all, "All Games", "square.grid.2x2", count: model.games.count)
            row(.recent, "Recently Played", "clock", count: model.recentGames.count)
            row(.favorites, "Favorites", "star", count: model.favoriteGames.count)
            if !model.graphicsGroups.isEmpty {
                group("Graphics")
                ForEach(model.graphicsGroups, id: \.name) { g in
                    row(.graphics(g.name), g.name, icon(g.name), count: g.count)
                }
            }
            group("Activity")
            buildsRow
            row(.playtime, "Playtime", "chart.bar.xaxis")
            Spacer()
            row(.settings, "Settings", "gearshape")
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle().fill(model.theme.deep.color.opacity(0.55)).ignoresSafeArea()
                .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
        }
        .animation(.easeInOut(duration: 0.45), value: model.theme)
    }

    private func icon(_ graphics: String) -> String {
        switch graphics {
        case "NVN": "cpu"
        case "Vulkan": "flame"
        case "OpenGL": "cube.transparent"
        default: "square.stack.3d.up"
        }
    }

    private func group(_ title: String) -> some View {
        Text(title).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.55))
            .padding(.leading, 10).padding(.top, 16).padding(.bottom, 4)
    }

    private var buildsRow: some View {
        SidebarRow(selected: isSelected(.builds), title: "Builds", systemImage: "arrow.down.circle",
                   count: nil, progress: model.activeBuild?.progress.fraction, badge: model.activeCount) { select(.builds) }
    }

    private func row(_ route: Route, _ title: String, _ systemImage: String, count: Int? = nil) -> some View {
        SidebarRow(selected: isSelected(route), title: title, systemImage: systemImage, count: count) { select(route) }
    }

    private func isSelected(_ r: Route) -> Bool { model.route == r && model.detail == nil && model.search.isEmpty }

    private func select(_ r: Route) {
        model.search = ""; model.detail = nil; model.route = r
    }
}

struct SidebarRow: View {
    let selected: Bool
    let title: String
    let systemImage: String
    var count: Int?
    var progress: Double?
    var badge = 0
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).frame(width: 20).foregroundStyle(.white.opacity(selected ? 1 : 0.75))
                Text(title).foregroundStyle(.white)
                Spacer()
                if let progress {
                    ProgressRing(fraction: progress).frame(width: 16, height: 16)
                } else if badge > 0 {
                    Text("\(badge)").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).background(.white.opacity(0.25), in: .capsule)
                }
                if let count { Text("\(count)").font(.caption).monospacedDigit().foregroundStyle(.white.opacity(0.55)) }
            }
            .font(.callout)
            .padding(.horizontal, 10).frame(height: 32)
            .contentShape(.rect)
            .background {
                if selected {
                    Capsule().fill(.clear).glassEffect(.regular.tint(.white.opacity(0.12)), in: .rect(cornerRadius: 9))
                } else if hover {
                    RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.07))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ProgressRing: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 2.5)
            Circle().trim(from: 0, to: max(0.03, fraction)).stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .animation(.smooth, value: fraction)
    }
}
