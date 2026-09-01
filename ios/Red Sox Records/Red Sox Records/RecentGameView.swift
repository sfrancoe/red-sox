import SwiftUI

private enum BoxScoreTeamSelection {
    case boston
    case opponent
}

struct RecentGameView: View {
    @State private var store = RecentGameStore()
    @State private var selectedStatsTeam: BoxScoreTeamSelection = .boston
    @State private var selectedGameID: Int?

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
                        ProgressView("Loading Game Center…")
                            .tint(AppColor.red)
                    } else {
                        errorView
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
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

    private var selectedGame: RecentGame? {
        if let selectedGameID,
           let game = store.games.first(where: { $0.gamePk == selectedGameID }) {
            return game
        }
        return store.games.first
    }

    private var gameSelector: some View {
        HStack(spacing: 0) {
            ForEach(Array(store.games.enumerated()), id: \.element.gamePk) { index, game in
                Button {
                    selectedGameID = game.gamePk
                    selectedStatsTeam = .boston
                } label: {
                    Text(gameTabTitle(game, index: index))
                        .font(
                            .system(
                                size: 13,
                                weight: selectedGame?.gamePk == game.gamePk ? .black : .regular
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(AppColor.paleRed)
    }

    private func gameTabTitle(_ game: RecentGame, index: Int) -> String {
        if game.isLive { return "LIVE" }
        if index == 0, !store.hasLiveGame { return "LAST GAME" }

        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: game.gameDate) else { return game.formattedDate }
        var title = date.formatted(.dateTime.month(.abbreviated).day()).uppercased()
        let gamesOnDate = store.games
            .filter { candidate in
                guard let candidateDate = formatter.date(from: candidate.gameDate) else { return false }
                return Calendar.current.isDate(candidateDate, inSameDayAs: date)
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
            selectedStatsTeam = .boston
        }
    }

    private func gameContent(_ game: RecentGame) -> some View {
        let redSox = game.away.id == 111 ? game.away : game.home
        let opponent = game.away.id == 111 ? game.home : game.away

        return ScrollView {
            LazyVStack(spacing: 10) {
                scoreCard(game)

                VStack(spacing: 0) {
                    recapCard(game)
                    reportDivider
                    battingCard(redSox: redSox, opponent: opponent)
                    reportDivider
                    pitchingCard(redSox: redSox, opponent: opponent)
                    reportDivider
                    scoringPlaysCard(game)
                    reportDivider
                    linksCard(game)
                }
                .background(AppColor.paper)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColor.border.opacity(0.7), lineWidth: 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .foregroundStyle(AppColor.ink)
        }
        .refreshable {
            let hadLiveGame = store.hasLiveGame
            await store.refresh()
            synchronizeSelection(preferNewLiveGame: !hadLiveGame && store.hasLiveGame)
        }
        .dynamicTypeSize(.xSmall)
    }

    private var reportDivider: some View {
        Divider()
            .overlay(AppColor.border)
            .padding(.horizontal, 16)
    }

    private func scoreCard(_ game: RecentGame) -> some View {
        VStack(spacing: 9) {
            HStack {
                Text(game.formattedDate.uppercased())
                    .font(.title3.weight(.black))
                    .tracking(0.4)

                Spacer()

                Text(game.isLive ? "LIVE" : "FINAL")
                    .font(.caption.weight(.black))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(game.isLive ? AppColor.red : AppColor.green)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            Text(game.gameDetails)
                .font(.subheadline)
                .foregroundStyle(AppColor.hunterGreen)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Divider()

            combinedLineScore(game)
        }
        .cardStyle(padding: 12)
    }

    private func combinedLineScore(_ game: RecentGame) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 50, alignment: .leading)
                ForEach(game.innings) { inning in
                    Text("\(inning.num)")
                        .frame(maxWidth: .infinity)
                }
                lineScoreLegend("R", width: 24)
                lineScoreLegend("H", width: 24)
                lineScoreLegend("E", width: 24)
                lineScoreLegend("LOB", width: 24)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)

            combinedLineScoreRow(game.away, innings: game.innings, isAway: true)
            combinedLineScoreRow(game.home, innings: game.innings, isAway: false)
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity)
    }

    private func combinedLineScoreRow(
        _ team: TeamBoxScore,
        innings: [Inning],
        isAway: Bool
    ) -> some View {
        HStack(spacing: 0) {
            Text(team.cityName)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(AppColor.navy)
                .frame(width: 50, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ForEach(innings) { inning in
                Text("\((isAway ? inning.away : inning.home).runs ?? 0)")
                    .frame(maxWidth: .infinity)
            }

            lineScoreTotal(team.runs, width: 24, emphasized: true)
            lineScoreTotal(team.hits, width: 24)
            lineScoreTotal(team.errors, width: 24)
            lineScoreTotal(team.leftOnBase, width: 24)
        }
        .font(.system(size: 11, weight: .semibold))
    }

    private func lineScoreLegend(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .frame(width: width, alignment: .center)
    }

    private func lineScoreTotal(
        _ value: Int,
        width: CGFloat,
        emphasized: Bool = false
    ) -> some View {
        Text("\(value)")
            .font(
                emphasized
                    ? .system(size: 15, weight: .black, design: .monospaced)
                    : .system(size: 11, weight: .semibold, design: .monospaced)
            )
            .foregroundStyle(emphasized ? AppColor.red : AppColor.ink)
            .frame(width: width, alignment: .center)
    }

    private func recapCard(_ game: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            primarySectionTitle(game.isLive ? "Game So Far" : "Game Recap")

            Text(game.summary)
                .font(.system(size: 15))
                .lineSpacing(4)

            if !game.facts.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(game.facts, id: \.self) { fact in
                        HStack(alignment: .top, spacing: 9) {
                            Circle()
                                .fill(AppColor.red)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(fact)
                                .font(.system(size: 14))
                                .lineSpacing(2)
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private func battingCard(redSox: TeamBoxScore, opponent: TeamBoxScore) -> some View {
        let team = selectedBoxScoreTeam(redSox: redSox, opponent: opponent)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                sectionTitle("Batting")
                Spacer(minLength: 0)
                statsTeamPicker(redSox: redSox, opponent: opponent)
            }
            let widths: [CGFloat] = [28, 28, 28, 32, 38]
            VStack(spacing: 4) {
                statHeader(labels: ["AB", "R", "H", "RBI", "AVG"], widths: widths)

                VStack(spacing: 0) {
                    ForEach(team.batting) { batter in
                        statRow(
                            name: batter.name,
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

    private func pitchingCard(redSox: TeamBoxScore, opponent: TeamBoxScore) -> some View {
        let team = selectedBoxScoreTeam(redSox: redSox, opponent: opponent)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                sectionTitle("Pitching")
                Spacer(minLength: 0)
                statsTeamPicker(redSox: redSox, opponent: opponent)
            }
            VStack(spacing: 4) {
                statHeader(labels: ["IP", "H", "ER", "K"])

                VStack(spacing: 0) {
                    ForEach(team.pitching) { pitcher in
                        statRow(
                            name: pitcher.name,
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

    private func selectedBoxScoreTeam(
        redSox: TeamBoxScore,
        opponent: TeamBoxScore
    ) -> TeamBoxScore {
        selectedStatsTeam == .boston ? redSox : opponent
    }

    private func statsTeamPicker(
        redSox: TeamBoxScore,
        opponent: TeamBoxScore
    ) -> some View {
        HStack(spacing: 2) {
            statsTeamButton("Boston", selection: .boston)
            statsTeamButton(opponent.cityName, selection: .opponent)
        }
        .frame(width: 166)
    }

    private func statsTeamButton(
        _ title: String,
        selection: BoxScoreTeamSelection
    ) -> some View {
        Button {
            selectedStatsTeam = selection
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(Color.black)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selectedStatsTeam == selection ? AppColor.red : Color.clear)
                        .frame(height: 2)
                }
        }
        .buttonStyle(.plain)
    }

    private func statHeader(labels: [String], widths: [CGFloat] = []) -> some View {
        HStack {
            Text("PLAYER")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label).frame(width: widths.indices.contains(index) ? widths[index] : 32)
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
    }

    private func statRow(
        name: String,
        detail: String,
        values: [Int] = [],
        textValues: [String] = [],
        detailInline: Bool = false,
        columnWidths: [CGFloat] = []
    ) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
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
        .padding(.vertical, 3)
    }

    private func scoringPlaysCard(_ game: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Scoring Plays")

            ForEach(game.scoringPlays) { play in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(play.inning.uppercased())
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
        Text(title.uppercased())
            .font(.system(size: 13, weight: .black))
            .tracking(1.1)
            .foregroundStyle(AppColor.navy)
    }

    private func primarySectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .black))
            .tracking(1.1)
            .foregroundStyle(AppColor.navy)
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Game Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(store.errorMessage ?? "Game Center could not be loaded.")
        } actions: {
            Button("Try Again") {
                Task { await store.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.red)
        }
    }
}

#Preview {
    RecentGameView()
}
