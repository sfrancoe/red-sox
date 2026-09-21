import SwiftUI
import UIKit

private enum ShutoutStyle {
    static let navy = Color(red: 0.035, green: 0.075, blue: 0.14)
    static let gold = Color(red: 1, green: 0.77, blue: 0.18)
    static let blue = Color(red: 0.36, green: 0.76, blue: 1)
    static let cream = Color(red: 0.97, green: 0.94, blue: 0.86)
    static let pitcherColors: [Color] = [.cyan, .mint, .purple, .orange]
}

struct ShutoutPerson: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    var surname: String { name.split(separator: " ").dropFirst().joined(separator: " ") }
}

struct ShutoutEvent: Decodable, Identifiable {
    let id: Int
    let inning: Int
    let top: Bool
    let position: Double
    let total: Int
    let runs: Int
    let rbi: Int
    let batter: ShutoutPerson
    let pitcher: ShutoutPerson
    let scorers: [ShutoutPerson]
    let outs: Int
    let strikeouts: Int
    let hits: Int
    let walks: Int
    let event: String
    let description: String
    var moment: String { "\(top ? "TOP" : "BOT") \(inning)" }
    func involves(_ id: Int) -> Bool {
        top ? pitcher.id == id : (batter.id == id && (rbi > 0 || hits > 0)) || scorers.contains { $0.id == id }
    }
}

struct ShutoutGame: Decodable, Identifiable {
    let id: Int
    let date: String
    let opponent: String
    let total: Int
    let events: [ShutoutEvent]
    var dateLabel: String { date == "2026-08-18" ? "AUG 18, 2026" : "SEP 11, 2026" }
    var boxScoreURL: URL { URL(string: "https://www.mlb.com/gameday/\(id)/final/box")! }
}

private struct HitterCredit: Identifiable {
    let person: ShutoutPerson
    var rbi = 0
    var runs = 0
    var hits = 0
    var id: Int { person.id }
}

private func hitterCredits(_ events: [ShutoutEvent]) -> [HitterCredit] {
    var credits: [Int: HitterCredit] = [:]
    for event in events where !event.top {
        if event.rbi > 0 || event.hits > 0 {
            var hitter = credits[event.batter.id] ?? HitterCredit(person: event.batter)
            hitter.rbi += event.rbi; hitter.hits += event.hits
            credits[hitter.id] = hitter
        }
        for runner in event.scorers {
            var hitter = credits[runner.id] ?? HitterCredit(person: runner)
            hitter.runs += 1; credits[hitter.id] = hitter
        }
    }
    return credits.values.sorted {
        if $0.rbi != $1.rbi { return $0.rbi > $1.rbi }
        return $0.person.name < $1.person.name
    }
}

private func cumulativeBattingEvents(_ games: [ShutoutGame], chapter: Int, cursor: Int) -> [ShutoutEvent] {
    let finished = games.prefix(chapter).flatMap(\.events)
    guard chapter < games.count else { return finished }
    return finished + games[chapter].events.prefix(max(0, cursor + 1))
}

