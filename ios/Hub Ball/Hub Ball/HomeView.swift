import SwiftUI

enum HomeDestination {
    case games
    case schedule
    case standings
}

struct HomeView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @State private var store: HomeStore
    let team: HubTeam
    let onSelect: (HomeDestination) -> Void

    init(team: HubTeam = .boston, onSelect: @escaping (HomeDestination) -> Void) {
        self.team = team
        self.onSelect = onSelect
        _store = State(initialValue: HomeStore(team: team))
    }

    var body: some View {
        ZStack {
            AppColor.paleRed.ignoresSafeArea()
            homeMasthead
            Group {
                if store.recentGame != nil, store.schedule != nil {
                    briefing
                } else if store.isLoading {
                    ProgressView("Loading today's briefing…")
                        .tint(AppColor.ink)
                        .foregroundStyle(AppColor.ink)
                } else {
                    errorView
                }
            }
        }
        .task { await store.load() }
    }

    private var homeMasthead: some View {
        VStack {
            HStack(spacing: 9) {
                Image(systemName: "baseball.fill")
                    .font(.system(size: contentWidth >= 650 ? 42 : 36, weight: .regular))

                Text(team.fullName)
                    .font(AppFont.displayLarge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .layoutPriority(1)

                Spacer()

                Text(todayHeading)
                    .font(AppFont.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(AppColor.ink)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(team.fullName), \(todayHeading)")

            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var briefing: some View {
        ScrollView {
            VStack(spacing: 0) {
                lastGameCard
                Color.clear.frame(height: 32)
                standingsCard
                Color.clear.frame(height: 32)
                upcomingBoard
            }
            .padding(.horizontal, contentWidth >= 650 ? 18 : 12)
            .padding(.top, 107)
            .padding(.bottom, 12)
        }
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private var standingsCard: some View {
        if let division = store.standings?.divisions.first(where: { division in
            division.teams.contains(where: \.isFavorite)
        }) {
            Button { onSelect(.standings) } label: {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("TEAM")
                            .font(.system(size: contentWidth >= 650 ? 20 : 17, weight: .black))
                            .frame(width: contentWidth >= 650 ? 200 : 135, alignment: .leading)
                        Text("W").frame(maxWidth: .infinity)
                        Text("L").frame(maxWidth: .infinity)
                        Text("GB").frame(maxWidth: .infinity)
                        Text("L10").frame(maxWidth: .infinity)
                        Text("STRK").frame(maxWidth: .infinity)
                    }
                    .font(AppFont.label)
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .modifier(HomeTableHeaderStyle())

                    ForEach(Array(division.teams.enumerated()), id: \.element.id) { index, team in
                        HStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Text(team.rank)
                                    .font(AppFont.number)
                                    .foregroundStyle(AppColor.boneMuted)
                                    .frame(width: 12, alignment: .trailing)
                                Text(team.cityName)
                                    .font(.system(size: 15, weight: team.isFavorite ? .black : .bold))
                                    .lineLimit(1)
                            }
                            .frame(width: contentWidth >= 650 ? 200 : 135, alignment: .leading)

                            standingNumber(team.wins, emphasized: team.isFavorite)
                            standingNumber(team.losses, emphasized: team.isFavorite)
                            Text(team.gamesBack)
                                .font(AppFont.number)
                                .overlay(alignment: .bottom) {
                                    if team.isFavorite {
                                        Rectangle()
                                            .fill(AppColor.amber)
                                            .frame(height: 1)
                                            .offset(y: 2)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            Text(team.lastTen)
                                .font(AppFont.number)
                                .frame(maxWidth: .infinity)
                            Text(team.streak)
                                .font(AppFont.number)
                                .foregroundStyle(AppColor.streakColor(team.streak))
                                .frame(maxWidth: .infinity)
                        }
                        .foregroundStyle(AppColor.navy)
                        .padding(.horizontal, 13)
                        .frame(height: 35)
                        .background(team.isFavorite ? AppColor.paleBlue.opacity(0.72) : AppColor.paper)

                        if index < division.teams.count - 1 {
                            Divider().overlay(AppColor.separator).padding(.leading, 13)
                        }
                    }
                }
                .modifier(HomeCardStyle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the standings")
        }
    }

    @ViewBuilder
    private var lastGameCard: some View {
        if let game = store.recentGame {
            let favorite = favoriteTeam(in: game)
            let opponent = opponent(in: game)
            Button { onSelect(.games) } label: {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        HStack(spacing: 7) {
                            Text(compactNumericDate(game.gameDate))
                            if !game.isLive {
                                Text(game.result.lowercased() == "win" ? "W" : "L")
                                    .foregroundStyle(
                                        game.result.lowercased() == "win"
                                            ? AppColor.resultWinText
                                            : AppColor.resultLossText
                                    )
                            }
                        }
                        .font(.system(size: contentWidth >= 650 ? 20 : 17, weight: .black))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("R").frame(width: 38, alignment: .trailing)
                        Text("H").frame(width: 38, alignment: .trailing)
                        Text("E").frame(width: 38, alignment: .trailing)
                        Text("LOB").frame(width: 44, alignment: .trailing)
                        Text("SB").frame(width: 36, alignment: .trailing)
                    }
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .modifier(HomeTableHeaderStyle())

                    gameResultRow(favorite, isWinner: favorite.runs > opponent.runs)
                    Divider().overlay(AppColor.separator).padding(.leading, 13)
                    gameResultRow(opponent, isWinner: opponent.runs > favorite.runs)

                    HStack(spacing: 8) {
                        Text("Home runs")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(AppColor.boneMuted)
                        Text(homeRunSummary(for: favorite))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColor.navy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .padding(.horizontal, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 27)
                    .background(AppColor.paleBlue.opacity(0.35))

                    HStack(spacing: 8) {
                        Text(game.isLive ? "Live" : "Pitching")
                            .foregroundStyle(AppColor.boneMuted)
                        Text(game.isLive ? game.liveStatus ?? "In progress" : pitchingSummary(for: game))
                            .foregroundStyle(AppColor.navy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .font(.system(size: 10, weight: .black))
                    .padding(.horizontal, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 27)
                    .background(AppColor.paperRaised)
                }
                .modifier(HomeCardStyle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens Game Center")
        }
    }

    @ViewBuilder
    private var upcomingBoard: some View {
        if let schedule = store.schedule {
            let upcomingGames = schedule.games
                .filter { $0.gamePk != store.recentGame?.gamePk }
                .prefix(3)
            VStack(spacing: 0) {
                tableHeader
                ForEach(Array(upcomingGames).indices, id: \.self) { index in
                    let game = Array(upcomingGames)[index]
                    upcomingRow(game)
                    if index < upcomingGames.count - 1 {
                        Divider().overlay(AppColor.separator).padding(.leading, 13)
                    }
                }

                if upcomingGames.isEmpty {
                    Text("No upcoming games are scheduled.")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.ink)
                        .frame(maxWidth: .infinity, minHeight: 110)
                }
            }
            .modifier(HomeCardStyle())
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text(contentWidth < 400 ? "NEXT 3" : "NEXT 3 GAMES")
                .font(.system(size: contentWidth >= 650 ? 20 : 17, weight: .black))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("TIME").frame(width: 52, alignment: .center)
            Text("\(team.shortName.uppercased()) STARTER").frame(width: 128, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .black))
        .tracking(0.75)
        .padding(.horizontal, 13)
        .frame(height: 36)
        .modifier(HomeTableHeaderStyle())
    }

    private func upcomingRow(_ game: ScheduledGame) -> some View {
        return HStack(spacing: 8) {
            Text("\(shortGameDate(game.gameDate)) \(game.locationWord) \(game.opponent)")
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(game.formattedTime)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 52, alignment: .center)
            Text(projectedStarter(for: game))
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 128, alignment: .trailing)
        }
        .foregroundStyle(AppColor.navy)
        .padding(.horizontal, 13)
        .frame(height: 35)
        .accessibilityElement(children: .combine)
    }

    private func gameResultRow(_ team: TeamBoxScore, isWinner: Bool) -> some View {
        HStack(spacing: 0) {
            Text(team.cityName)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            gameResultNumber(team.runs, width: 38, isRunTotal: true, isWinner: isWinner)
            gameResultNumber(team.hits, width: 38)
            gameResultNumber(team.errors, width: 38)
            gameResultNumber(team.leftOnBase, width: 44)
            gameResultNumber(team.batting.reduce(0) { $0 + ($1.stolenBases ?? 0) }, width: 36)
        }
        .foregroundStyle(AppColor.navy)
        .padding(.horizontal, 13)
        .frame(height: 35)
        .background(isWinner ? AppColor.paleBlue.opacity(0.72) : AppColor.paper)
    }

    private func gameResultNumber(
        _ value: Int,
        width: CGFloat,
        isRunTotal: Bool = false,
        isWinner: Bool = false
    ) -> some View {
        Text("\(value)")
            .font(isRunTotal ? AppFont.numberLarge : AppFont.number)
            .foregroundStyle(isRunTotal && isWinner ? AppColor.amber : AppColor.bone)
            .frame(width: width, alignment: .trailing)
    }

    private func homeRunSummary(for team: TeamBoxScore) -> String {
        let hitters = team.batting.filter { $0.homeRuns > 0 }
        guard !hitters.isEmpty else { return "None" }
        return hitters.map { batter in
            let total = batter.seasonHomeRuns.map(String.init) ?? "—"
            let surname = batter.name.split(separator: " ").last.map(String.init) ?? batter.name
            return "\(surname) (\(total))"
        }.joined(separator: ", ")
    }

    private func pitchingSummary(for game: RecentGame) -> String {
        var decisions = [
            pitchingDecision("W", pitcher: game.decisions.winner, game: game),
            pitchingDecision("L", pitcher: game.decisions.loser, game: game)
        ]
        if !game.decisions.save.isEmpty {
            decisions.append(pitchingDecision("SV", pitcher: game.decisions.save, game: game))
        }
        return decisions.joined(separator: " · ")
    }

    private func pitchingDecision(_ label: String, pitcher: String, game: RecentGame) -> String {
        let record = decisionValue(for: pitcher, in: game.away)
            ?? decisionValue(for: pitcher, in: game.home)
        let name = surname(pitcher)
        return record.map { "\(label) \(name) (\($0))" } ?? "\(label) \(name)"
    }

    private func decisionValue(for pitcher: String, in team: TeamBoxScore) -> String? {
        guard let note = team.pitching.first(where: { $0.name == pitcher })?.note,
              let comma = note.lastIndex(of: ",") else { return nil }
        return note[note.index(after: comma)...]
            .trimmingCharacters(in: CharacterSet(charactersIn: " )"))
    }

    private var todayHeading: String {
        let now = Date.now
        let calendar = Calendar.current
        let weekday = now.formatted(.dateTime.weekday(.abbreviated))
        let month = now.formatted(.dateTime.month(.abbreviated))
        let day = calendar.component(.day, from: now)
        return "\(weekday), \(month) \(ordinal(day))"
    }

    private func ordinal(_ day: Int) -> String {
        let suffix: String
        if (11...13).contains(day % 100) { suffix = "th" }
        else {
            switch day % 10 { case 1: suffix = "st"; case 2: suffix = "nd"; case 3: suffix = "rd"; default: suffix = "th" }
        }
        return "\(day)\(suffix)"
    }

    private func projectedStarter(for game: ScheduledGame) -> String {
        guard game.showProbables, !game.favoriteTeamPitcher.isEmpty else { return "TBD" }
        return game.favoriteTeamPitcher
    }

    private func surname(_ name: String) -> String {
        name.split(separator: " ").last.map(String.init) ?? name
    }

    private func standingNumber(_ value: Int, emphasized: Bool) -> some View {
        Text("\(value)")
            .font(.system(size: 14, weight: emphasized ? .black : .medium, design: .monospaced))
            .frame(maxWidth: .infinity)
    }

    private func scoreTeam(_ team: TeamBoxScore, isWinner: Bool) -> some View {
        HStack(alignment: .center, spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text(team.abbreviation)
                    .font(AppFont.displayMedium)
                    .foregroundStyle(AppColor.bone)
                Text(team.record)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppColor.navy.opacity(0.46))
            }
            Spacer(minLength: 2)
            Text("\(team.runs)")
                .font(AppFont.numberExtraLarge)
                .foregroundStyle(isWinner ? AppColor.amber : AppColor.bone)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func resultPill(_ result: String) -> some View {
        Text(result.uppercased())
            .font(.system(size: 10, weight: .black))
            .tracking(0.7)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(result.lowercased() == "win" ? AppColor.resultWin : AppColor.resultLoss)
            .foregroundStyle(AppColor.ink)
            .clipShape(Rectangle())
    }

    private func oddsCell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(value == "—" ? AppColor.navy.opacity(0.36) : AppColor.navy)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: width, alignment: .trailing)
    }

    private func favoriteTeam(in game: RecentGame) -> TeamBoxScore {
        game.away.id == team.mlbID ? game.away : game.home
    }

    private func opponent(in game: RecentGame) -> TeamBoxScore {
        game.away.id == team.mlbID ? game.home : game.away
    }

    private func ordinal(_ rank: String) -> String {
        switch rank { case "1": "1st"; case "2": "2nd"; case "3": "3rd"; default: "\(rank)th" }
    }

    private func compactDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func compactNumericDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(.dateTime.month(.defaultDigits).day().year(.twoDigits))
    }

    private func shortGameDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(.dateTime.weekday(.abbreviated))
            + " "
            + date.formatted(.dateTime.month(.defaultDigits).day())
    }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
    private func american(_ value: Int?) -> String { value.map(signed) ?? "—" }

    private func runLine(_ odds: HomeGameOdds?) -> String {
        guard let line = odds?.runLine else { return "—" }
        let lineText = line > 0 ? "+\(line.formatted())" : line.formatted()
        return odds?.runLinePrice.map { "\(lineText) \(signed($0))" } ?? lineText
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle)
            Text(store.errorMessage ?? "Today's briefing is unavailable.")
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await store.load() } }
                .buttonStyle(HubProminentButtonStyle())
                .tint(AppColor.navy)
        }
        .foregroundStyle(AppColor.ink)
        .padding(24)
    }
}

private struct HomeTableHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(AppColor.ink.opacity(0.82))
            .background(AppColor.teamAccent.opacity(0.06))
            .overlay(alignment: .top) {
                Rectangle().fill(AppColor.ink.opacity(0.78)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppColor.ink.opacity(0.78)).frame(height: 1)
            }
    }
}

private struct HomeCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(Rectangle())
            .overlay(alignment: .top) { Rectangle().fill(AppColor.rule).frame(height: 1) }
    }
}
