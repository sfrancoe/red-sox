import SwiftUI

private enum BoxScoreTeamSelection {
    case favorite
    case opponent
}

struct RecentGameView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var store: RecentGameStore
    @State private var selectedStatsTeam: BoxScoreTeamSelection = .favorite
    @State private var selectedGameID: Int?
    private let statColumnSpacing: CGFloat = 6
    let team: HubTeam
    let onSelectPlayer: (Int) -> Void

    init(team: HubTeam = .boston, onSelectPlayer: @escaping (Int) -> Void = { _ in }) {
        self.team = team
        self.onSelectPlayer = onSelectPlayer
        _store = State(initialValue: RecentGameStore(team: team))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                Group {
                    if let game = selectedGame {
                        VStack(spacing: 0) {
                            gameSelector
                            gameContent(game)
                        }
                    } else if store.isLoading {
                        ProgressView("Loading Game Recaps…")
                            .tint(AppColor.ink)
                            .foregroundStyle(AppColor.ink)
                    } else {
                        errorView
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.load()
            synchronizeSelection()

            while !Task.isCancelled {
                let delay: UInt64 = store.hasLiveGame ? 20 : 60
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                guard !Task.isCancelled else { return }
                let hadLiveGame = store.hasLiveGame
                await store.refresh()
                synchronizeSelection(preferNewLiveGame: !hadLiveGame && store.hasLiveGame)
            }
        }
    }

    private var usesExpandedReadingLayout: Bool {
        dynamicTypeSize.usesExpandedReadingLayout
    }

    private var selectedGame: RecentGame? {
        if let selectedGameID,
           let game = store.games.first(where: { $0.gamePk == selectedGameID }) {
            return game
        }
        return store.games.first
    }

    @ViewBuilder
    private var gameSelector: some View {
        if usesExpandedReadingLayout {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Menu {
                    ForEach(store.games, id: \.gamePk) { game in
                        Button {
                            selectedGameID = game.gamePk
                            selectedStatsTeam = .favorite
                        } label: {
                            if selectedGame?.gamePk == game.gamePk {
                                Label(gameTabAccessibilityLabel(game, at: context.date), systemImage: "checkmark")
                            } else {
                                Text(gameTabAccessibilityLabel(game, at: context.date))
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedGame.map { gameTabTitle($0, at: context.date) } ?? "Choose a game")
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Game")
                .accessibilityValue(selectedGame.map { gameTabAccessibilityLabel($0, at: context.date) } ?? "No game selected")
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        } else {
            compactGameSelector
        }
    }

    private var compactGameSelector: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 0) {
                ForEach(store.games, id: \.gamePk) { game in
                    Button {
                        selectedGameID = game.gamePk
                        selectedStatsTeam = .favorite
                    } label: {
                        VStack(spacing: 3) {
                            gameTabLabel(game, at: context.date)
                            gameScoreLabel(game, at: context.date)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(selectedGameID == game.gamePk ? AppColor.ink : AppColor.inkMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(gameTabAccessibilityLabel(game, at: context.date))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .background(AppColor.paleRed)
        }
    }

    private func gameTabLabel(_ game: RecentGame, at date: Date) -> some View {
        Text(gameTabTitle(game, at: date))
            .font(
                .system(
                    size: selectedGame?.gamePk == game.gamePk ? 16 : 13,
                    weight: selectedGame?.gamePk == game.gamePk ? .black : .semibold
                )
            )
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private func gameScoreLabel(_ game: RecentGame, at date: Date) -> some View {
        let favorite = game.away.id == team.mlbID ? game.away : game.home
        let opponent = game.away.id == team.mlbID ? game.home : game.away
        let result = game.result.lowercased()
        let state = store.presentationState(for: game, at: date)
        let textColor: Color
        switch state {
        case .live:
            textColor = AppColor.hunterGreen
        case .interruptedLive:
            textColor = AppColor.red
        case .savedLive, .delayedLive:
            textColor = AppColor.inkMuted
        case .final:
            textColor = result == "win" ? AppColor.resultWinText : AppColor.resultLossText
        }
        let prefix = game.isLive ? "" : result == "win" ? "W " : "L "

        return Text("\(prefix)\(favorite.runs)–\(opponent.runs)")
            .font(
                .system(
                    size: selectedGame?.gamePk == game.gamePk ? 14 : 12,
                    weight: .black
                )
            )
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(textColor)
    }

    private func gameTabAccessibilityLabel(_ game: RecentGame, at date: Date) -> String {
        let favorite = game.away.id == team.mlbID ? game.away : game.home
        let opponent = game.away.id == team.mlbID ? game.home : game.away
        let state = store.presentationState(for: game, at: date)
        let status = state == .final ? game.result : state.accessibilityLabel
        return "\(gameTabTitle(game, at: date)), \(status), \(favorite.abbreviation) \(favorite.runs), \(opponent.abbreviation) \(opponent.runs)"
    }

    private func gameTabTitle(_ game: RecentGame, at date: Date) -> String {
        let state = store.presentationState(for: game, at: date)
        switch state {
        case .live:
            return "Live"
        case .savedLive:
            return "Saved score"
        case .interruptedLive:
            return "Updates interrupted"
        case .delayedLive:
            return "Updates delayed"
        case .final:
            break
        }

        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: game.gameDate) else { return game.formattedDate }
        var title = BaseballTime.format(date, .dateTime.month(.abbreviated).day())
        let gamesOnDate = store.games
            .filter { candidate in
                guard let candidateDate = formatter.date(from: candidate.gameDate) else { return false }
                return BaseballTime.calendar.isDate(candidateDate, inSameDayAs: date)
            }
            .sorted { $0.gameDate < $1.gameDate }
        if gamesOnDate.count > 1,
           let gameNumber = gamesOnDate.firstIndex(where: { $0.gamePk == game.gamePk }) {
            title += " G\(gameNumber + 1)"
        }
        return title
    }

    private func synchronizeSelection(preferNewLiveGame: Bool = false) {
        let currentStillExists = store.games.contains { $0.gamePk == selectedGameID }
        if preferNewLiveGame || !currentStillExists {
            selectedGameID = store.games.first?.gamePk
            selectedStatsTeam = .favorite
        }
    }

    private func gameContent(_ game: RecentGame) -> some View {
        let favorite = game.away.id == team.mlbID ? game.away : game.home
        let opponent = game.away.id == team.mlbID ? game.home : game.away

        return ScrollView {
            LazyVStack(spacing: 10) {
                freshnessBanner(game)
                scoreCard(game)

                if contentWidth >= 720 && !usesExpandedReadingLayout {
                    VStack(spacing: 0) {
                        recapCard(game)
                        reportDivider
                        HStack(alignment: .top, spacing: 0) {
                            battingCard(favorite: favorite, opponent: opponent)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            pitchingCard(favorite: favorite, opponent: opponent)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        reportDivider
                        scoringPlaysCard(game)
                        reportDivider
                        linksCard(game)
                    }
                    .cardStyle(padding: 0)
                } else {
                    VStack(spacing: 0) {
                        recapCard(game)
                        reportDivider
                        if usesExpandedReadingLayout {
                            expandedBattingCard(favorite: favorite, opponent: opponent)
                        } else {
                            battingCard(favorite: favorite, opponent: opponent)
                        }
                        reportDivider
                        if usesExpandedReadingLayout {
                            expandedPitchingCard(favorite: favorite, opponent: opponent)
                        } else {
                            pitchingCard(favorite: favorite, opponent: opponent)
                        }
                        reportDivider
                        scoringPlaysCard(game)
                        reportDivider
                        linksCard(game)
                    }
                    .overlay(alignment: .top) {
                        Rectangle().fill(AppColor.rule).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 18)
            .foregroundStyle(AppColor.ink)
        }
        .refreshable {
            let hadLiveGame = store.hasLiveGame
            await store.refresh()
            synchronizeSelection(preferNewLiveGame: !hadLiveGame && store.hasLiveGame)
        }
    }

    private var reportDivider: some View {
        Divider()
            .overlay(AppColor.border)
            .padding(.horizontal, 16)
    }

    private func scoreCard(_ game: RecentGame) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let state = store.presentationState(for: game, at: context.date)
            VStack(spacing: 9) {
                let layout = usesExpandedReadingLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
                layout {
                    Text(game.formattedDate)
                        .font(.title3.weight(.black))

                    Spacer()

                    gameStatusIndicator(state)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(game.gameDetails(watchSummary: store.watchSummary(for: game)))
                        .font(.subheadline)
                        .foregroundStyle(AppColor.bone.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)

                    if game.isLive, let liveStatus = game.liveStatus {
                        Text(state == .live ? liveStatus : "\(state.label) · \(liveStatus)")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(state == .live ? AppColor.hunterGreen : AppColor.inkMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                combinedLineScore(game)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .overlay {
                        Rectangle()
                            .stroke(AppColor.border.opacity(0.65), lineWidth: 0.5)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.nightRaised)
        }
    }

    @ViewBuilder
    private func gameStatusIndicator(_ state: RecentGamePresentationState) -> some View {
        switch state {
        case .live:
            LiveGameIndicator()
        case .savedLive:
            QualifiedGameIndicator(text: "SAVED SCORE", accessibilityLabel: state.accessibilityLabel)
        case .interruptedLive:
            QualifiedGameIndicator(text: "UPDATES INTERRUPTED", accessibilityLabel: state.accessibilityLabel)
        case .delayedLive:
            QualifiedGameIndicator(text: "UPDATES DELAYED", accessibilityLabel: state.accessibilityLabel)
        case .final:
            Text("Final")
                .font(AppFont.label)
                .foregroundStyle(AppColor.inkMuted)
        }
    }

    private func freshnessBanner(_ game: RecentGame) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let message = store.freshnessMessage(for: game, at: context.date)
            let warning = store.hasRefreshWarning(for: game)
            if let message {
                let layout = usesExpandedReadingLayout ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
                layout {
                    if !usesExpandedReadingLayout {
                        Image(systemName: warning ? "exclamationmark.triangle" : "clock")
                            .font(.caption.weight(.bold))
                    }
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .lineLimit(usesExpandedReadingLayout ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if warning {
                        Button("Retry") {
                        Task { await store.retry(game: game) }
                        }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.bordered)
                        .tint(AppColor.red)
                        .accessibilityLabel("Retry Game Recaps updates")
                    }
                }
                .foregroundStyle(warning ? AppColor.red : AppColor.inkMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.paper.opacity(0.82))
                .overlay(Rectangle().stroke(warning ? AppColor.red.opacity(0.35) : AppColor.border, lineWidth: 1))
                .accessibilityElement(children: .contain)
            }
        }
    }

    @ScaledMetric(relativeTo: .body) private var readingScoreColumnWidth: CGFloat = 72

    @ViewBuilder
    private func combinedLineScore(_ game: RecentGame) -> some View {
        if usesExpandedReadingLayout {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Team").fontWeight(.bold)
                        Text(game.away.abbreviation)
                        Text(game.home.abbreviation)
                    }
                    .frame(width: readingScoreColumnWidth, alignment: .leading)
                    ForEach(game.innings) { inning in
                        readingScoreColumn(String(inning.num), spokenTitle: "Inning \(inning.num)",
                                           away: inning.away.runs.map(String.init) ?? "—",
                                           home: inning.home.runs.map(String.init) ?? "—", game: game)
                    }
                    readingScoreColumn("R", spokenTitle: "Runs", away: String(game.away.runs), home: String(game.home.runs), game: game)
                    readingScoreColumn("H", spokenTitle: "Hits", away: String(game.away.hits), home: String(game.home.hits), game: game)
                    readingScoreColumn("E", spokenTitle: "Errors", away: String(game.away.errors), home: String(game.home.errors), game: game)
                    readingScoreColumn("LOB", spokenTitle: "Left on base", away: String(game.away.leftOnBase), home: String(game.home.leftOnBase), game: game)
                }
                .font(.body.monospacedDigit())
                .fixedSize(horizontal: true, vertical: false)
            }
        } else {
            compactCombinedLineScore(game)
        }
    }

    private func readingScoreColumn(_ title: String, spokenTitle: String, away: String, home: String, game: RecentGame) -> some View {
        VStack(spacing: 12) {
            Text(title).fontWeight(.bold).accessibilityLabel(spokenTitle)
            Text(away).accessibilityLabel("\(game.away.abbreviation), \(spokenTitle), \(away == "—" ? "not recorded" : away)")
            Text(home).accessibilityLabel("\(game.home.abbreviation), \(spokenTitle), \(home == "—" ? "not recorded" : home)")
        }
        .frame(width: readingScoreColumnWidth)
        .accessibilityElement(children: .contain)
    }

    private func compactCombinedLineScore(_ game: RecentGame) -> some View {
        let teamWidth: CGFloat = contentWidth >= 650 ? 90 : 50
        // Account for the page (32), card (24), and table (16) horizontal padding.
        // Nine innings fit on SE; additional innings can scroll at readable cell widths.
        let tableWidth = max(contentWidth - 72, teamWidth + CGFloat(game.innings.count + 4) * 18)
        return ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 7) {
                HStack(spacing: 0) {
                    Text("")
                        .frame(width: contentWidth >= 650 ? 90 : 50, alignment: .leading)
                    ForEach(game.innings) { inning in
                        Text("\(inning.num)")
                            .frame(minWidth: 0, maxWidth: .infinity)
                    }
                    lineScoreLegend("R")
                    lineScoreLegend("H")
                    lineScoreLegend("E")
                    lineScoreLegend("LOB")
                }
                .font(.system(size: contentWidth >= 650 ? 12 : 9, weight: .bold))
                .foregroundStyle(AppColor.ink)

                combinedLineScoreRow(game.away, innings: game.innings, isAway: true, isWinner: game.away.runs > game.home.runs)
                combinedLineScoreRow(game.home, innings: game.innings, isAway: false, isWinner: game.home.runs > game.away.runs)
            }
            .frame(width: tableWidth)
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity)
    }

    private func combinedLineScoreRow(
        _ team: TeamBoxScore,
        innings: [Inning],
        isAway: Bool,
        isWinner: Bool
    ) -> some View {
        HStack(spacing: 0) {
            Text(team.abbreviation)
                .font(.system(size: contentWidth >= 650 ? 14 : 12, weight: .black))
                .foregroundStyle(AppColor.navy)
                .frame(width: contentWidth >= 650 ? 90 : 50, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ForEach(innings) { inning in
                let runs = (isAway ? inning.away : inning.home).runs
                Text(runs.map(String.init) ?? " ")
                    .frame(minWidth: 0, maxWidth: .infinity)
            }

            lineScoreTotal(team.runs, emphasized: isWinner)
            lineScoreTotal(team.hits)
            lineScoreTotal(team.errors)
            lineScoreTotal(team.leftOnBase)
        }
        .font(.system(size: contentWidth >= 650 ? 13 : 11, weight: .semibold))
    }

    private func lineScoreLegend(_ title: String) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
    }

    private func lineScoreTotal(
        _ value: Int,
        emphasized: Bool = false
    ) -> some View {
        Text("\(value)")
            .font(
                emphasized
                    ? .system(size: contentWidth >= 650 ? 17 : 15, weight: .black, design: .monospaced)
                    : .system(size: contentWidth >= 650 ? 13 : 11, weight: .semibold, design: .monospaced)
            )
            .foregroundStyle(emphasized ? AppColor.amber : AppColor.bone)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
    }

    private func recapCard(_ game: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            primarySectionTitle(game.isLive ? "Game So Far" : "Game Recap")

            Text(game.summary)
                .font(AppFont.body)
                .lineSpacing(4)

            if !game.facts.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(game.facts, id: \.self) { fact in
                        HStack(alignment: .top, spacing: 9) {
                            Circle()
                                .fill(AppColor.teamAccent)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(fact)
                                .font(AppFont.bodySmall)
                                .lineSpacing(2)
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private func battingCard(favorite: TeamBoxScore, opponent: TeamBoxScore) -> some View {
        let boxScoreTeam = selectedBoxScoreTeam(favorite: favorite, opponent: opponent)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                sectionTitle("Batting")
                Spacer(minLength: 0)
                statsTeamPicker(favorite: favorite, opponent: opponent)
            }
            let widths: [CGFloat] = [28, 28, 28, 32, 38]
            VStack(spacing: 4) {
                statHeader(labels: ["AB", "R", "H", "RBI", "AVG"], widths: widths)

                VStack(spacing: 0) {
                    ForEach(boxScoreTeam.batting.filter { !["P", "SP", "RP"].contains($0.position.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) }) { batter in
                        statRow(
                            name: batter.name,
                            playerID: self.team.supportsPlayers && selectedStatsTeam == .favorite ? batter.mlbId : nil,
                            detail: batter.position,
                            textValues: [
                                "\(batter.atBats)", "\(batter.runs)", "\(batter.hits)",
                                "\(batter.rbi)", batter.average ?? ".---"
                            ],
                            detailInline: true,
                            columnWidths: widths
                        )
                    }
                }
            }
        }
        .padding(16)
    }

    private func pitchingCard(favorite: TeamBoxScore, opponent: TeamBoxScore) -> some View {
        let boxScoreTeam = selectedBoxScoreTeam(favorite: favorite, opponent: opponent)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                sectionTitle("Pitching")
                Spacer(minLength: 0)
                statsTeamPicker(favorite: favorite, opponent: opponent)
            }
            VStack(spacing: 4) {
                statHeader(labels: ["IP", "H", "ER", "K"])

                VStack(spacing: 0) {
                    ForEach(boxScoreTeam.pitching) { pitcher in
                        statRow(
                            name: pitcher.name,
                            playerID: self.team.supportsPlayers && selectedStatsTeam == .favorite ? pitcher.mlbId : nil,
                            detail: pitcher.note,
                            textValues: [
                                pitcher.inningsPitched,
                                "\(pitcher.hits)",
                                "\(pitcher.earnedRuns)",
                                "\(pitcher.strikeOuts)"
                            ],
                            detailInline: true
                        )
                    }
                }
            }
        }
        .padding(16)
    }

    private func expandedBattingCard(favorite: TeamBoxScore, opponent: TeamBoxScore) -> some View {
        let boxScoreTeam = selectedBoxScoreTeam(favorite: favorite, opponent: opponent)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Batting")
                statsTeamPicker(favorite: favorite, opponent: opponent)
            }

            ForEach(boxScoreTeam.batting.filter { !["P", "SP", "RP"].contains($0.position.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) }) { batter in
                VStack(alignment: .leading, spacing: 7) {
                    playerStatHeading(
                        name: batter.name,
                        playerID: self.team.supportsPlayers && selectedStatsTeam == .favorite ? batter.mlbId : nil,
                        detail: batter.position
                    )
                    VStack(spacing: 4) {
                        expandedStatValue("At bats", "\(batter.atBats)")
                        expandedStatValue("Runs", "\(batter.runs)")
                        expandedStatValue("Hits", "\(batter.hits)")
                        expandedStatValue("RBI", "\(batter.rbi)")
                        expandedStatValue("Average", batter.average ?? ".---")
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Divider().overlay(AppColor.rule) }
            }
        }
        .padding(16)
    }

    private func expandedPitchingCard(favorite: TeamBoxScore, opponent: TeamBoxScore) -> some View {
        let boxScoreTeam = selectedBoxScoreTeam(favorite: favorite, opponent: opponent)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Pitching")
                statsTeamPicker(favorite: favorite, opponent: opponent)
            }

            ForEach(boxScoreTeam.pitching) { pitcher in
                VStack(alignment: .leading, spacing: 7) {
                    playerStatHeading(
                        name: pitcher.name,
                        playerID: self.team.supportsPlayers && selectedStatsTeam == .favorite ? pitcher.mlbId : nil,
                        detail: pitcher.note
                    )
                    VStack(spacing: 4) {
                        expandedStatValue("Innings pitched", pitcher.inningsPitched)
                        expandedStatValue("Hits", "\(pitcher.hits)")
                        expandedStatValue("Earned runs", "\(pitcher.earnedRuns)")
                        expandedStatValue("Strikeouts", "\(pitcher.strikeOuts)")
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Divider().overlay(AppColor.rule) }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func playerStatHeading(name: String, playerID: Int?, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let playerID {
                Button { onSelectPlayer(playerID) } label: {
                    Text(name).font(.headline.weight(.semibold)).foregroundStyle(AppColor.navy)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open player biography")
            } else {
                Text(name).font(.headline.weight(.semibold)).foregroundStyle(AppColor.navy)
            }
            if !detail.isEmpty {
                Text(detail).font(.subheadline).foregroundStyle(AppColor.hunterGreen).fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func expandedStatValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.hunterGreen)
            Text(value).font(.body.monospacedDigit()).foregroundStyle(AppColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func selectedBoxScoreTeam(
        favorite: TeamBoxScore,
        opponent: TeamBoxScore
    ) -> TeamBoxScore {
        selectedStatsTeam == .favorite ? favorite : opponent
    }

    private func statsTeamPicker(
        favorite: TeamBoxScore,
        opponent: TeamBoxScore
    ) -> some View {
        let layout = usesExpandedReadingLayout ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            statsTeamButton(team.cityName, selection: .favorite)
            statsTeamButton(opponent.cityName, selection: .opponent)
        }
        .frame(maxWidth: usesExpandedReadingLayout ? .infinity : 166)
    }

    private func statsTeamButton(
        _ title: String,
        selection: BoxScoreTeamSelection
    ) -> some View {
        Button {
            selectedStatsTeam = selection
        } label: {
            Text(title)
                .font(.subheadline.weight(.black))
                .lineLimit(usesExpandedReadingLayout ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(AppColor.ink)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selectedStatsTeam == selection ? AppColor.teamAccent : Color.clear)
                        .frame(height: 2)
                }
        }
        .buttonStyle(.plain)
    }

    private func statHeader(labels: [String], widths: [CGFloat] = []) -> some View {
        HStack(spacing: statColumnSpacing) {
            Text("Player")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label).frame(width: widths.indices.contains(index) ? widths[index] : 32)
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(AppColor.ink)
    }

    private func statRow(
        name: String,
        playerID: Int? = nil,
        detail: String,
        values: [Int] = [],
        textValues: [String] = [],
        detailInline: Bool = false,
        columnWidths: [CGFloat] = []
    ) -> some View {
        HStack(spacing: statColumnSpacing) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let playerID {
                        Button {
                            onSelectPlayer(playerID)
                        } label: {
                            Text(name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColor.navy)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Open player biography")
                    } else {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    if detailInline, !detail.isEmpty {
                        Text("· \(detail)")
                            .font(.caption)
                            .foregroundStyle(AppColor.hunterGreen)
                            .fixedSize()
                    }
                }
                if !detailInline, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(AppColor.hunterGreen)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array((textValues.isEmpty ? values.map(String.init) : textValues).enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(.subheadline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: columnWidths.indices.contains(index) ? columnWidths[index] : 32)
            }
        }
        .padding(.vertical, contentWidth >= 650 ? 6 : 3)
    }

    private func scoringPlaysCard(_ game: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Scoring Plays")

            ForEach(game.scoringPlays) { play in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(play.inning)
                            .font(.caption.weight(.black))
                            .foregroundStyle(AppColor.red)
                        Spacer()
                        Text("\(game.away.abbreviation) \(play.awayScore) · \(game.home.abbreviation) \(play.homeScore)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppColor.hunterGreen)
                    }
                    Text(play.description)
                        .font(.subheadline)
                        .lineSpacing(2)
                }
            }
        }
        .padding(16)
    }

    private func linksCard(_ game: RecentGame) -> some View {
        VStack(spacing: 10) {
            if let recap = game.officialRecap,
               let recapURL = URL(string: recap.url) {
                Link(destination: recapURL) {
                    linkRow(recap.headline, icon: "newspaper")
                }
            }

            if let gamedayURL = URL(string: game.gamedayUrl) {
                Link(destination: gamedayURL) {
                    linkRow("Open MLB Gameday", icon: "arrow.up.right.square")
                }
            }
        }
        .padding(16)
    }

    private func linkRow(_ text: String, icon: String) -> some View {
        HStack {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
            Spacer()
            Image(systemName: icon)
        }
        .foregroundStyle(AppColor.red)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(usesExpandedReadingLayout ? .headline : .system(size: contentWidth >= 650 ? 15 : 13, weight: .black))
            .foregroundStyle(AppColor.navy)
    }

    private func primarySectionTitle(_ title: String) -> some View {
        Text(title)
            .font(usesExpandedReadingLayout ? .headline : .system(size: contentWidth >= 650 ? 15 : 13, weight: .black))
            .foregroundStyle(AppColor.navy)
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Game Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(store.errorMessage ?? "Game Recaps could not be loaded.")
        } actions: {
            Button("Try Again") {
                Task { await store.load() }
            }
            .buttonStyle(HubProminentButtonStyle())
            .tint(AppColor.red)
        }
    }
}

#Preview {
    RecentGameView()
}

struct LiveGameIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * .pi * 2 / 1.6
            let opacity = reduceMotion ? 1.0 : 0.75 + 0.25 * cos(phase)

            HStack(spacing: 5) {
                Circle().frame(width: 6, height: 6)
                Text("LIVE")
            }
            .font(AppFont.label)
            .foregroundStyle(Color(hubHex: "#FF4545"))
            .opacity(opacity)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live game")
    }
}

struct QualifiedGameIndicator: View {
    let text: String
    let accessibilityLabel: String

    var body: some View {
        Text(text)
            .font(AppFont.label)
            .foregroundStyle(Color(hubHex: "#FFB000"))
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }
}