struct BrewersShutoutView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var games: [ShutoutGame] = []
    @State private var loadFailed = false
    @State private var chapter = 0
    @State private var cursor = -1
    @State private var playing = false
    @State private var playbackID = UUID()
    @State private var selectedPlayer: ShutoutPerson?
    @State private var replayPlayer: Int?
    @State private var showSources = false
    @State private var showAllHitters = false
    @State private var shareURL: URL?
    @State private var shareFailed = false

    private var combined: Bool { chapter == 2 }
    private var game: ShutoutGame { games[min(chapter, 1)] }
    private var seen: [ShutoutEvent] { combined ? games.flatMap(\.events) : Array(game.events.prefix(cursor + 1)) }
    private var current: ShutoutEvent? { combined || cursor < 0 ? nil : game.events[cursor] }
    private var score: Int { combined ? 42 : current?.total ?? 0 }
    // Batting credits carry forward; pitching and the score line stay game-specific.
    private var cumulativeEvents: [ShutoutEvent] {
        cumulativeBattingEvents(games, chapter: chapter, cursor: cursor)
    }
    private var credits: [HitterCredit] { hitterCredits(cumulativeEvents) }
    private var nonRBI: Int { cumulativeEvents.filter { !$0.top }.reduce(0) { $0 + $1.runs - $1.rbi } }
    private var leaderMaximum: Int { max(1, hitterCredits(games.flatMap(\.events)).map(\.rbi).max() ?? 1) }
    private var usesExpandedReadingLayout: Bool { dynamicTypeSize >= .xxxLarge }

    var body: some View {
        ZStack {
            ShutoutStyle.navy.ignoresSafeArea()
            if games.count == 2 {
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Color.clear.frame(height: 0).id("top")
                            chapterPicker
                            header
                            if combined { combinedChart } else { gameStage }
                            hitterPanel
                            if combined {
                                ForEach(games) { game in
                                    PitchingStrip(events: game.events, title: "vs. \(game.opponent) · 27 outs", select: { selectedPlayer = $0 })
                                }
                                Text("Two wins. 42 runs. Every out protected a zero.")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                Label("POSTSEASON CLINCHED · SEPTEMBER 11", systemImage: "ticket.fill")
                                    .font(.system(size: 11, weight: .bold)).foregroundStyle(ShutoutStyle.gold)
                            }
                            bottomControls
                        }
                        .padding(.horizontal, 20).padding(.bottom, 20)
                        .frame(maxWidth: 700).frame(maxWidth: .infinity)
                    }
                    .onChange(of: chapter) { _, _ in scroll.scrollTo("top", anchor: .top) }
                    .onChange(of: playing) { _, active in if active { scroll.scrollTo("top", anchor: .top) } }
                    .safeAreaInset(edge: .bottom, spacing: 0) { transport }
                }
            } else if loadFailed {
                ContentUnavailableView("Story unavailable", systemImage: "exclamationmark.circle", description: Text("The saved game data could not be read."))
            } else { ProgressView().tint(ShutoutStyle.gold) }
        }
        .foregroundStyle(ShutoutStyle.cream)
        .navigationTitle("Who Built the 42?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ShutoutStyle.navy, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { load() }
        .task(id: playbackID) { if playing { await animateStory() } }
        .onDisappear { stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stop() } }
        .onChange(of: reduceMotion) { _, reduced in if reduced { stop() } }
        .sheet(isPresented: $showSources) { sources }
        .sheet(item: $selectedPlayer) { player in playerSheet(player) }
    }

    private var chapterPicker: some View {
        Group {
            if usesExpandedReadingLayout {
                VStack(spacing: 8) {
                    chapterButtons
                }
            } else {
                HStack(spacing: 6) {
                    chapterButtons
                }
            }
        }
    }

    @ViewBuilder
    private var chapterButtons: some View {
            ForEach(0..<3, id: \.self) { index in
                Button {
                    stop(); chapter = index; cursor = index == 2 ? -1 : games[index].events.count - 1
                } label: {
                    Text(["01 SEATTLE", "02 CINCINNATI", "03 THE 42"][index])
                        .font(usesExpandedReadingLayout ? .subheadline.weight(.bold) : .system(size: 10, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity).frame(minHeight: 44)
                        .background(chapter == index ? ShutoutStyle.gold : ShutoutStyle.cream.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(chapter == index ? ShutoutStyle.navy : ShutoutStyle.cream)
                }
                .buttonStyle(.plain).accessibilityAddTraits(chapter == index ? .isSelected : [])
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(combined ? "THE PEOPLE BEHIND 42–0" : "\(game.dateLabel) / \(chapter == 0 ? "THE SLOW FUSE" : "THE AVALANCHE")")
                .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(ShutoutStyle.gold)
            HStack(alignment: .firstTextBaseline) {
                Text(combined ? "WHO BUILT\nTHE 42?" : "\(score)–0")
                    .font(.system(size: combined ? 38 : 52, weight: .black, design: .rounded)).tracking(-2).monospacedDigit()
                    .accessibilityLabel(combined ? "Who built the 42?" : "Milwaukee \(score), \(game.opponent) zero")
                Spacer()
                if !combined {
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("MIL vs. \(game.opponent.uppercased())").font(.system(size: 10, weight: .bold))
                        Text(current?.moment ?? "BEFORE FIRST PITCH").font(.system(size: 11, design: .monospaced))
                    }.foregroundStyle(ShutoutStyle.cream.opacity(0.65))
                }
            }
            if combined {
                Text("The bats built the lead. The arms kept the zero.")
                    .font(.system(size: 17)).foregroundStyle(ShutoutStyle.cream.opacity(0.75))
            }
        }
    }

    private var gameStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            raceChart
            momentCard
            PitchingStrip(events: seen, title: "PROTECTING THE ZERO", compact: true, activeOnly: true, select: { selectedPlayer = $0 })
        }
    }

    private var raceChart: some View {
        RBIRaceChart(games: combined ? games : [game],
                     cursors: combined ? games.map { $0.events.count - 1 } : [cursor],
                     progress: combined ? 0 : Double(cursor + 1),
                     credits: credits, maximum: leaderMaximum,
                     activePlayer: current?.top == false && (current?.rbi ?? 0) > 0 ? current?.batter.id : nil,
                     reduceMotion: reduceMotion, lineDuration: (current?.runs ?? 0) > 0 ? 0.85 : 0.18, select: { selectedPlayer = $0 })
    }

    private var momentCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let event = current {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.top ? event.pitcher.name : event.batter.name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    if event.runs > 0 {
                        Text("+\(event.runs)").font(.system(size: 28, weight: .black, design: .rounded)).foregroundStyle(ShutoutStyle.gold)
                    } else if event.top && event.strikeouts > 0 {
                        Text("K").font(.system(size: 28, weight: .black)).foregroundStyle(ShutoutStyle.blue)
                    }
                }
                Text(event.runs == 4 && event.event == "Home Run" ? "GRAND SLAM" : event.event.uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced)).tracking(1).foregroundStyle(event.top ? ShutoutStyle.blue : ShutoutStyle.gold)
                if !event.scorers.isEmpty {
                    Label(event.scorers.map(\.surname).joined(separator: " · "), systemImage: "baseball.diamond.bases")
                        .font(.system(size: 12)).accessibilityLabel("Crossed home: " + event.scorers.map(\.name).joined(separator: ", "))
                    Text("\(event.rbi) RBI · \(event.runs - event.rbi) RUNS WITHOUT RBI")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(ShutoutStyle.cream.opacity(0.65))
                } else {
                    Text(event.top ? "\(event.outs) out\(event.outs == 1 ? "" : "s") recorded on this play. No runs allowed." : "The bats keep working. Every run needs a beginning.")
                        .font(.system(size: 12)).foregroundStyle(ShutoutStyle.cream.opacity(0.65))
                }
            } else {
                Text("WHO LIGHTS THE FUSE?").font(.system(size: 16, weight: .black, design: .rounded))
                Text("The line climbs. RBI bars grow and race for the leftmost spot.")
                    .font(.system(size: 13)).foregroundStyle(ShutoutStyle.cream.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .padding(14)
        .background((current?.top == true ? ShutoutStyle.blue : ShutoutStyle.gold).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var combinedChart: some View { raceChart }

    private var hitterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(combined ? "WHO DROVE THEM HOME?" : "CUMULATIVE RUN PRODUCERS")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                Spacer()
                Text("RBI").font(.system(size: 11, weight: .bold)).foregroundStyle(ShutoutStyle.gold)
            }
            if credits.isEmpty {
                Text("The leaderboard grows with every hit, run and RBI.")
                    .font(.system(size: 13)).foregroundStyle(ShutoutStyle.cream.opacity(0.6)).padding(.vertical, 10)
            }
            ForEach(showAllHitters || combined ? credits : Array(credits.prefix(4))) { hitter in
                Button { selectedPlayer = hitter.person } label: {
                    HitterBar(hitter: hitter, maximum: leaderMaximum, highlighted: current?.batter.id == hitter.id && current?.top == false)
                }.buttonStyle(.plain)
            }
            if !combined && credits.count > 4 {
                Button(showAllHitters ? "Show leaders" : "All \(credits.count) contributors") { showAllHitters.toggle() }
                    .font(.system(size: 13)).tint(ShutoutStyle.gold).padding(.vertical, 6)
            }
            HStack {
                Text("RUNS WITHOUT AN RBI")
                Spacer()
                Text(String(nonRBI)).foregroundStyle(ShutoutStyle.gold)
            }.font(.system(size: 11, weight: .bold, design: .monospaced))
            if combined {
                Text("\(credits.reduce(0) { $0 + $1.rbi }) RBI + \(nonRBI) runs without an RBI = 42 runs. Runs scored are shown separately; they overlap with RBI and are not added again.")
                    .font(.system(size: 12)).foregroundStyle(ShutoutStyle.cream.opacity(0.65))
            } else {
                Text("Totals carry across both games. R = runs scored, H = hits. Tap a player for their moments.")
                    .font(.system(size: 11)).foregroundStyle(ShutoutStyle.cream.opacity(0.6))
            }
        }
        .padding(16).background(ShutoutStyle.cream.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var transport: some View {
        VStack(spacing: 6) {
            if !combined {
                Slider(value: Binding(get: { Double(cursor + 1) }, set: { stop(); cursor = Int($0) - 1 }), in: 0...Double(game.events.count), step: 1)
                    .tint(ShutoutStyle.gold).accessibilityLabel("Game progress, play by play")
                    .accessibilityValue(current?.moment ?? "Before first pitch")
            }
            HStack(spacing: 10) {
                if !combined {
                    Button { stop(); cursor = max(-1, cursor - 1) } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }
                        .disabled(cursor < 0).accessibilityLabel("Previous play")
                }
                Button {
                    if playing { stop() }
                    else if reduceMotion { chapter = 2; cursor = -1 }
                    else {
                        replayPlayer = nil
                        if combined { chapter = 0; cursor = -1 }
                        if cursor == game.events.count - 1 { cursor = -1 }
                        playing = true; playbackID = UUID()
                    }
                } label: {
                    Label(playing ? "Pause" : combined ? "Replay both nights" : cursor < 0 ? "Light the fuse" : "Continue story", systemImage: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).frame(height: 44)
                        .foregroundStyle(ShutoutStyle.navy).background(ShutoutStyle.gold, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
                if !combined {
                    Button { stop(); cursor = min(game.events.count - 1, cursor + 1) } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }
                        .disabled(cursor == game.events.count - 1).accessibilityLabel("Next play")
                }
            }.tint(ShutoutStyle.cream)
        }.padding(.horizontal, 16).padding(.vertical, 8).background(ShutoutStyle.navy)
    }

    private var bottomControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !combined {
                if let current { Text(current.description).font(.system(size: 14)).foregroundStyle(ShutoutStyle.cream.opacity(0.7)) }
                Button("See who built all 42 runs →") { stop(); chapter = 2 }
                    .font(.system(size: 15, weight: .bold)).padding(.vertical, 10)
            } else {
                Text("The first MLB team with two shutout wins of 20+ runs in one season.")
                    .font(.system(size: 14)).foregroundStyle(ShutoutStyle.cream.opacity(0.7))
            }
            if let shareURL {
                ShareLink(item: shareURL, preview: SharePreview("Who Built the 42? — Milwaukee 2026")) {
                    Label("Share the people behind 42–0", systemImage: "square.and.arrow.up").padding(.vertical, 10)
                }
            } else if shareFailed { Button("Retry share poster") { makePoster() } }
            Button("Box scores & story sources") { stop(); showSources = true }
                .font(.system(size: 13)).padding(.vertical, 10)
        }.tint(ShutoutStyle.gold)
    }

    private func playerSheet(_ player: ShutoutPerson) -> some View {
        NavigationStack {
            List {
                ForEach(Array(games.enumerated()), id: \.element.id) { gameIndex, game in
                    let moments = game.events.filter { $0.involves(player.id) }
                    if !moments.isEmpty {
                        Section("vs. \(game.opponent) · \(game.dateLabel)") {
                            Button("Replay \(player.surname)’s moments") {
                                stop(); selectedPlayer = nil; chapter = gameIndex; cursor = -1
                                replayPlayer = player.id; playing = true; playbackID = UUID()
                            }
                            ForEach(moments) { event in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(event.moment) · \(event.top ? "PITCHING" : "HITTING")").font(.caption.bold())
                                    Text(event.description).font(.subheadline)
                                }
                            }
                        }
                    }
                }
            }.navigationTitle(player.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedPlayer = nil } } }
        }
        .onAppear { stop() }
    }

    private var sources: some View {
        NavigationStack {
            List {
                Section("Readable box scores") {
                    ForEach(games) { game in Link("\(game.dateLabel) · \(game.total)–0 vs. \(game.opponent)", destination: game.boxScoreURL) }
                }
                Section("How we count contributions") {
                    Text("RBI bars accumulate across both games: Seattle’s totals carry forward into Cincinnati. They rank the top six contributors from left to right, with alphabetical ties. Bar heights use RBI totals; the background lines use team run differential over innings. The graph advances through completed plays. Plays are spaced evenly within each inning, not by clock time. RBI, runs scored, hits and pitching totals reconcile to MLB's final box scores.")
                    Text("Runs without an RBI remain separate. Pitcher outs include outs made by the defense; they are not estimates of runs prevented. The 42–0 combines two games.")
                }
                Section("Historical distinction & playoff clinch") {
                    Link("Yahoo Sports · September 12, 2026", destination: URL(string: "https://malaysia.news.yahoo.com/brewers-clinch-playoffs-become-first-team-in-mlb-history-to-record-multiple-shutout-wins-of-20-plus-runs-in-a-season-121406831.html")!)
                }
            }.navigationTitle("Story sources")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSources = false } } }
        }
    }

    private func stop() { playing = false; playbackID = UUID() }

    @MainActor private func animateStory() async {
        do {
            let firstChapter = min(chapter, 1)
            let lastChapter = replayPlayer == nil ? 1 : firstChapter
            for index in firstChapter...lastChapter {
                if index != chapter { chapter = index; cursor = -1 }
                for next in (cursor + 1)..<games[index].events.count {
                    try Task.checkCancellation()
                    let event = games[index].events[next]
                    if let replayPlayer, !event.involves(replayPlayer) { continue }
                    cursor = next
                    if event.runs > 0 {
                        UIImpactFeedbackGenerator(style: event.runs >= 4 ? .heavy : .soft).impactOccurred()
                    }
                    let delay = replayPlayer != nil ? 1.6 : event.runs >= 4 ? 2.2 : event.runs > 0 ? 1.4 : event.top && event.strikeouts > 0 ? 0.45 : 0.18
                    try await Task.sleep(for: .seconds(delay))
                }
                try await Task.sleep(for: .seconds(1.5))
            }
            if replayPlayer == nil { chapter = 2 }
            replayPlayer = nil; playing = false
        } catch { /* Pause, navigation, and backgrounding cancel playback. */ }
    }

    private func load() {
        guard games.isEmpty else { return }
        struct Payload: Decodable { let games: [ShutoutGame] }
        do {
            guard let url = Bundle.main.url(forResource: "brewers-shutouts", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
            guard payload.games.count == 2, payload.games.map(\.total) == [22, 20], payload.games.allSatisfy({ !$0.events.isEmpty && $0.events.last?.total == $0.total }) else { throw CocoaError(.fileReadCorruptFile) }
            games = payload.games; makePoster()
        } catch { loadFailed = true }
    }

    @MainActor private func makePoster() {
        let renderer = ImageRenderer(content: ContributionPoster(games: games).frame(width: 600, height: 1200))
        renderer.scale = 2
        do {
            guard let data = renderer.uiImage?.pngData() else { throw CocoaError(.fileWriteUnknown) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("hub-ball-who-built-the-42.png")
            try data.write(to: url, options: .atomic); shareURL = url; shareFailed = false
        } catch { shareFailed = true }
    }
}

private struct HitterBar: View {
    let hitter: HitterCredit
    let maximum: Int
    var highlighted = false
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(hitter.person.name).font(.system(size: 14, weight: highlighted ? .black : .semibold))
                Spacer()
                Text("\(hitter.runs) R · \(hitter.hits) H").font(.system(size: 10, design: .monospaced)).foregroundStyle(ShutoutStyle.cream.opacity(0.6))
                Text(String(hitter.rbi)).font(.system(size: 19, weight: .black, design: .rounded)).foregroundStyle(ShutoutStyle.gold).frame(width: 24, alignment: .trailing)
            }
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(0..<maximum, id: \.self) { run in
                        RoundedRectangle(cornerRadius: 2).fill(run < hitter.rbi ? ShutoutStyle.gold : ShutoutStyle.cream.opacity(0.055))
                    }
                }.frame(width: proxy.size.width)
            }.frame(height: 9)
        }.padding(.vertical, 5)
        .foregroundStyle(ShutoutStyle.cream)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(hitter.person.name): \(hitter.rbi) RBI, \(hitter.runs) runs scored, \(hitter.hits) hits")
    }
}

