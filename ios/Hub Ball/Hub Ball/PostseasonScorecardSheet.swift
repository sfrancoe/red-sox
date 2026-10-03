import SwiftUI

struct PostseasonScorecardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: PostseasonScorecardStore
    private let game: PostseasonGame

    init(game: PostseasonGame) {
        self.game = game
        _store = State(initialValue: PostseasonScorecardStore(game: game))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let scorecard = store.snapshot {
                        scorecardHeader(scorecard)
                        if store.refreshFailed {
                            Text("Updates interrupted. Showing the last loaded scorecard.")
                                .foregroundStyle(AppColor.amber)
                            retryButton
                        }
                        lineScore(scorecard)
                        if scorecard.isLive {
                            currentMatchup(scorecard.liveMatchup)
                        }
                        teamBoxScore(scorecard.away)
                        teamBoxScore(scorecard.home)
                    } else if store.refreshFailed {
                        ContentUnavailableView {
                            Label("Scorecard unavailable", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text("The game’s scorecard could not be loaded.")
                        } actions: {
                            retryButton
                        }
                    } else {
                        ProgressView("Loading scorecard…")
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(AppColor.bone)
                .padding(16)
            }
            .background(AppColor.night)
            .navigationTitle("Game Scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await store.refresh() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await store.refresh()
                while !Task.isCancelled, scenePhase == .active {
                    if let snapshot = store.snapshot, !snapshot.isLive { break }
                    do { try await Task.sleep(for: .seconds(30)) }
                    catch { break }
                    guard !Task.isCancelled, scenePhase == .active else { break }
                    await store.refresh()
                }
            }
        }
        .tint(AppColor.amber)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("postseason.scorecard")
    }

    private var retryButton: some View {
        Button("Retry") { Task { await store.refresh() } }
            .disabled(store.isLoading)
    }

    private func scorecardHeader(_ scorecard: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(scorecard.away.name) at \(scorecard.home.name)")
                .font(.headline)
            HStack {
                if scorecard.isLive, !store.refreshFailed {
                    LiveGameIndicator()
                }
                Text(scorecard.liveStatus ?? scorecard.gameState ?? game.status)
                    .font(.subheadline.weight(.semibold))
            }
            Text(scorecard.venue).foregroundStyle(AppColor.boneMuted)
            if let checkedAt = store.checkedAt {
                Text("Updated \(checkedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(AppColor.boneMuted)
            }
        }
    }

    private func lineScore(_ scorecard: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Line Score").font(.headline)
            ScrollView(.horizontal) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        tableCell("Team", width: 72, leading: true, header: true)
                        ForEach(scorecard.innings) { inning in
                            tableCell(String(inning.num), header: true)
                        }
                        ForEach(["R", "H", "E", "LOB"], id: \.self) { tableCell($0, header: true) }
                    }
                    ForEach([scorecard.away, scorecard.home], id: \.side) { team in
                        GridRow {
                            tableCell(team.abbreviation, width: 72, leading: true)
                            ForEach(scorecard.innings) { inning in
                                let runs = team.side == "away" ? inning.away.runs : inning.home.runs
                                tableCell(runs.map(String.init) ?? "–")
                                    .accessibilityLabel("\(team.abbreviation), inning \(inning.num): \(runs.map { "\($0) runs" } ?? "not played")")
                            }
                            tableCell(String(team.runs), header: true)
                            tableCell(String(team.hits))
                            tableCell(String(team.errors))
                            tableCell(String(team.leftOnBase))
                        }
                    }
                }
            }
            Text("R: Runs · H: Hits · E: Errors · LOB: Left on base\n–: Inning not played. Swipe tables to see all columns.")
                .font(.caption).foregroundStyle(AppColor.boneMuted)
        }
        .accessibilityIdentifier("postseason.scorecard.linescore")
    }

    private func currentMatchup(_ matchup: LiveGameMatchup?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Current pitcher").font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.boneMuted)
                Text(matchup?.pitcher ?? "Not available")
                    .accessibilityIdentifier("postseason.scorecard.currentPitcher")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Current batter").font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.boneMuted)
                Text(matchup?.batter ?? "Not available")
                    .accessibilityIdentifier("postseason.scorecard.currentBatter")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColor.nightRaised, in: RoundedRectangle(cornerRadius: 8))
    }

    private func teamBoxScore(_ team: TeamBoxScore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(team.name).font(.title3.weight(.bold))
            Text("Batting").font(.headline)
            statsTable(headers: ["AB", "R", "H", "RBI", "BB", "SO", "HR", "SB", "LOB"],
                       rows: team.batting.map { batter in
                ScorecardRow(id: batter.id,
                             name: batter.name + "  " + batter.position,
                             note: batter.note,
                             values: [batter.atBats, batter.runs, batter.hits, batter.rbi,
                                      batter.baseOnBalls, batter.strikeOuts, batter.homeRuns]
                                .map(String.init) + [batter.stolenBases.map(String.init) ?? "–", String(batter.leftOnBase)])
            })
            Text("Pitching").font(.headline)
            statsTable(headers: ["IP", "H", "R", "ER", "BB", "SO", "HR", "P"],
                       rows: team.pitching.map { pitcher in
                ScorecardRow(id: pitcher.id, name: pitcher.name, note: pitcher.note,
                             values: [pitcher.inningsPitched] + [pitcher.hits, pitcher.runs,
                                 pitcher.earnedRuns, pitcher.baseOnBalls, pitcher.strikeOuts,
                                 pitcher.homeRuns, pitcher.numberOfPitches].map(String.init))
            })
        }
        .accessibilityIdentifier("postseason.scorecard.\(team.side)")
    }

    private func statsTable(headers: [String], rows: [ScorecardRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty {
                Text("Player statistics aren’t available yet.").foregroundStyle(AppColor.boneMuted)
            } else {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            tableCell("Player", width: 210, leading: true, header: true)
                            ForEach(headers, id: \.self) { tableCell($0, header: true) }
                        }
                        ForEach(rows) { row in
                            GridRow {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name)
                                    if !row.note.isEmpty {
                                        Text(row.note).font(.caption).foregroundStyle(AppColor.boneMuted)
                                    }
                                }
                                .frame(width: 194, alignment: .leading).padding(8)
                                ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                                    tableCell(value)
                                        .accessibilityLabel("\(row.name), \(headers[index]): \(value)")
                                }
                            }
                            .background(AppColor.nightRaised)
                        }
                    }
                }
            }
        }
    }

    private func tableCell(_ text: String, width: CGFloat = 44,
                           leading: Bool = false, header: Bool = false) -> some View {
        Text(text)
            .font(header ? .subheadline.weight(.bold) : .subheadline)
            .monospacedDigit()
            .frame(width: width, alignment: leading ? .leading : .center)
            .padding(.vertical, 10)
            .background(header ? AppColor.rule : AppColor.nightRaised)
    }
}

private struct ScorecardRow: Identifiable {
    let id: String
    let name: String
    let note: String
    let values: [String]
}
