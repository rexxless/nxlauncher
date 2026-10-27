import LauncherCore
import SwiftUI

/// Home: the hero of the game played last, then the rows.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 36) {
                if let hero = model.heroGame {
                    Hero(game: hero)
                    if model.games.count > 0 {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Ready to Play") { model.route = .all }
                            PageScroll(axis: .horizontal) {
                                LazyHStack(spacing: 24) {
                                    ForEach(model.games) { CoverCard(game: $0) }
                                }
                                .padding(.vertical, 14).padding(.horizontal, 4)
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                    if model.recentGames.count > 1 {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Jump Back In") { model.route = .recent }
                            PageScroll(axis: .horizontal) {
                                LazyHStack(spacing: 24) { ForEach(model.recentGames.dropFirst()) { CoverCard(game: $0, width: 160) } }
                                    .padding(.vertical, 14).padding(.horizontal, 4)
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                    StatsRow()
                    if !model.graphicsGroups.isEmpty { GraphicsRow() }
                } else {
                    Onboarding()
                }
            }
            .padding(.horizontal, 48).padding(.bottom, 48)
        }
        .scrollIndicators(.never)
    }
}

/// "CONTINUE PLAYING", the title in heavy type, Play and ⓘ; the icon large on the right, faded into the backdrop.
struct Hero: View {
    @Environment(AppModel.self) private var model
    let game: GameBundle

    var body: some View {
        let palette = model.palette(game), played = model.playtime.lastPlayed(game.titleID) != nil
        ZStack(alignment: .leading) {
            HeroArt(icon: model.icons[game.titleID], palette: palette)
            VStack(alignment: .leading, spacing: 18) {
                Text(played ? "CONTINUE PLAYING" : "READY TO PLAY")
                    .font(.system(size: 12, weight: .semibold)).kerning(1.6).foregroundStyle(.white.opacity(0.75))
                Text(game.name)
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .lineLimit(3).minimumScaleFactor(0.5)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                    .frame(maxWidth: 520, alignment: .leading)
                Text(subtitle).font(.callout).foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 12) {
                    PlayButton(game: game, palette: palette)
                    GlassCircleButton(systemImage: "info") { model.detail = game }.help("Details")
                }
                .padding(.top, 6)
            }
            .padding(.top, 70)
        }
        .frame(height: 440)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let e = model.catalog[game.titleID] { parts += [e.engine, e.graphics] }
        let total = model.playtime.total(game.titleID)
        if total > 0 { parts.append("\(PlaytimeLog.format(total)) played") }
        return parts.joined(separator: " · ")
    }
}

struct StatsRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let week = model.playtime.weekly(weeks: 1).last?.seconds ?? 0
        HStack(spacing: 0) {
            StatCell(label: "Games", value: "\(model.games.count)")
            Divider().overlay(.white.opacity(0.2))
            StatCell(label: "Total played", value: PlaytimeLog.format(model.playtime.total))
            Divider().overlay(.white.opacity(0.2))
            StatCell(label: "This week", value: PlaytimeLog.format(week))
            Divider().overlay(.white.opacity(0.2))
            StatCell(label: "Most played", value: mostPlayed ?? "—")
        }
        .frame(height: 76)
        .glassEffect(.regular.tint(model.theme.deep.color.opacity(0.3)), in: .rect(cornerRadius: 18))
    }

    private var mostPlayed: String? {
        model.games.max { model.playtime.total($0.titleID) < model.playtime.total($1.titleID) }
            .flatMap { model.playtime.total($0.titleID) > 0 ? $0.name : nil }
    }
}

struct GraphicsRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Graphics")
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    ForEach(model.graphicsGroups, id: \.name) { g in
                        Button { model.route = .graphics(g.name) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(g.name).font(.title3.weight(.bold))
                                    Text("\(g.count) game\(g.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.white.opacity(0.7))
                                }
                                Spacer()
                                Text(about(g.name)).font(.caption2).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.trailing)
                            }
                            .padding(18).frame(maxWidth: .infinity, minHeight: 84)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                    }
                }
            }
        }
    }

    private func about(_ g: String) -> String {
        switch g {
        case "NVN": "NVIDIA's Switch API\non Metal"
        case "Vulkan": "Vulkan\non Metal"
        case "OpenGL": "Desktop OpenGL\non Metal"
        default: ""
        }
    }
}

/// The first run: what the launcher needs before it can build.
struct Onboarding: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("WELCOME").font(.system(size: 12, weight: .semibold)).kerning(1.6).foregroundStyle(.white.opacity(0.75))
            Text("Your Switch library,\nnative on your Mac.").font(.system(size: 48, weight: .black, design: .rounded))
            Text("Add a game's NSP folder and nxnative builds it into a Mac app. Games you already built can be added from their folder in Settings.")
                .font(.title3).foregroundStyle(.white.opacity(0.8)).frame(maxWidth: 560, alignment: .leading)
            HStack(spacing: 12) {
                Button { model.showingAddGame = true } label: {
                    Label("Add Game", systemImage: "plus").font(.title3.weight(.semibold)).frame(width: 150, height: 46)
                        .foregroundStyle(.black).background(.white, in: .capsule)
                }
                .buttonStyle(.plain)
                Button("Settings") { model.route = .settings }.buttonStyle(.glass).controlSize(.extraLarge)
            }
            if !model.readyToBuild && !model.preflight.isEmpty {
                PreflightList().frame(maxWidth: 560)
            }
        }
        .padding(.top, 110)
    }
}