private struct PitchingStrip: View {
    let events: [ShutoutEvent]
    let title: String
    var compact = false
    var activeOnly = false
    let select: (ShutoutPerson) -> Void
    private var top: [ShutoutEvent] { events.filter(\.top) }
    private var pitchers: [ShutoutPerson] {
        var seen = Set<Int>()
        return top.map(\.pitcher).filter { seen.insert($0.id).inserted }
    }
    private var marks: [(Int, Bool)] {
        top.flatMap { event in (0..<event.outs).map { (event.pitcher.id, $0 < event.strikeouts) } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased()).font(.system(size: 10, weight: .black, design: .monospaced))
                Spacer()
                Text("\(marks.count)/27 OUTS").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(ShutoutStyle.blue)
            }
            HStack(spacing: 3) {
                ForEach(0..<27, id: \.self) { out in
                    let filled = out < marks.count
                    let pitcherIndex = filled ? pitchers.firstIndex(where: { $0.id == marks[out].0 }) ?? 0 : 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(filled ? ShutoutStyle.pitcherColors[pitcherIndex % 4] : ShutoutStyle.cream.opacity(0.08))
                        .overlay { if filled && marks[out].1 { Text("K").font(.system(size: 7, weight: .black)).foregroundStyle(ShutoutStyle.navy) } }
                        .frame(height: 18)
                }
            }.accessibilityLabel("\(marks.count) outs recorded, \(top.reduce(0) { $0 + $1.strikeouts }) strikeouts")
            ForEach(Array(pitchers.enumerated()).filter { !activeOnly || $0.offset == pitchers.count - 1 }, id: \.element.id) { index, pitcher in
                let work = top.filter { $0.pitcher.id == pitcher.id }
                let outs = work.reduce(0) { $0 + $1.outs }
                Button { select(pitcher) } label: {
                    HStack {
                        Circle().fill(ShutoutStyle.pitcherColors[index % 4]).frame(width: 6, height: 6)
                        Text(pitcher.name).font(.system(size: compact ? 11 : 13, weight: .semibold))
                        Spacer()
                        Text("\(outs / 3).\(outs % 3) IP  \(work.reduce(0) { $0 + $1.strikeouts }) K  \(work.reduce(0) { $0 + $1.hits }) H  \(work.reduce(0) { $0 + $1.walks }) BB")
                            .font(.system(size: compact ? 9 : 10, design: .monospaced))
                    }.frame(minHeight: compact && !activeOnly ? 28 : 44)
                }.buttonStyle(.plain)
            }
            if compact, let last = top.last, last.hits > 0 || last.walks > 0, last.outs < 3 {
                Text("\(last.hits > 0 ? "HIT ALLOWED" : "WALK") · THE ZERO IS STILL INTACT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.orange)
            }
        }.foregroundStyle(ShutoutStyle.cream)
    }
}

