import SwiftUI
import UIKit

private enum ShutoutStyle {
    static let navy = Color(red: 0.035, green: 0.075, blue: 0.14)
    static let gold = Color(red: 1, green: 0.77, blue: 0.18)
    static let blue = Color(red: 0.36, green: 0.76, blue: 1)
    static let cream = Color(red: 0.97, green: 0.94, blue: 0.86)
}

struct ShutoutGame: Decodable, Identifiable {
    struct Play: Decodable, Identifiable {
        let id: Int
        let inning: Int
        let runs: Int
        let total: Int
        let description: String
    }
    let id: Int
    let date: String
    let opponent: String
    let total: Int
    let innings: [Int]
    let plays: [Play]
    let source: URL
    var dateLabel: String { date == "2026-08-18" ? "AUG 18, 2026" : "SEP 11, 2026" }
    func score(through inning: Int) -> Int { innings.prefix(inning).reduce(0, +) }
}

struct BrewersShutoutView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var games: [ShutoutGame] = []
    @State private var loadFailed = false
    @State private var phase = 0
    @State private var scores = [0, 0]
    @State private var progress = [0.0, 0.0]
    @State private var playing = false
    @State private var runID = UUID()
    @State private var inning = 9.0
    @State private var selectedGame = 0
    @State private var shareURL: URL?
    @State private var shareFailed = false
    @State private var showSources = false

    private var exploring: Bool { phase == 3 }
    private var headline: String {
        switch phase {
        case 0: "ALL.\nOR NOTHING."
        case 1: "Once would have\nbeen enough."
        case 2: "Again."
        default: "42 runs.\nZero answers."
        }
    }

    var body: some View {
        GeometryReader { viewport in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("MILWAUKEE / 2026").tracking(2)
                    Spacer()
                    Text(exploring ? "02 / 02" : "0\(max(phase, 1)) / 02")
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(ShutoutStyle.gold)

                Text(headline)
                    .font(.system(size: phase == 0 ? 44 : 36, weight: .black, design: .rounded))
                    .tracking(-2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if loadFailed {
                    ContentUnavailableView("Story unavailable", systemImage: "exclamationmark.circle", description: Text("The saved game data could not be read."))
                } else if games.count == 2 {
                    HStack(spacing: 16) {
                        ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("vs. \(game.opponent)").font(.system(size: 12, weight: .semibold))
                                Text("\(scores[index])–0")
                                    .font(.system(size: 32, weight: .black, design: .rounded)).monospacedDigit()
                                Text(game.dateLabel).font(.system(size: 9, design: .monospaced))
                            }
                            .foregroundStyle(index == 0 ? ShutoutStyle.gold : ShutoutStyle.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(phase == 1 && index == 1 ? 0.35 : 1)
                        }
                    }
                    ShutoutLineChart(games: games, firstProgress: progress[0], secondProgress: progress[1])
                        .frame(height: min(300, max(220, viewport.size.height * 0.36)))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Cumulative runs by inning. Milwaukee against Seattle: \(scores[0]). Against Cincinnati: \(scores[1]). Both opponents: zero.")
                    Text(phase == 0 ? "Two lines climb. One never moves." : "CUMULATIVE RUNS · INNING TOTALS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(ShutoutStyle.cream.opacity(0.6))
                        .frame(maxWidth: .infinity)

                    if exploring { exploration }
                    else {
                        Text(phase == 0 ? "Two nights. One season. A place in baseball history." : phase == 1 ? "Seattle • August 18\nOne run through four innings. Then the climb." : "Cincinnati • September 11\nAnother eruption. Another untouched zero.")
                            .font(.system(size: 16))
                            .foregroundStyle(ShutoutStyle.cream.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    controls
                }
            }
            .padding(20)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !exploring && games.count == 2 {
                playbackButton.padding(.horizontal, 20).padding(.vertical, 10)
                    .background(ShutoutStyle.navy)
            }
        }
        .background(ShutoutStyle.navy.ignoresSafeArea())
        .foregroundStyle(ShutoutStyle.cream)
        .navigationTitle("All. Or Nothing.")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ShutoutStyle.navy, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { load() }
        .task(id: runID) { if playing { await animateStory() } }
        .onDisappear { playing = false; runID = UUID() }
        .onChange(of: scenePhase) { _, value in
            if value != .active { playing = false; runID = UUID() }
        }
        .sheet(isPresented: $showSources) { sources }
    }

    private var exploration: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("The first team in MLB history with two shutout wins of 20+ runs in one season.")
                .font(.system(size: 19, weight: .semibold))
            Label("POSTSEASON CLINCHED · SEPTEMBER 11", systemImage: "ticket.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ShutoutStyle.gold)
            Divider().overlay(ShutoutStyle.cream.opacity(0.2))
            HStack {
                Text("REBUILD BOTH NIGHTS")
                Spacer()
                Text(inning == 0 ? "START" : inning == 9 ? "FINAL" : "THROUGH \(Int(inning))")
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            Slider(value: $inning, in: 0...9, step: 1)
                .tint(ShutoutStyle.gold)
                .accessibilityLabel("Inning, both games")
                .accessibilityValue(inning == 0 ? "Before the game" : "Through inning \(Int(inning))")
                .onChange(of: inning) { _, value in
                    scores = games.map { $0.score(through: Int(value)) }
                    progress = [value, value]
                }
            HStack {
                Button { inning = max(0, inning - 1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous inning")
                .disabled(inning == 0)
                Spacer()
                Text(inning == 0 ? "BEFORE FIRST PITCH" : "INNING \(Int(inning))")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                Button { inning = min(9, inning + 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next inning")
                .disabled(inning == 9)
            }
            .tint(ShutoutStyle.gold)
            HStack(spacing: 8) {
                ForEach(Array(games.enumerated()), id: \.offset) { index, game in
                    Button { selectedGame = index } label: {
                        Text(game.opponent).font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(minHeight: 44)
                            .foregroundStyle(selectedGame == index ? ShutoutStyle.navy : ShutoutStyle.cream)
                            .background(selectedGame == index ? ShutoutStyle.gold : ShutoutStyle.cream.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedGame == index ? .isSelected : [])
                }
            }
            Text(inning == 0 ? "Move through the innings to uncover each scoring play." : "SCORING PLAYS · INNING \(Int(inning))")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(ShutoutStyle.gold)
            let plays = games[selectedGame].plays.filter { $0.inning == Int(inning) }
            if plays.isEmpty && inning > 0 {
                Text(inning == 9 ? "Milwaukee did not need to bat in the ninth. The shutout was complete." : "No Milwaukee runs this inning. The opponent stayed at zero.")
                    .font(.system(size: 15))
            }
            ForEach(plays) { play in
                HStack(alignment: .top, spacing: 12) {
                    Text("+\(play.runs)").font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(ShutoutStyle.gold).frame(width: 38)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(play.description).font(.system(size: 15))
                        Text("MIL \(play.total)  ·  \(games[selectedGame].opponent.uppercased()) 0")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(ShutoutStyle.cream.opacity(0.6))
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var playbackButton: some View {
            Button {
                if playing { playing = false; runID = UUID() }
                else if reduceMotion { finish() }
                else { scores = [0, 0]; progress = [0, 0]; phase = 1; playing = true; runID = UUID() }
            } label: {
                Label(playing ? "Pause story" : phase == 0 ? "Play the impossible" : "Replay both nights", systemImage: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity).padding(17)
                    .foregroundStyle(ShutoutStyle.navy).background(ShutoutStyle.gold, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            if exploring { playbackButton }
            if !exploring {
                Button("Explore the final scores") { playing = false; runID = UUID(); finish() }
                    .font(.system(size: 14)).padding(8)
            } else if let shareURL {
                ShareLink(item: shareURL, preview: SharePreview("All. Or Nothing. — Milwaukee 2026")) {
                    Label("Share this piece of history", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold)).padding(10)
                }
            } else if shareFailed {
                Button("Retry share poster") { makePoster() }
            }
            Button("Box scores & story sources") { showSources = true }
                .font(.system(size: 12)).foregroundStyle(ShutoutStyle.cream.opacity(0.65)).padding(8)
        }
        .tint(ShutoutStyle.cream)
    }

    private var sources: some View {
        NavigationStack {
            List {
                Section("Verified game data") {
                    ForEach(games) { game in
                        Link("\(game.dateLabel) · \(game.total)–0 vs. \(game.opponent)", destination: game.source)
                    }
                    Text("Inning totals and play descriptions come from MLB's final game feeds. The home ninth was not played in either game.")
                }
                Section("Historical distinction & playoff clinch") {
                    Link("Yahoo Sports · September 12, 2026", destination: URL(string: "https://malaysia.news.yahoo.com/brewers-clinch-playoffs-become-first-team-in-mlb-history-to-record-multiple-shutout-wins-of-20-plus-runs-in-a-season-121406831.html")!)
                    Text("The historical first is sourced reporting; the two game feeds verify the scores and scoring sequence.")
                }
            }
            .navigationTitle("Story sources")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSources = false } } }
        }
    }

    private func load() {
        guard games.isEmpty else { return }
        struct Payload: Decodable { let games: [ShutoutGame] }
        do {
            guard let url = Bundle.main.url(forResource: "brewers-shutouts", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            let decoded = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url)).games
            guard decoded.count == 2, decoded.map(\.total) == [22, 20], decoded.allSatisfy({ $0.innings.count == 9 && $0.score(through: 9) == $0.total }) else { throw CocoaError(.fileReadCorruptFile) }
            games = decoded
            makePoster()
        } catch { loadFailed = true }
    }

    @MainActor private func animateStory() async {
        do {
            for index in 0..<2 {
                phase = index + 1
                try await Task.sleep(for: .seconds(1.4))
                for frame in 1...9 {
                    try Task.checkCancellation()
                    scores[index] = games[index].score(through: frame)
                    withAnimation(.linear(duration: 1.15)) {
                        progress[index] = Double(frame)
                    }
                    try await Task.sleep(for: .seconds(1.15))
                    if games[index].innings[frame - 1] > 0 {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)
                    }
                }
                try await Task.sleep(for: .seconds(1.6))
            }
            finish()
        } catch { /* Navigation, pause and backgrounding cancel playback. */ }
    }

    private func finish() {
        phase = 3; playing = false; inning = 9
        scores = games.map(\.total)
        progress = [9, 9]
    }

    @MainActor private func makePoster() {
        guard games.count == 2 else { return }
        let renderer = ImageRenderer(content: ShutoutPoster(games: games).frame(width: 600, height: 900))
        renderer.scale = 2
        do {
            guard let data = renderer.uiImage?.pngData() else { throw CocoaError(.fileWriteUnknown) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("hub-ball-all-or-nothing.png")
            try data.write(to: url, options: .atomic)
            shareURL = url; shareFailed = false
        } catch { shareFailed = true }
    }
}

/// Straight segments connect verified end-of-inning totals; no fitted curve or invented play timing.
private struct ShutoutLineChart: View, Animatable {
    let games: [ShutoutGame]
    var firstProgress: Double
    var secondProgress: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(firstProgress, secondProgress) }
        set { firstProgress = newValue.first; secondProgress = newValue.second }
    }

    var body: some View {
        Canvas { context, size in
            let left: CGFloat = 25
            let right = size.width - 30
            let top: CGFloat = 12
            let bottom = size.height - 36
            func point(_ inning: Double, _ runs: Double) -> CGPoint {
                CGPoint(x: left + (right - left) * inning / 9,
                        y: bottom - (bottom - top) * runs / 24)
            }
            for runs in [0, 5, 10, 15, 20] {
                let y = point(0, Double(runs)).y
                var grid = Path(); grid.move(to: CGPoint(x: left, y: y)); grid.addLine(to: CGPoint(x: right, y: y))
                context.stroke(grid, with: .color(ShutoutStyle.cream.opacity(runs == 0 ? 0.7 : 0.12)),
                               style: StrokeStyle(lineWidth: runs == 0 ? 2 : 0.5, dash: runs == 0 ? [4, 4] : []))
                context.draw(Text(String(runs)).font(.system(size: 9, design: .monospaced)).foregroundColor(ShutoutStyle.cream.opacity(0.65)), at: CGPoint(x: left - 9, y: y), anchor: .trailing)
            }
            for inning in 1...9 {
                context.draw(Text(String(inning)).font(.system(size: 10, design: .monospaced)).foregroundColor(ShutoutStyle.cream.opacity(0.65)), at: CGPoint(x: point(Double(inning), 0).x, y: bottom + 14))
            }
            context.draw(Text("INNING").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(ShutoutStyle.cream.opacity(0.5)), at: CGPoint(x: (left + right) / 2, y: size.height - 2), anchor: .bottom)
            for (index, game) in games.enumerated() {
                let progress = min(9, max(0, index == 0 ? firstProgress : secondProgress))
                guard progress > 0 else { continue }
                let color = index == 0 ? ShutoutStyle.gold : ShutoutStyle.blue
                var path = Path(); path.move(to: point(0, 0))
                let complete = Int(progress)
                if complete > 0 {
                    for inning in 1...complete { path.addLine(to: point(Double(inning), Double(game.score(through: inning)))) }
                }
                var tip = point(Double(complete), Double(game.score(through: complete)))
                if complete < 9 {
                    let fraction = progress - Double(complete)
                    let runs = Double(game.score(through: complete)) + fraction * Double(game.innings[complete])
                    tip = point(progress, runs)
                    path.addLine(to: tip)
                }
                context.stroke(path, with: .color(color.opacity(0.12)), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: index == 0 ? [] : [6, 3]))
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 4, y: tip.y - 4, width: 8, height: 8)), with: .color(color))
                if progress == 9 {
                    context.draw(Text(String(game.total)).font(.system(size: 12, weight: .black, design: .rounded)).foregroundColor(color), at: CGPoint(x: tip.x + 9, y: tip.y), anchor: .leading)
                }
            }
            context.draw(Text("OPPONENTS  0").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(ShutoutStyle.cream), at: CGPoint(x: right - 4, y: bottom - 9), anchor: .bottomTrailing)
        }
    }
}

