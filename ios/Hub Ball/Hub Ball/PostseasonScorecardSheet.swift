import SwiftUI

struct PostseasonScorecardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: PostseasonScorecardStore
    private let game: PostseasonGame
    @ScaledMetric(relativeTo: .caption) private var scoreRowHeight: CGFloat = 28

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
        HStack {
            if scorecard.isLive, !store.refreshFailed {
                LiveGameIndicator()
            }
            Text(scorecard.liveStatus ?? scorecard.gameState ?? game.status)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func lineScore(_ scorecard: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let teamWidth: CGFloat = geometry.size.width >= 600 ? 68 : 44
                let cellWidth = max(18, (geometry.size.width - 16 - teamWidth) / 13)
                let inningsWidth = max(0, geometry.size.width - 16 - teamWidth - cellWidth * 4)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        scoreCell("", width: teamWidth)
                        scoreCell(scorecard.away.abbreviation, width: teamWidth, team: true)
                        scoreCell(scorecard.home.abbreviation, width: teamWidth, team: true)
                    }
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 0) {
                            ForEach(scorecard.innings) { inning in
                                VStack(spacing: 0) {
                                    scoreCell(String(inning.num), width: cellWidth, header: true)
                                    scoreCell(inning.away.runs.map(String.init) ?? "–", width: cellWidth)
                                        .accessibilityLabel("\(scorecard.away.abbreviation), inning \(inning.num): \(inning.away.runs.map { "\($0) runs" } ?? "not played")")
                                    scoreCell(inning.home.runs.map(String.init) ?? "–", width: cellWidth)
                                        .accessibilityLabel("\(scorecard.home.abbreviation), inning \(inning.num): \(inning.home.runs.map { "\($0) runs" } ?? "not played")")
                                }
                            }
                        }
                    }
                    .frame(width: inningsWidth)
                    scoreTotal("R", away: scorecard.away.runs, home: scorecard.home.runs,
                               scorecard: scorecard, width: cellWidth, highlightsLeader: true)
                    scoreTotal("H", away: scorecard.away.hits, home: scorecard.home.hits,
                               scorecard: scorecard, width: cellWidth)
                    scoreTotal("E", away: scorecard.away.errors, home: scorecard.home.errors,
                               scorecard: scorecard, width: cellWidth)
                    scoreTotal("LOB", away: scorecard.away.leftOnBase, home: scorecard.home.leftOnBase,
                               scorecard: scorecard, width: cellWidth)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .background(AppColor.nightRaised)
                .overlay(Rectangle().strokeBorder(AppColor.rule, lineWidth: 1))
            }
            .frame(height: scoreRowHeight * 3 + 20)
            if scorecard.isLive {
                currentMatchup(scorecard.liveMatchup)
            }
        }
        .accessibilityIdentifier("postseason.scorecard.linescore")
    }

    private func scoreCell(_ value: String, width: CGFloat, header: Bool = false,
                           team: Bool = false, emphasized: Bool = false) -> some View {
        Text(value)
            .font(.system(size: emphasized ? 15 : (header ? 10 : 12),
                          weight: team || header || emphasized ? .bold : .semibold))
            .monospacedDigit()
            .foregroundStyle(emphasized ? AppColor.amber : AppColor.bone)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: width, height: scoreRowHeight, alignment: team ? .leading : .center)
    }

    private func scoreTotal(_ title: String, away: Int, home: Int, scorecard: RecentGame,
                            width: CGFloat, highlightsLeader: Bool = false) -> some View {
        VStack(spacing: 0) {
            scoreCell(title, width: width, header: true)
            scoreCell(String(away), width: width, emphasized: highlightsLeader && away > home)
                .accessibilityLabel("\(scorecard.away.abbreviation), \(title): \(away)")
            scoreCell(String(home), width: width, emphasized: highlightsLeader && home > away)
                .accessibilityLabel("\(scorecard.home.abbreviation), \(title): \(home)")
        }
    }

    private func currentMatchup(_ matchup: LiveGameMatchup?) -> some View {
        Text(matchup?.compactDescription.replacingOccurrences(of: "  (AB)", with: " , (AB)")
             ?? "(P) — , (AB) —  —, — Outs")
            .font(AppFont.bodySmall)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(matchup?.accessibilityDescription ?? "Current matchup unavailable")
            .accessibilityIdentifier("postseason.scorecard.currentMatchup")
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