// Bars use RBI and rank; the background lines use team runs and inning progression.
// Stable player IDs and explicit positions preserve identity as ranks change.
private struct RBIRaceChart: View {
    let games: [ShutoutGame]
    let cursors: [Int]
    let progress: Double
    let credits: [HitterCredit]
    let maximum: Int
    let activePlayer: Int?
    let reduceMotion: Bool
    let lineDuration: Double
    let select: (ShutoutPerson) -> Void
    private var leaders: [HitterCredit] { Array(credits.filter { $0.rbi > 0 }.prefix(6)) }
    private var revision: [Int] { leaders.flatMap { [$0.id, $0.rbi] } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("RUN DIFFERENTIAL", systemImage: "waveform.path")
                    .foregroundStyle(ShutoutStyle.blue)
                Spacer()
                Text("TOP 6 · TOTAL RBI").foregroundStyle(ShutoutStyle.gold)
            }.font(.system(size: 9, weight: .bold, design: .monospaced))
            GeometryReader { proxy in
                let left: CGFloat = 26
                let plotWidth = max(1, proxy.size.width - left - 10)
                let slot = plotWidth / 6
                let baseline: CGFloat = 187
                ZStack(alignment: .topLeading) {
                    ContributionGraph(games: games, cursors: cursors, progress: progress, featured: nil,
                                      lineColors: [ShutoutStyle.blue, .white], showInnings: false)
                        .frame(height: 214)
                        .animation(reduceMotion ? nil : .linear(duration: lineDuration), value: progress)
                    ForEach(leaders) { hitter in
                        let rank = leaders.firstIndex { $0.id == hitter.id } ?? 0
                        let height = max(4, 142 * CGFloat(hitter.rbi) / CGFloat(maximum))
                        let active = activePlayer == hitter.id
                        Button { select(hitter.person) } label: {
                            VStack(spacing: 4) {
                                Text(String(hitter.rbi))
                                    .font(.system(size: 21, weight: .black, design: .rounded))
                                    .foregroundStyle(active ? .white : ShutoutStyle.gold)
                                    .frame(height: 25)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(ShutoutStyle.gold.opacity(active ? 0.88 : 0.5))
                                    .overlay(alignment: .top) {
                                        RoundedRectangle(cornerRadius: 2).fill(active ? .white : ShutoutStyle.gold).frame(height: 3)
                                    }
                                    .frame(height: height)
                                    .shadow(color: ShutoutStyle.gold.opacity(active ? 0.65 : 0), radius: 9)
                                Text(hitter.person.surname)
                                    .font(.system(size: 10, weight: .bold))
                                    .lineLimit(2).minimumScaleFactor(0.75)
                                    .frame(height: 30, alignment: .top)
                                    .foregroundStyle(ShutoutStyle.cream)
                                Text(rank == 0 ? "LEADER" : "#\(rank + 1)")
                                    .font(.system(size: 7, weight: .black, design: .monospaced))
                                    .foregroundStyle(rank == 0 ? ShutoutStyle.gold : ShutoutStyle.cream.opacity(0.5))
                                    .frame(height: 10)
                            }
                            .frame(width: max(1, slot - 6))
                        }
                        .buttonStyle(.plain)
                        .position(x: left + slot * (CGFloat(rank) + 0.5), y: baseline - height / 2 + 9.5)
                        .transition(.opacity)
                        .accessibilityLabel("Rank \(rank + 1), \(hitter.person.name), \(hitter.rbi) RBI. Tap for player moments.")
                    }
                    if leaders.isEmpty {
                        Text("WHO TAKES THE LEAD?")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(ShutoutStyle.gold.opacity(0.8))
                            .frame(width: plotWidth, height: 120).offset(x: left, y: 25)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.75), value: revision)
            }.frame(height: 242)
            Text(games.count == 1 ? "Line: this game · Bars: cumulative RBI across both games" : "Lines: Seattle (blue), Cincinnati (white) · Bars: both games")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(ShutoutStyle.cream.opacity(0.6))
            Text("Seattle RBI carry into Cincinnati · Ties alphabetical")
                .font(.system(size: 9)).foregroundStyle(ShutoutStyle.cream.opacity(0.5))
        }
    }
}

