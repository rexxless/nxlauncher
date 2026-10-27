import LauncherCore
import SwiftUI

/// All playtime: the last eight weeks across every game, then each game ranked by hours.
struct PlaytimeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let ranked = model.games.map { ($0, model.playtime.total($0.titleID)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let top = ranked.first?.1 ?? 1
        PageScroll {
            VStack(alignment: .leading, spacing: 28) {
                Text("Playtime").font(.system(size: 34, weight: .heavy, design: .rounded))
                StatsRow()
                PlaytimeChart(titleID: nil, accent: model.theme.accent.color)
                if ranked.isEmpty {
                    Text("Play a game from the launcher, or from Finder while the launcher is open, and its time shows up here.")
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    SectionHeader(title: "By Game")
                    VStack(spacing: 10) {
                        ForEach(ranked, id: \.0.titleID) { game, secs in
                            Button { model.detail = game } label: {
                                HStack(spacing: 14) {
                                    GameArt(icon: model.icons[game.titleID], palette: model.palette(game), corner: 10).frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(game.name).font(.headline)
                                            Spacer()
                                            Text(PlaytimeLog.format(secs)).monospacedDigit().fontWeight(.semibold)
                                        }
                                        GeometryReader { geo in
                                            Capsule().fill(model.palette(game).accent.color.gradient)
                                                .frame(width: max(6, geo.size.width * secs / top))
                                        }
                                        .frame(height: 6)
                                    }
                                }
                                .padding(12).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                        }
                    }
                }
            }
            .padding(.horizontal, 48).padding(.top, 70).padding(.bottom, 40)
        }
    }
}
