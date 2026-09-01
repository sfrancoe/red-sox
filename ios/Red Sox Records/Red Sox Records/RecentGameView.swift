import SwiftUI

private enum BoxScoreTeamSelection {
    case boston
    case opponent
}

struct RecentGameView: View {
    @State private var store = RecentGameStore()
    @State private var selectedStatsTeam: BoxScoreTeamSelection = .boston

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                Group {
                    if let game = store.game {
                        gameContent(game)
                    } else if store.isLoading {
                        ProgressView("Loading the latest game…")
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
        }
    }

    private func gameContent(_ game: RecentGame) -> some View {
        let redSox = game.away.id == 111 ? game.away : game.home
        let opponent = game.away.id == 111 ? game.home : game.away

        return ScrollView {
            LazyVStack(spacing: 6) {
                scoreCard(game)
                summaryCard(game)
                lineScoreCard(game)
                gameNotesCard(game)
                decisionsCard(game)
                battingCard(redSox: redSox, opponent: opponent)
                pitchingCard(redSox: redSox, opponent: opponent)
                scoringPlaysCard(game)
                linksCard(game)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .foregroundStyle(AppColor.ink)
        }
        .refreshable {
            await store.load()
        }
        .dynamicTypeSize(.xSmall)
    }

    private func scoreCard(_ game: RecentGame) -> some View {
        VStack(spacing: 9) {
            HStack {
                Text(game.formattedDate.uppercased())
                    .font(.title3.weight(.black))
                    .tracking(0.4)

                Spacer()

                Text("FINAL")
                    .font(.caption.weight(.black))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AppColor.green)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            Text(game.gameDetails)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Divider()

            HStack(spacing: 8) {
                scoreLegend("R")
                scoreLegend("H")
                scoreLegend("E")
                scoreLegend("LOB")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            teamScoreRow(game.away)
            teamScoreRow(game.home)
        }
        .cardStyle(padding: 12)
    }

    private func teamScoreRow(_ team: TeamBoxScore) -> some View {
        HStack(spacing: 10) {
            Text(team.cityName)
                .font(.title3.weight(.black))
                .foregroundStyle(AppColor.navy)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            HStack(spacing: 8) {
                scoreNumber(team.runs, emphasized: true)
                scoreNumber(team.hits)
                scoreNumber(team.errors)
                scoreNumber(team.leftOnBase)
            }
        }
    }

    private func scoreNumber(_ number: Int, emphasized: Bool = false) -> some View {
        Text("\(number)")
            .font(emphasized ? .title2.weight(.black) : .headline)
            .monospacedDigit()
            .frame(width: 36, alignment: .trailing)
            .foregroundStyle(emphasized ? AppColor.red : AppColor.ink)
            .lineLimit(1)
    }

    private func scoreLegend(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(width: 36, alignment: .trailing)
    }

    private func summaryCard(_ game: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            primarySectionTitle("Game Summary")
            Text(game.summary)
                .font(.system(size: 15))
                .lineSpacing(4)
        }
        .cardStyle()
    }

    private func lineScoreCard(_ game: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            primarySectionTitle("Line Score")

            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    Text("")
                        .frame(width: 42, alignment: .leading)
                    ForEach(game.innings) { inning in
                        Text("\(inning.num)")
                            .frame(maxWidth: .infinity)
                    }
                    Text("R")
                        .fontWeight(.black)
                        .frame(width: 28, alignment: .trailing)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

                lineScoreRow(game.away, innings: game.innings, isAway: true)
                lineScoreRow(game.home, innings: game.innings, isAway: false)
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity)
        }
        .cardStyle()
    }

    private func lineScoreRow(
        _ team: TeamBoxScore,
        innings: [Inning],
        isAway: Bool
    ) -> some View {
        HStack(spacing: 0) {
            Text(team.abbreviation)
                .fontWeight(.black)
                .frame(width: 42, alignment: .leading)
            ForEach(innings) { inning in
                Text("\((isAway ? inning.away : inning.home).runs ?? 0)")
                    .frame(maxWidth: .infinity)
            }
            Text("\(team.runs)")
                .fontWeight(.black)
                .foregroundStyle(AppColor.red)
                .frame(width: 28, alignment: .trailing)
        }
        .font(.subheadline)
    }

    private func gameNotesCard(_ game: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            primarySectionTitle("Game Notes")

            ForEach(game.facts, id: \.self) { fact in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(AppColor.red)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(fact)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                }
            }
        }
        .cardStyle()
    }

    private func decisionsCard(_ game: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            primarySectionTitle("Decisions")
            decisionRow("Winning pitcher", game.decisions.winner)
            decisionRow("Losing pitcher", game.decisions.loser)
            if !game.decisions.save.isEmpty {
                decisionRow("Save", game.decisions.save)
            }
        }
        .cardStyle()
    }

    private func decisionRow(_ label: String, _ name: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AppColor.navy)
            Spacer()
            Text(name)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private func battingCard(redSox: TeamBoxScore, opponent: TeamBoxScore) -> some View {
        let team = selectedBoxScoreTeam(redSox: redSox, opponent: opponent)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                sectionTitle("Batting", icon: "figure.baseball")
                Spacer(minLength: 0)
                statsTeamPicker(redSox: redSox, opponent: opponent)
            }
            statHeader(labels: ["AB", "R", "H", "RBI"])

            VStack(spacing: 0) {
                ForEach(team.batting) { batter in
                    statRow(
                        name: batter.name,
                        detail: batter.position,
                        values: [batter.atBats, batter.runs, batter.hits, batter.rbi],
                        detailInline: true
                    )
                }
            }
        }
        .cardStyle()
    }

    private func pitchingCard(redSox: TeamBoxScore, opponent: TeamBoxScore) -> some View {
        let team = selectedBoxScoreTeam(redSox: redSox, opponent: opponent)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                sectionTitle("Pitching", icon: "baseball.diamond.bases")
                Spacer(minLength: 0)
                statsTeamPicker(redSox: redSox, opponent: opponent)
            }
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
        .cardStyle()
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
        .padding(2)
        .background(AppColor.paleBlue)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .font(.system(size: 10, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(selectedStatsTeam == selection ? Color.white : AppColor.navy)
                .background(selectedStatsTeam == selection ? AppColor.navy : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statHeader(labels: [String]) -> some View {
        HStack {
            Text("PLAYER")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(labels, id: \.self) { label in
                Text(label).frame(width: 32)
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
        detailInline: Bool = false
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
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                if !detailInline, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array((textValues.isEmpty ? values.map(String.init) : textValues).enumerated()), id: \.offset) { _, value in
                Text(value)
                    .font(.subheadline)
                    .monospacedDigit()
                    .frame(width: 32)
            }
        }
        .padding(.vertical, 3)
    }

    private func scoringPlaysCard(_ game: RecentGame) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Scoring Plays", icon: "list.bullet.rectangle")

            ForEach(game.scoringPlays) { play in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(play.inning.uppercased())
                            .font(.caption.weight(.black))
                            .foregroundStyle(AppColor.red)
                        Spacer()
                        Text("\(game.away.abbreviation) \(play.awayScore) · \(game.home.abbreviation) \(play.homeScore)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(play.description)
                        .font(.subheadline)
                        .lineSpacing(2)
                }
            }
        }
        .cardStyle()
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
        .cardStyle()
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

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title.uppercased(), systemImage: icon)
            .font(.caption.weight(.black))
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
            Text(store.errorMessage ?? "The latest game could not be loaded.")
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