private struct ContributionGraph: View, Animatable {
    let games: [ShutoutGame]
    let cursors: [Int]
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    let featured: Int?
    var lineColors: [Color] = [ShutoutStyle.gold, ShutoutStyle.blue]
    var showInnings = true
    var body: some View {
        Canvas { context, size in
            let left: CGFloat = 24, right = size.width - 24, bottom = size.height - 27
            func point(_ position: Double, _ score: Int) -> CGPoint {
                CGPoint(x: left + (right - left) * position / 9, y: bottom - (bottom - 22) * Double(score) / 24)
            }
            for run in [0, 10, 20] {
                let y = point(0, run).y
                var grid = Path(); grid.move(to: CGPoint(x: left, y: y)); grid.addLine(to: CGPoint(x: right, y: y))
                context.stroke(grid, with: .color(ShutoutStyle.cream.opacity(run == 0 ? 0.65 : 0.12)), style: StrokeStyle(lineWidth: 1, dash: run == 0 ? [3, 3] : []))
                context.draw(Text(String(run)).font(.system(size: 9, design: .monospaced)).foregroundColor(ShutoutStyle.cream.opacity(0.6)), at: CGPoint(x: left - 8, y: y), anchor: .trailing)
            }
            for inning in (showInnings ? Array(1...9) : []) {
                context.draw(Text(String(inning)).font(.system(size: 9, design: .monospaced)).foregroundColor(ShutoutStyle.cream.opacity(0.6)), at: CGPoint(x: point(Double(inning), 0).x, y: bottom + 13))
            }
            for (index, game) in games.enumerated() {
                let color = lineColors[index % lineColors.count]
                let completed = games.count == 1 ? min(game.events.count, max(0, Int(progress))) : cursors[index] + 1
                let seen = Array(game.events.prefix(completed))
                var line = Path(); line.move(to: point(0, 0))
                var tip = point(0, 0)
                // Fixed, monotone cubic segments pass through every actual score.
                // De Casteljau reveals the current segment without moving earlier geometry.
                func mix(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
                    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                }
                func appendSegment(to end: CGPoint, fraction: Double = 1) {
                    let midX = (tip.x + end.x) / 2
                    let c1 = CGPoint(x: midX, y: tip.y)
                    let c2 = CGPoint(x: midX, y: end.y)
                    let t = min(1, max(0, fraction))
                    let a = mix(tip, c1, t), b = mix(c1, c2, t), c = mix(c2, end, t)
                    let d = mix(a, b, t), e = mix(b, c, t)
                    let endpoint = mix(d, e, t)
                    line.addCurve(to: endpoint, control1: a, control2: d)
                    tip = endpoint
                }
                for event in seen { appendSegment(to: point(event.position, event.total)) }
                if games.count == 1 && completed < game.events.count {
                    let next = game.events[completed]
                    appendSegment(to: point(next.position, next.total), fraction: progress - Double(completed))
                }
                context.stroke(line, with: .color(color.opacity(0.1)), style: StrokeStyle(lineWidth: 8, lineJoin: .round))
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                for event in seen where event.runs > 0 {
                    let p = point(event.position, event.total)
                    let radius: CGFloat = event.id == featured ? 5 : 2
                    context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
                }
                if !seen.isEmpty || progress > 0 {
                    context.fill(Path(ellipseIn: CGRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6)), with: .color(color))
                }
            }
            if showInnings {
                context.draw(Text("OPPONENTS 0").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(ShutoutStyle.cream), at: CGPoint(x: right, y: bottom - 9), anchor: .bottomTrailing)
            }
        }.accessibilityHidden(true)
    }
}

