import SwiftUI

private enum OctoberSection: String, CaseIterable {
    case race = "Bracket"
    case history = "Best/Worst"
}

private enum PostseasonHistoryGroup: String, CaseIterable {
    case hitting = "Batting"
    case pitching = "Pitching"
}

private enum PostseasonHistoryRanking: String, CaseIterable {
    case best = "Best"
    case worst = "Worst"
}

private enum PostseasonHistoryLeague: String, CaseIterable {
    case both = "Both"
    case american = "AL"
    case national = "NL"
}

private func bracketLabel(_ series: PostseasonSeries) -> String {
    switch series.round {
    case "wild-card": "\(series.league ?? "League") Wild Card slot \(series.bracketSlot)"
    case "division-series": "\(series.league ?? "League") Division Series slot \(series.bracketSlot)"
    case "league-championship": "\(series.league ?? "League") Championship Series"
    case "world-series": "World Series"
    default: "Bracket slot not established"
    }
}

struct OctoberView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = PostseasonStore(season: OctoberFeature.season)
    @State private var historyStore = PostseasonHistoryStore(season: OctoberFeature.season)
    @State private var section: OctoberSection = .race
    @State private var historyGroup: PostseasonHistoryGroup = .hitting
    @State private var historyLeague: PostseasonHistoryLeague = .both
    @State private var historyCategoryKey = "ops"
    @State private var historyRanking: PostseasonHistoryRanking = .best
    @State private var selectedSeries: PostseasonSeries?

    private var payload: PostseasonPayload? { store.snapshot }
    private var series: [PostseasonSeries] { payload?.series ?? [] }

    var body: some View {
        ZStack {
            AppColor.night.ignoresSafeArea()
            VStack(spacing: 0) {
                masthead
                Picker("Playoff view", selection: $section) {
                    ForEach(OctoberSection.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Group {
                    if section == .history {
                        historyView
                    } else if let payload {
                        switch section {
                        case .race: raceView(payload)
                        case .history: EmptyView()
                        }
                    } else if store.isLoading {
                        ProgressView("Opening the playoff bracket…").tint(AppColor.amber)
                            .foregroundStyle(AppColor.bone)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        emptyState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            async let postseasonRefresh: Void = store.refresh()
            async let historyRefresh: Void = historyStore.refresh()
            _ = await (postseasonRefresh, historyRefresh)
            while !Task.isCancelled, scenePhase == .active {
                guard store.snapshot?.isLive == true else { break }
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, scenePhase == .active else { break }
                await store.refresh()
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-show-playoff-history") {
                section = .history
            }
            #endif
        }
        .sheet(item: $selectedSeries) { series in
            OctoberSeriesDetail(series: series, allSeries: self.series, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
    }

    private var masthead: some View {
        Text("\(String(OctoberFeature.season)) PLAYOFFS")
            .font(AppFont.displayLarge)
            .tracking(1.5)
            .foregroundStyle(AppColor.bone)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(AppColor.nightRaised)
    }

    private func raceView(_ payload: PostseasonPayload) -> some View {
        PlayoffBracketView(payload: payload) { selectedSeries = $0 }
            .refreshable { await store.refresh() }
    }

    private func tonightView(_ payload: PostseasonPayload) -> some View {
        let tonight = relevantTonightGames(payload.games)
        let ordered = tonight.sorted {
            let firstPriority = priority($0, payload: payload)
            let secondPriority = priority($1, payload: payload)
            if firstPriority != secondPriority { return firstPriority < secondPriority }
            return ($0.gameDate ?? "", $0.gamePk) < ($1.gameDate ?? "", $1.gamePk)
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WHAT MATTERS NEXT")
                        .font(AppFont.displayMedium)
                        .foregroundStyle(AppColor.bone)
                    Text("Editorial priority · not a win probability")
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.boneMuted)
                }
                if ordered.isEmpty {
                    Text("No postseason game is on today. Here is the next scheduled game and the latest confirmed result.")
                        .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
                }
                ForEach(ordered) { game in tonightCard(game, payload: payload) }
            }
            .padding(14)
        }
        .refreshable { await store.refresh() }
    }

    @ViewBuilder
    private var historyView: some View {
        if let history = historyStore.snapshot {
            playoffHistory(history)
        } else if historyStore.isLoading {
            ProgressView("Building career playoff rankings…")
                .tint(AppColor.amber)
                .foregroundStyle(AppColor.bone)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Career playoff rankings aren’t available yet.")
                    .font(AppFont.displayMedium)
                Text("The bracket is still available while the roster snapshot refreshes.")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.boneDim)
                Button("Try again") { Task { await historyStore.refresh() } }
                    .buttonStyle(HubProminentButtonStyle())
                    .frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .foregroundStyle(AppColor.bone)
        }
    }

    private func playoffHistory(_ payload: PostseasonHistoryPayload) -> some View {
        let categories = historyGroup == .hitting ? payload.categories.hitting : payload.categories.pitching
        let selected = categories.first(where: { $0.key == historyCategoryKey }) ?? categories.first
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Picker("Player group", selection: $historyGroup) {
                        ForEach(PostseasonHistoryGroup.allCases, id: \.self) { group in
                            Text(group.rawValue).tag(group)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: historyGroup) { _, group in
                        historyCategoryKey = group == .hitting ? "ops" : "wins"
                    }

                    Picker("League", selection: $historyLeague) {
                        ForEach(PostseasonHistoryLeague.allCases, id: \.self) { league in
                            Text(league.rawValue).tag(league)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories) { category in
                            Button(category.label) { historyCategoryKey = category.key }
                                .font(AppFont.label)
                                .foregroundStyle(historyCategoryKey == category.key ? AppColor.night : AppColor.bone)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 40)
                                .background(historyCategoryKey == category.key ? AppColor.amber : AppColor.nightRaised)
                        }
                    }
                }

                if let selected {
                    Picker("Ranking", selection: $historyRanking) {
                        ForEach(PostseasonHistoryRanking.allCases, id: \.self) { ranking in
                            Text(ranking.rawValue).tag(ranking)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Qualified: \(selected.qualification) · Current 40-man rosters")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(AppColor.boneDim)

                    historyBoard(
                        filteredHistoryEntries(
                            historyRanking == .best ? selected.best : selected.worst,
                            payload: payload
                        ),
                        category: selected
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .accessibilityIdentifier("playoffs.history")
        .refreshable { await historyStore.refresh() }
    }

    private func historyBoard(
        _ entries: [PostseasonHistoryEntry],
        category: PostseasonHistoryCategory
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                Text("No qualified players yet.")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.boneDim)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(String(index + 1))
                            .font(AppFont.number)
                            .monospacedDigit()
                            .foregroundStyle(AppColor.boneMuted)
                            .frame(width: 24, alignment: .trailing)
                        Text(entry.name)
                            .font(AppFont.bodySmall.weight(.semibold))
                            .foregroundStyle(AppColor.bone)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("\(entry.teamAbbreviation) · \(historySample(entry))")
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.boneMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 6)
                        Text(historyValue(entry.value, key: category.key))
                            .font(.custom("Inter-Medium", size: 16, relativeTo: .body))
                            .monospacedDigit()
                            .foregroundStyle(AppColor.bone)
                    }
                    .padding(.vertical, 5)
                    .overlay(alignment: .bottom) { Rectangle().fill(AppColor.rule).frame(height: 1) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(AppColor.nightRaised)
    }

    private func filteredHistoryEntries(
        _ entries: [PostseasonHistoryEntry],
        payload: PostseasonHistoryPayload
    ) -> [PostseasonHistoryEntry] {
        guard historyLeague != .both else { return entries }
        let leagueByTeam = Dictionary(uniqueKeysWithValues: payload.teams.map { ($0.teamId, $0.league) })
        return entries.filter { leagueByTeam[$0.teamId] == historyLeague.rawValue }
    }

    private func historySample(_ entry: PostseasonHistoryEntry) -> String {
        if let plateAppearances = entry.plateAppearances {
            return "\(plateAppearances) PA · \(entry.games) G"
        }
        return "\(entry.inningsPitched ?? "0.0") IP · \(entry.games) G"
    }

    private func historyValue(_ value: Double, key: String) -> String {
        switch key {
        case "ops", "avg":
            let rendered = value.formatted(.number.precision(.fractionLength(3)))
            return rendered.hasPrefix("0") ? String(rendered.dropFirst()) : rendered
        case "whip", "era":
            return value.formatted(.number.precision(.fractionLength(2)))
        default:
            return Int(value).formatted()
        }
    }

    private func tonightCard(_ game: PostseasonGame, payload: PostseasonPayload) -> some View {
        let localDate = game.startDate
        let associated = game.seriesId.flatMap { id in series.first(where: { $0.id == id }) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(associated.map { roundTitle($0.round) } ?? "POSTSEASON")
                    .font(AppFont.label).foregroundStyle(AppColor.amber)
                Spacer()
                Text(game.timeTBD || localDate == nil ? "TIME TBD" : localDate!.formatted(date: .abbreviated, time: .shortened))
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.night)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColor.scheduleGray)
            }
            HStack(alignment: .center, spacing: 10) {
                Text(game.away.name ?? game.away.slot ?? "TBD")
                    .frame(maxWidth: .infinity, alignment: .leading)
                score(game.awayScore)
                Text("—").foregroundStyle(AppColor.boneMuted)
                score(game.homeScore)
                Text(game.home.name ?? game.home.slot ?? "TBD")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
            .font(AppFont.bodySmall.weight(.semibold))
            if !game.broadcasts.isEmpty {
                Text("BROADCAST · \(game.broadcasts.joined(separator: ", "))")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.boneMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(game.status.uppercased())
                    .font(AppFont.label).foregroundStyle(game.abstractState == "Live" ? AppColor.amber : AppColor.boneMuted)
                if let inning = game.liveInning, game.abstractState == "Live" {
                    Text("· INNING \(inning)").font(AppFont.label).foregroundStyle(AppColor.boneDim)
                }
                Spacer()
                if game.conditional { Text("IF NECESSARY").font(AppFont.label).foregroundStyle(AppColor.boneMuted) }
            }
            Text(stakes(for: game, series: associated))
                .font(AppFont.bodySmall)
                .foregroundStyle(AppColor.boneDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(AppColor.nightRaised)
        .overlay(alignment: .leading) { Rectangle().fill(game.abstractState == "Live" ? AppColor.amber : AppColor.rule).frame(width: 3) }
    }

    private func score(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "·")
            .font(AppFont.numberLarge)
            .monospacedDigit()
            .foregroundStyle(AppColor.bone)
            .frame(minWidth: 22)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The field hasn’t opened yet.").font(AppFont.displayMedium)
            Text("We’ll keep the MLB-wide postseason path here. Your favorite team stays as it is.")
                .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
            if store.refreshFailed { Text("Postseason data is temporarily unavailable.").font(AppFont.bodySmall).foregroundStyle(AppColor.amber) }
            Button("Try again") { Task { await store.refresh() } }
                .buttonStyle(HubProminentButtonStyle())
                .frame(minHeight: 44)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .foregroundStyle(AppColor.bone)
    }

    private func priority(_ game: PostseasonGame, payload: PostseasonPayload) -> Int {
        let current = game.seriesId.flatMap { id in series.first(where: { $0.id == id }) }
        let aWins = game.away.teamId.flatMap { current?.wins(for: $0) } ?? 0
        let hWins = game.home.teamId.flatMap { current?.wins(for: $0) } ?? 0
        let needed = current?.requiredWins ?? 99
        if aWins == needed - 1 || hWins == needed - 1 { return 0 }
        if let rooting = store.selectedRootingTeamID,
           game.away.teamId == rooting || game.home.teamId == rooting { return 1 }
        if game.abstractState == "Live" { return 2 }
        return 3
    }

    private func stakes(for game: PostseasonGame, series: PostseasonSeries?) -> String {
        guard let series, let required = series.requiredWins, let wins = series.wins,
              let awayID = game.away.teamId, let homeID = game.home.teamId else {
            return "Series score is shown when it is confirmed; stakes are not yet established."
        }
        let awayWins = wins[String(awayID)] ?? 0
        let homeWins = wins[String(homeID)] ?? 0
        if awayWins == required - 1, homeWins == required - 1 {
            return "Winner advances. The other team is eliminated."
        }
        if awayWins == required - 1 {
            return "A win by \(game.away.name ?? "\(awayID)") advances. \(game.home.name ?? "Their opponent") must win to extend the series."
        }
        if homeWins == required - 1 {
            return "A win by \(game.home.name ?? "\(homeID)") advances. \(game.away.name ?? "Their opponent") must win to extend the series."
        }
        if series.winnerTeamId != nil { return "Series complete. The result is confirmed above." }
        return "The series continues; neither team can clinch with one win tonight."
    }

    private func relevantTonightGames(_ games: [PostseasonGame]) -> [PostseasonGame] {
        let playable = games.filter { ["Preview", "Live", "Final"].contains($0.abstractState) }
        let live = playable.filter { $0.abstractState == "Live" }
        if !live.isEmpty { return live }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        let todayKey = formatter.string(from: Date())
        let upcoming = playable.filter { $0.abstractState == "Preview" || $0.abstractState == "Scheduled" }
        let nextDate = upcoming.compactMap { $0.gameDate?.prefix(10).description }
            .filter { $0 >= todayKey }.min()
        let next = upcoming.filter { $0.gameDate?.prefix(10).description == nextDate }
        let latestFinal = playable.filter { $0.abstractState == "Final" }
            .max { ($0.gameDate ?? "") < ($1.gameDate ?? "") }
        if next.isEmpty { return latestFinal.map { [$0] } ?? [] }
        return next + (latestFinal.map { [$0] } ?? [])
    }

    private func teamName(_ teamID: Int) -> String {
        HubTeam.allCases.first(where: { $0.mlbID == teamID })?.fullName ?? "Team"
    }

    private func roundTitle(_ round: String) -> String {
        switch round {
        case "wild-card": "Wild Card"
        case "division-series": "Division Series"
        case "league-championship": "League Championship"
        case "world-series": "World Series"
        default: "Postseason"
        }
    }

}

private struct OctoberSeriesDetail: View {
    @Environment(\.dismiss) private var dismiss
    let series: PostseasonSeries
    let allSeries: [PostseasonSeries]
    let store: PostseasonStore

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(series.participants.compactMap(\.name).joined(separator: "  ·  "))
                    .font(AppFont.displayMedium).foregroundStyle(AppColor.bone)
                ForEach(series.participants) { team in
                    HStack {
                        Text(team.name ?? team.slot ?? "Team to be determined")
                        Spacer()
                        Text(team.teamId.flatMap { series.wins(for: $0) }.map(String.init) ?? "—")
                            .font(AppFont.numberLarge).monospacedDigit().foregroundStyle(AppColor.amber)
                    }
                    .font(AppFont.body.weight(.semibold)).foregroundStyle(AppColor.bone)
                }
                Text(seriesConsequence)
                    .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
                Text("Next: \(nextDescription)")
                    .font(AppFont.bodySmall).foregroundStyle(AppColor.boneMuted)
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.night.ignoresSafeArea())
            .navigationTitle(series.round.replacingOccurrences(of: "-", with: " ").capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("series.close")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func teamName(_ id: Int) -> String {
        HubTeam.allCases.first(where: { $0.mlbID == id })?.fullName ?? "Team"
    }

    private var seriesConsequence: String {
        guard let winner = series.winnerTeamId else {
            guard let required = series.requiredWins, let wins = series.wins,
                  let first = series.participants.first?.teamId,
                  let second = series.participants.dropFirst().first?.teamId else {
                return "Win/loss consequences are not established from the available series data."
            }
            let firstWins = wins[String(first)] ?? 0
            let secondWins = wins[String(second)] ?? 0
            if firstWins == required - 1, secondWins == required - 1 {
                return "Next game decides the series. The winner advances; the other team is eliminated."
            }
            if firstWins == required - 1 {
                return "A win by \(teamName(first)) advances. \(teamName(second)) must win to extend the series."
            }
            if secondWins == required - 1 {
                return "A win by \(teamName(second)) advances. \(teamName(first)) must win to extend the series."
            }
            return "A win adds one confirmed series win. Advancement is not yet determined."
        }
        return "Series winner: \(teamName(winner))."
    }

    private var nextDescription: String {
        guard let nextID = series.nextSlots?.first,
              let next = allSeries.first(where: { $0.id == nextID }) else {
            return "bracket slot not established"
        }
        return bracketLabel(next)
    }
}
