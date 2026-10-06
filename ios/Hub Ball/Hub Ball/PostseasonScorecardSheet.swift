import SwiftUI

struct PostseasonScorecardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var model
    private var store: PostseasonScorecardStore { model.scorecard(for: game) }
    @State private var selectedTeamSide = "away"
    @State private var selectedPlayer: ScorecardPlayerSelection?
    private let game: PostseasonGame
    @ScaledMetric(relativeTo: .caption) private var scoreRowHeight: CGFloat = 28

    init(game: PostseasonGame) {
        self.game = game
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let scorecard = store.snapshot {
                        if store.refreshFailed {
                            Text("Updates interrupted. Showing the last loaded scorecard.")
                                .foregroundStyle(AppColor.amber)
                            retryButton
                        }
                        lineScore(scorecard)
                        gameSummary(scorecard)
                        Picker("Box score team", selection: $selectedTeamSide) {
                            Text(scorecard.away.abbreviation).tag("away")
                            Text(scorecard.home.abbreviation).tag("home")
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("postseason.scorecard.teamTabs")
                        teamBoxScore(selectedTeamSide == "away" ? scorecard.away : scorecard.home)
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
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 12) {
                    if let scorecard = store.snapshot {
                        scorecardHeader(scorecard)
                            .foregroundStyle(AppColor.bone)
                    }
                    Spacer(minLength: 0)
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColor.amber)
                        .font(.body)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(AppColor.nightRaised, in: Capsule())
                        .overlay { Capsule().stroke(AppColor.rule, lineWidth: 1) }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColor.night)
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
        .sheet(item: $selectedPlayer) { selection in
            if let team = HubTeam.allCases.first(where: { $0.mlbID == selection.teamID }) {
                PostseasonPlayerCardSheet(team: team, playerID: selection.playerID)
            }
        }
        .tint(AppColor.amber)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("postseason.scorecard")
        .modifier(ScorecardPresentationSizing())
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

    private func gameSummary(_ scorecard: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scorecard.isLive ? "Game So Far" : "Game Summary")
                .font(.headline)
            Text(scorecard.summary)
                .font(AppFont.bodySmall)
                .lineSpacing(2)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColor.nightRaised, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("postseason.scorecard.summary")
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
            Text("Batting").font(.headline)
            statsTable(headers: ["AB", "R", "H", "RBI"], teamID: team.id,
                       rows: team.batting.map { batter in
                ScorecardRow(id: batter.id, playerID: batter.mlbId, name: batter.name,
                             position: batter.position,
                             values: [batter.atBats, batter.runs, batter.hits, batter.rbi].map(String.init))
            }, fitsScreen: true)
            Text("Pitching").font(.headline)
            statsTable(headers: ["IP", "H", "R", "ER", "BB", "SO", "HR", "P"], teamID: team.id,
                       rows: team.pitching.map { pitcher in
                ScorecardRow(id: pitcher.id, playerID: pitcher.mlbId, name: pitcher.name,
                             position: pitcher.note,
                             values: [pitcher.inningsPitched] + [pitcher.hits, pitcher.runs,
                                 pitcher.earnedRuns, pitcher.baseOnBalls, pitcher.strikeOuts,
                                 pitcher.homeRuns, pitcher.numberOfPitches].map(String.init))
            }, fitsScreen: false)
        }
        .accessibilityIdentifier("postseason.scorecard.\(team.side)")
    }

    private func statsTable(headers: [String], teamID: Int, rows: [ScorecardRow], fitsScreen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text("Player statistics aren’t available yet.").foregroundStyle(AppColor.boneMuted)
            } else {
                GeometryReader { geometry in
                    let statWidth: CGFloat = fitsScreen ? max(28, min(38, geometry.size.width * 0.09)) : 36
                    let nameWidth = fitsScreen ? max(0, geometry.size.width - statWidth * CGFloat(headers.count) - 16) : 190
                    if fitsScreen {
                        compactStatsRows(headers: headers, rows: rows, teamID: teamID,
                                         nameWidth: nameWidth, statWidth: statWidth)
                    } else {
                        ScrollView(.horizontal) {
                            compactStatsRows(headers: headers, rows: rows, teamID: teamID,
                                             nameWidth: nameWidth, statWidth: statWidth)
                        }
                    }
                }
                .frame(height: CGFloat(rows.count + 1) * boxScoreRowHeight)
            }
        }
    }

    @ScaledMetric(relativeTo: .subheadline) private var boxScoreRowHeight: CGFloat = 30

    private func compactStatsRows(headers: [String], rows: [ScorecardRow], teamID: Int,
                                  nameWidth: CGFloat, statWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Player").frame(width: nameWidth, alignment: .leading)
                ForEach(headers, id: \.self) { header in
                    Text(header).frame(width: statWidth)
                }
            }
            .font(AppFont.label.weight(.bold))
            .padding(.horizontal, 8)
            .frame(height: boxScoreRowHeight)
            .background(AppColor.rule)
            ForEach(rows) { row in
                HStack(spacing: 0) {
                    Button {
                        if let playerID = row.playerID {
                            selectedPlayer = ScorecardPlayerSelection(playerID: playerID, teamID: teamID)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(row.name)
                                .font(AppFont.bodySmall.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .layoutPriority(1)
                            if !row.position.isEmpty {
                                Text(row.position).font(AppFont.label)
                                    .foregroundStyle(AppColor.boneMuted)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: nameWidth, height: boxScoreRowHeight, alignment: .leading)
                        .contentShape(Rectangle())
                        .foregroundStyle(AppColor.bone)
                    }
                    .buttonStyle(.plain)
                    .disabled(row.playerID == nil)
                    .accessibilityLabel(row.name)
                    .accessibilityHint("Opens player card")
                    .accessibilityIdentifier("postseason.scorecard.player.\(teamID).\(row.playerID ?? 0)")
                    ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                        Text(value)
                            .font(AppFont.bodySmall)
                            .monospacedDigit()
                            .frame(width: statWidth, height: boxScoreRowHeight)
                            .accessibilityLabel("\(row.name), \(headers[index]): \(value)")
                    }
                }
                .padding(.horizontal, 8)
                .background(AppColor.nightRaised)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppColor.rule).frame(height: 0.5)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ScorecardRow: Identifiable {
    let id: String
    let playerID: Int?
    let name: String
    let position: String
    let values: [String]
}

private struct ScorecardPlayerSelection: Identifiable {
    let playerID: Int
    let teamID: Int
    var id: String { "\(teamID)-\(playerID)" }
}

private struct ScorecardPresentationSizing: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            content.presentationSizing(ScorecardPageSizing())
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
private struct ScorecardPageSizing: PresentationSizing {
    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        let page = PagePresentationSizing.page.proposedSize(for: root, context: context)
        return ProposedViewSize(width: min(page.width ?? 640, 640), height: page.height)
    }
}