private struct ContributionPoster: View {
    let games: [ShutoutGame]
    var body: some View {
        let credits = hitterCredits(games.flatMap(\.events))
        VStack(alignment: .leading, spacing: 20) {
            Text("MILWAUKEE / 2026").font(.system(size: 14, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(ShutoutStyle.gold)
            Text("WHO BUILT\nTHE 42?").font(.system(size: 65, weight: .black, design: .rounded)).tracking(-2).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                Text("42–0").font(.system(size: 62, weight: .black, design: .rounded)).foregroundStyle(ShutoutStyle.gold)
                Spacer()
                Text("22–0 vs. Seattle · Aug 18\n20–0 vs. Cincinnati · Sep 11").font(.system(size: 14, weight: .semibold))
            }
            Text("THE BATS BUILT THE LEAD").font(.system(size: 12, weight: .black, design: .monospaced))
            ForEach(Array(credits.prefix(4))) { hitter in HitterBar(hitter: hitter, maximum: credits.first?.rbi ?? 1) }
            Text("\(credits.reduce(0) { $0 + $1.rbi }) RBI + \(42 - credits.reduce(0) { $0 + $1.rbi }) runs without an RBI. R and H shown separately.")
                .font(.system(size: 11)).foregroundStyle(ShutoutStyle.cream.opacity(0.7))
            Text("THE ARMS KEPT THE ZERO").font(.system(size: 12, weight: .black, design: .monospaced)).foregroundStyle(ShutoutStyle.blue)
            ForEach(games) { game in PitchingStrip(events: game.events, title: "vs. \(game.opponent)", compact: true, select: { _ in }) }
            Spacer(minLength: 0)
            Text("HUB BALL · BASEBALL. WORTH FEELING.").font(.system(size: 12, weight: .black)).tracking(2).foregroundStyle(ShutoutStyle.gold)
        }.padding(36).foregroundStyle(ShutoutStyle.cream).background(ShutoutStyle.navy)
    }
}

struct BrewersShutoutStoryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MILWAUKEE / 2026").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(ShutoutStyle.gold)
            HStack(alignment: .bottom) {
                Text("WHO BUILT\nTHE 42?").font(.system(size: 36, weight: .black, design: .rounded)).tracking(-1)
                Spacer()
                Image(systemName: "chart.xyaxis.line").font(.system(size: 44)).foregroundStyle(ShutoutStyle.blue)
            }
            Text("The bats built the lead.\nThe arms kept the zero.").font(.system(size: 16, weight: .medium))
            HStack {
                Text("MEET THE RUN PRODUCERS").tracking(1)
                Spacer()
                Image(systemName: "play.fill")
            }.font(.system(size: 11, weight: .bold)).foregroundStyle(ShutoutStyle.gold)
        }.padding(24).foregroundStyle(ShutoutStyle.cream).background(ShutoutStyle.navy, in: RoundedRectangle(cornerRadius: 12))
    }
}
