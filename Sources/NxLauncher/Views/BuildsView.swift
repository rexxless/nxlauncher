import LauncherCore
import SwiftUI

/// The build queue: each build's overall bar, its current stage and step, its ETA, the stage list and the live log.
struct BuildsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Builds").font(.system(size: 34, weight: .heavy, design: .rounded))
                    Spacer()
                    if model.builds.contains(where: { !$0.isActive }) {
                        Button("Clear Finished") { model.clearFinishedBuilds() }.launcherButton()
                    }
                }
                if model.builds.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No builds yet.").font(.title2.weight(.semibold))
                        Text("Add a game's NSP folder and nxnative extracts it, rewrites its code for the Mac, translates its shaders and packs it into an app. A first build takes a few minutes; later ones reuse what they can.")
                            .foregroundStyle(.white.opacity(0.75)).frame(maxWidth: 560, alignment: .leading)
                        Button { model.showingAddGame = true } label: { Label("Add Game", systemImage: "plus") }
                            .launcherButton(prominent: true).controlSize(.large)
                    }
                    .padding(.top, 20)
                }
                ForEach(model.builds) { BuildCard(job: $0) }
            }
            .padding(.horizontal, 48).padding(.top, 70).padding(.bottom, 40)
        }
    }
}

struct BuildCard: View {
    @Environment(AppModel.self) private var model
    let job: BuildJob
    @State private var showStages = true
    @State private var showLog = false

    var body: some View {
        let p = job.progress
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                art
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title).font(.title3.weight(.bold)).lineLimit(1)
                    Text(status).font(.callout).foregroundStyle(statusColor).lineLimit(2)
                }
                Spacer()
                actions
            }

            if job.isActive {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: p.fraction).progressViewStyle(GlassBarStyle(tint: model.theme.accent.color))
                    HStack {
                        Text(stageLine(p)).lineLimit(1)
                        Spacer()
                        if let eta = p.eta { Text("about \(Duration.seconds(eta).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))) left") }
                        Text("\(Int(p.fraction * 100))%").monospacedDigit().fontWeight(.semibold)
                    }
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
                    if !p.detail.isEmpty { Text(p.detail).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
                }
            }

            if !p.stages.isEmpty {
                DisclosureGroup(isExpanded: $showStages) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(p.stages) { s in
                            HStack(spacing: 8) {
                                Group {
                                    switch s.ok {
                                    case true?: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    case false?: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                    case nil: ProgressView().controlSize(.mini)
                                    }
                                }
                                .frame(width: 16)
                                Text("\(s.k)/\(p.stageCount)").monospacedDigit().foregroundStyle(.white.opacity(0.5))
                                Text(s.name)
                                if !s.summary.isEmpty { Text(s.summary).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
                                Spacer()
                                if s.ok != nil { Text(Duration.seconds(s.elapsed).formatted(.time(pattern: .minuteSecond))).monospacedDigit().foregroundStyle(.white.opacity(0.6)) }
                            }
                            .font(.callout)
                        }
                    }
                    .padding(.top, 8)
                } label: { Text("Stages").font(.callout.weight(.semibold)) }
            }

            DisclosureGroup(isExpanded: $showLog) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(job.log.enumerated()), id: \.offset) { i, line in
                                Text(line).font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(line.hasPrefix("[RED]") ? Color(red: 1, green: 0.55, blue: 0.5) : .white.opacity(0.8))
                                    .textSelection(.enabled).id(i)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }
                    .frame(height: 220)
                    .background(.black.opacity(0.35), in: .rect(cornerRadius: 10))
                    .onChange(of: job.log.count) { _, n in proxy.scrollTo(n - 1, anchor: .bottom) }
                }
                .padding(.top, 8)
            } label: { Text("Log (\(job.log.count) line\(job.log.count == 1 ? "" : "s"))").font(.callout.weight(.semibold)) }
        }
        .padding(20)
        .glassEffect(.regular.tint(model.surface(model.theme.deep, 0.25)), in: .rect(cornerRadius: 22))
    }

    @ViewBuilder private var art: some View {
        if let g = job.app {
            GameArt(icon: model.icons[g.titleID], palette: model.palette(g), corner: 12).frame(width: 56, height: 56)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.12))
                if job.isActive { ProgressRing(fraction: job.progress.fraction).frame(width: 30, height: 30) }
                else { Image(systemName: "shippingbox").font(.title2) }
            }
            .frame(width: 56, height: 56)
        }
    }

    @ViewBuilder private var actions: some View {
        if job.isActive {
            Button("Cancel", role: .cancel) { model.cancel(job) }.launcherButton()
        } else if let g = job.app {
            HStack {
                Button("Show") { model.detail = g }.launcherButton()
                Button { model.play(g) } label: { Label("Play", systemImage: "play.fill") }
                    .launcherButton(prominent: true)
            }
        } else {
            Button("Show Folder") { NSWorkspace.shared.open(job.request.nspFolder) }.launcherButton()
        }
    }

    private var status: String {
        switch job.progress.phase {
        case .queued: "Waiting for the build before it"
        case .running: job.titleID.map { "Building · \($0)" } ?? "Building"
        case .succeeded: job.app.map { "Ready · \($0.url.lastPathComponent)" } ?? "Built — the app was not found; add it in Settings"
        case let .failed(msg): msg
        case .cancelled: "Cancelled"
        }
    }

    private var statusColor: Color {
        switch job.progress.phase {
        case .failed: Color(red: 1, green: 0.6, blue: 0.55)
        case .succeeded: Color(red: 0.6, green: 1, blue: 0.7)
        default: .white.opacity(0.75)
        }
    }

    private func stageLine(_ p: BuildProgress) -> String {
        guard let s = p.current else { return "Starting…" }
        return "\(s.k)/\(p.stageCount) · \(s.name)" + (p.step.isEmpty ? "" : " · \(p.step)")
    }
}

/// A thick capsule progress bar on glass, filled with the theme's accent.
struct GlassBarStyle: ProgressViewStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.8), tint, .white.opacity(0.9)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(10, geo.size.width * (configuration.fractionCompleted ?? 0)))
                    .shadow(color: tint.opacity(0.6), radius: 8)
                    .animation(.smooth(duration: 0.5), value: configuration.fractionCompleted)
            }
        }
        .frame(height: 10)
        .glassEffect(.regular, in: .capsule)
    }
}