private struct ShutoutPoster: View {
    let games: [ShutoutGame]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("MILWAUKEE BREWERS / 2026").font(.system(size: 14, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(ShutoutStyle.gold)
            Text("ALL.\nOR NOTHING.").font(.system(size: 68, weight: .black, design: .rounded)).tracking(-3)
            HStack {
                Text("vs. SEATTLE · AUG 18").foregroundStyle(ShutoutStyle.gold)
                Spacer()
                Text("vs. CINCINNATI · SEP 11").foregroundStyle(ShutoutStyle.blue)
            }.font(.system(size: 12, weight: .bold, design: .monospaced))
            ShutoutLineChart(games: games, firstProgress: 9, secondProgress: 9)
                .frame(height: 350)
            Text("42 runs. Zero answers.").font(.system(size: 30, weight: .bold))
            Text("The first MLB team with two 20+ run shutouts in one season.")
                .font(.system(size: 17)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Text("HUB BALL").fontWeight(.black).tracking(3)
                Spacer()
                Text("BASEBALL. WORTH FEELING.").font(.system(size: 10, weight: .bold)).tracking(1)
            }.foregroundStyle(ShutoutStyle.gold)
        }
        .padding(42).foregroundStyle(ShutoutStyle.cream).background(ShutoutStyle.navy)
    }
}

struct BrewersShutoutStoryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("MILWAUKEE / 2026").tracking(2)
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(ShutoutStyle.gold)
            HStack(alignment: .bottom, spacing: 18) {
                Text("ALL.\nOR NOTHING.")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .tracking(-1).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(ShutoutStyle.blue)
                    .accessibilityHidden(true)
            }
            Text("42 runs. Zero answers.").font(.system(size: 17, weight: .semibold))
            HStack {
                Text("WATCH HISTORY HAPPEN").tracking(1)
                Spacer()
                Image(systemName: "play.fill")
            }
            .font(.system(size: 11, weight: .bold))
            .padding(.top, 4).foregroundStyle(ShutoutStyle.gold)
        }
        .padding(24)
        .foregroundStyle(ShutoutStyle.cream)
        .background(ShutoutStyle.navy, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
