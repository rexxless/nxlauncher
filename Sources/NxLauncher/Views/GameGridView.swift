import LauncherCore
import SwiftUI

struct GameGridView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let games: [GameBundle]
    let emptyText: String
    @AppStorage("gridSort") private var sort = Sort.name

    enum Sort: String, CaseIterable { case name = "Name", recent = "Last Played", playtime = "Playtime" }

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("\(games.count)").font(.title3).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue) } }
                        .pickerStyle(.segmented).frame(width: 280).labelsHidden()
                }
                if games.isEmpty {
                    Text(emptyText).font(.title3).foregroundStyle(.white.opacity(0.7)).padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 200), spacing: 28)], alignment: .leading, spacing: 32) {
                        ForEach(sorted) { CoverCard(game: $0, width: 180) }
                    }
                }
            }
            .padding(.horizontal, 48).padding(.top, 70).padding(.bottom, 40)
        }
    }

    private var sorted: [GameBundle] {
        switch sort {
        case .name: games
        case .recent: games.sorted { (model.playtime.lastPlayed($0.titleID) ?? .distantPast) > (model.playtime.lastPlayed($1.titleID) ?? .distantPast) }
        case .playtime: games.sorted { model.playtime.total($0.titleID) > model.playtime.total($1.titleID) }
        }
    }
}
