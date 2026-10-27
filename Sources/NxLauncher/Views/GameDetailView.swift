import Charts
import LauncherCore
import SwiftUI

/// A game's page: hero, Play, the stats strip, about, and its playtime over the last eight weeks.
struct GameDetailView: View {
    @Environment(AppModel.self) private var model
    let game: GameBundle

    var body: some View {
        let palette = model.palette(game), entry = model.catalog[game.titleID]
        PageScroll {
            VStack(alignment: .leading, spacing: 32) {
                ZStack(alignment: .bottomLeading) {
                    HeroArt(icon: model.icons[game.titleID], palette: palette)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(game.name).font(.system(size: 48, weight: .black, design: .rounded))
                            .lineLimit(3).minimumScaleFactor(0.5).frame(maxWidth: 560, alignment: .leading)
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                        Text(meta(entry)).font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                        HStack(spacing: 12) {
                            PlayButton(game: game, palette: palette)
                            GlassEffectContainer(spacing: 10) {
                                HStack(spacing: 10) {
                                    GlassCircleButton(systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([game.url]) }
                                        .help("Show in Finder")
                                    GlassCircleButton(systemImage: model.isFavorite(game) ? "star.fill" : "star") { model.toggleFavorite(game) }
                                        .help("Favorite")
                                    Menu { GameMenu(game: game) } label: {
                                        Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).frame(width: 46, height: 46)
                                    }
                                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                                    .roundButton()
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(height: 420)
                .padding(.top, 40)

                Rectangle().fill(.white.opacity(0.85)).frame(height: 1.5)
                    .padding(.bottom, -32)
                stats(entry)

                section("About") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(about(entry)).font(.system(size: 24, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        Text(tags(entry).map { $0.uppercased() }.joined(separator: "   /   "))
                            .font(.system(size: 11, weight: .medium, design: .monospaced)).kerning(1.2).foregroundStyle(.white.opacity(0.6))
                    }
                }
                section("Playtime") { PlaytimeChart(titleID: game.titleID, accent: palette.accent.color) }
            }
            .padding(.horizontal, 48).padding(.bottom, 48)
        }
    }

    private func meta(_ e: Catalog.Entry?) -> String {
        var p: [String] = []
        if let e { p += [e.engine, "SDK \(e.sdk)", "Build \(e.build)", e.graphics] } else { p.append("Version \(game.version)") }
        return p.joined(separator: " · ")
    }

    private func stats(_ e: Catalog.Entry?) -> some View {
        let total = model.playtime.total(game.titleID)
        let cells: [(String, String)] = [
            ("Engine", e?.engine ?? "—"),
            ("Build", e?.build ?? game.version),
            ("SDK", e?.sdk ?? "—"),
            ("Played", total > 0 ? PlaytimeLog.format(total) : "0 h"),
            ("Last played", model.playtime.lastPlayed(game.titleID)?.playedText ?? "Never"),
            ("Size", model.sizes[game.titleID].map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…"),
            ("Graphics", e?.graphics ?? "—"),
        ]
        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                if i > 0 { Rectangle().fill(.white.opacity(0.2)).frame(width: 1) }
                StatCell(label: c.0, value: c.1)
            }
        }
        .frame(height: 78)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.2)).frame(height: 1) }
    }

    private func about(_ e: Catalog.Entry?) -> String {
        let lang = Locale.current.localizedString(forIdentifier: game.language) ?? game.language
        if let e {
            return "\(game.name) runs natively on this Mac: its own code, on nxnative's Horizon host, with \(e.graphics) translated to Metal. Built from version \(e.build) in \(lang)."
        }
        return "\(game.name) was built from a provisional profile: nxnative had no notes for it yet. Version \(game.version), in \(lang)."
    }

    private func tags(_ e: Catalog.Entry?) -> [String] {
        [game.titleID, e == nil ? "Provisional" : "Supported", "Apple silicon"] + (model.isFavorite(game) ? ["Favorite"] : [])
    }

    private func section<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label.uppercased()).font(.system(size: 11, weight: .medium, design: .monospaced)).kerning(1.4)
                .foregroundStyle(.white.opacity(0.6)).frame(width: 190, alignment: .leading).padding(.top, 6)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PlaytimeChart: View {
    @Environment(AppModel.self) private var model
    var titleID: String?
    let accent: Color

    var body: some View {
        let weeks = model.playtime.weekly(titleID, weeks: 8)
        Chart(weeks, id: \.week) { w in
            BarMark(x: .value("Week", w.week, unit: .weekOfYear), y: .value("Hours", w.seconds / 3600))
                .foregroundStyle(accent.gradient)
                .clipShape(.rect(cornerRadius: 5))
        }
        .chartYAxisLabel("hours")
        .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
        .frame(height: 180)
        .padding(18)
        .glassEffect(.regular.tint(.black.opacity(0.1)), in: .rect(cornerRadius: 18))
    }
}
