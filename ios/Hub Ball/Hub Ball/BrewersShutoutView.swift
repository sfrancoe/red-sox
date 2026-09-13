import SwiftUI
import UIKit

private enum ShutoutStyle {
    static let navy = Color(red: 0.035, green: 0.075, blue: 0.14)
    static let gold = Color(red: 1, green: 0.77, blue: 0.18)
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
                    HStack(alignment: .bottom, spacing: 26) {
                        ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                            ShutoutTower(game: game, score: phase == 0 ? 0 : scores[index], highlight: exploring && selectedGame == index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard exploring else { return }
                                    selectedGame = index
                                }
                                .accessibilityAddTraits(exploring ? .isButton : [])
                                .accessibilityAction {
                                    if exploring { selectedGame = index }
                                }
                                .opacity(phase == 1 && index == 1 ? 0.15 : 1)
                        }
                    }
                    .frame(height: min(340, max(290, viewport.size.height * 0.48)))
                    Text(phase == 0 ? "Keep your eye on the zeros." : "ONE GOLD TILE = ONE MILWAUKEE RUN")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(ShutoutStyle.cream.opacity(0.6))
                        .frame(maxWidth: .infinity)

                    if exploring { exploration }
                    else {
                        Text(phase == 0 ? "Two nights. One season. A place in baseball history." : phase == 1 ? "Seattle • August 18\nThe first tower reaches 22. The zero never moves." : "Cincinnati • September 11\nAnother eruption. Another untouched zero.")
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
                else { scores = [0, 0]; phase = 1; playing = true; runID = UUID() }
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
                    Text("Scoring tiles and play descriptions come from MLB's final game feeds. The home ninth was not played in either game.")
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
                for play in games[index].plays {
                    try Task.checkCancellation()
                    for total in (scores[index] + 1)...play.total {
                        scores[index] = total
                        try await Task.sleep(for: .milliseconds(130))
                    }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)
                    try await Task.sleep(for: .milliseconds(650))
                }
                try await Task.sleep(for: .seconds(1.6))
            }
            finish()
        } catch { /* Navigation, pause and backgrounding cancel playback. */ }
    }

    private func finish() {
        phase = 3; playing = false; inning = 9
        scores = games.map(\.total)
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

private struct ShutoutTower: View {
    let game: ShutoutGame
    let score: Int
    var highlight = false
    var body: some View {
        VStack(spacing: 8) {
            Text(String(score)).font(.system(size: 42, weight: .black, design: .rounded)).monospacedDigit()
                .foregroundStyle(ShutoutStyle.gold)
            GeometryReader { proxy in
                VStack(spacing: 3) {
                    ForEach((1...22).reversed(), id: \.self) { run in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(run <= score ? ShutoutStyle.gold : ShutoutStyle.cream.opacity(0.035))
                            .frame(height: max(1, (proxy.size.height - 63) / 22))
                    }
                }
            }
            Rectangle().fill(ShutoutStyle.gold.opacity(0.5)).frame(height: 1)
            Text("0").font(.system(size: 52, weight: .black, design: .rounded)).monospacedDigit()
            Text(game.opponent.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced))
            Text(game.dateLabel).font(.system(size: 9, design: .monospaced)).opacity(0.6)
            Capsule().fill(highlight ? ShutoutStyle.gold : .clear).frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.dateLabel). Milwaukee \(score), \(game.opponent) zero.\(highlight ? " Selected." : "")")
    }
}

private struct ShutoutPoster: View {
    let games: [ShutoutGame]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("MILWAUKEE BREWERS / 2026").font(.system(size: 14, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(ShutoutStyle.gold)
            Text("ALL.\nOR NOTHING.").font(.system(size: 68, weight: .black, design: .rounded)).tracking(-3)
            HStack(spacing: 45) {
                ForEach(games) { game in ShutoutTower(game: game, score: game.total) }
            }.frame(height: 390)
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
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach([22, 20], id: \.self) { runs in
                        VStack(spacing: 2) {
                            ForEach(0..<runs, id: \.self) { _ in
                                Rectangle().fill(ShutoutStyle.gold).frame(width: 19, height: 3)
                            }
                            Text("0").font(.system(size: 23, weight: .black, design: .rounded))
                        }
                    }
                }.accessibilityHidden(true)
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
