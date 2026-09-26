import SwiftUI
import UIKit

private enum OctoberSection: String, CaseIterable {
    case race = "The Race"
    case tonight = "Tonight"
    case calls = "My Calls"
}

private enum OctoberLeague: String, CaseIterable {
    case american = "AL"
    case national = "NL"
    case final = "Final"
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
    @Environment(\.hubContentWidth) private var contentWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = PostseasonStore()
    @State private var section: OctoberSection = .race
    @State private var league: OctoberLeague = .american
    @State private var selectedSeries: PostseasonSeries?
    @State private var selectedTeamJourney: PostseasonClub?
    @State private var selectedCall: PostseasonSeries?

    private var payload: PostseasonPayload? { store.snapshot }
    private var series: [PostseasonSeries] { payload?.series ?? [] }
    private var widestLayout: Bool { contentWidth >= 700 }

    var body: some View {
        ZStack {
            AppColor.night.ignoresSafeArea()
            VStack(spacing: 0) {
                masthead
                Picker("October view", selection: $section) {
                    ForEach(OctoberSection.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Group {
                    if let payload {
                        switch section {
                        case .race: raceView(payload)
                        case .tonight: tonightView(payload)
                        case .calls: callsView(payload)
                        }
                    } else if store.isLoading {
                        ProgressView("Opening the October field…").tint(AppColor.amber)
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
            await store.refresh()
            while !Task.isCancelled, scenePhase == .active {
                guard store.snapshot?.isLive == true else { break }
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, scenePhase == .active else { break }
                await store.refresh()
            }
        }
        .sheet(item: $selectedSeries) { series in
            OctoberSeriesDetail(series: series, allSeries: self.series, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedTeamJourney) { team in
            OctoberTeamJourney(team: team, series: series)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedCall) { series in
            OctoberCallEditor(series: series, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("OCTOBER")
                    .font(AppFont.displayLarge)
                    .tracking(1.5)
                    .foregroundStyle(AppColor.bone)
                Spacer()
                if let checked = payload?.checkedDate {
                    Text(store.isDelayed ? "DELAYED UPDATES" : "CHECKED \(checked.formatted(date: .omitted, time: .shortened))")
                        .font(AppFont.label)
                        .foregroundStyle(store.isDelayed || store.refreshFailed ? AppColor.amber : AppColor.boneMuted)
                }
            }
            Text("TWELVE TEAMS. ONE ENDING.")
                .font(AppFont.label)
                .tracking(1.1)
                .foregroundStyle(AppColor.boneMuted)
            if store.refreshFailed {
                HStack {
                    Text("Saved data · Updates unavailable")
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.amber)
                    Spacer()
                    Button("Retry") { Task { await store.refresh() } }
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.bone)
                        .frame(minHeight: 44)
                }
            } else if store.isDelayed {
                Text("Saved live snapshot · Updates may be delayed")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.amber)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.nightRaised)
    }

    private func raceView(_ payload: PostseasonPayload) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                raceHero(payload)
                if !widestLayout {
                    Picker("League", selection: $league) {
                        ForEach(OctoberLeague.allCases, id: \.self) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)
                } else {
                    Text("AMERICAN + NATIONAL LEAGUES")
                        .font(AppFont.label)
                        .tracking(1.2)
                        .foregroundStyle(AppColor.boneMuted)
                }
                Text(league == .final && !widestLayout
                     ? "CHAMPIONSHIP ROUTE"
                     : "CURRENT ROUND · \(roundTitle(currentRound(in: payload) ?? "wild-card").uppercased())")
                    .font(AppFont.label)
                    .tracking(1.2)
                    .foregroundStyle(AppColor.boneMuted)
                let currentRound = currentRound(in: payload)
                let visible = series.filter {
                    ($0.round == currentRound || (!widestLayout && league == .final && $0.round == "world-series"))
                        && (league == .final && !widestLayout || raceLeagueFilter($0))
                }
                let potential = series.filter {
                    league != .final && roundRank($0.round) > roundRank(currentRound ?? "wild-card") && raceLeagueFilter($0)
                }
                let completed = series.filter {
                    league != .final && roundRank($0.round) < roundRank(currentRound ?? "wild-card") && raceLeagueFilter($0)
                }
                if visible.isEmpty {
                    Text("The bracket slot is still taking shape. We’ll fill the path when the schedule establishes it.")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.boneDim)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColor.nightRaised)
                } else { seriesGrid(visible) }
                if !potential.isEmpty {
                    DisclosureGroup("Potential later rounds · \(potential.count) series") {
                        seriesGrid(potential)
                    }
                    .font(AppFont.bodySmall.weight(.semibold))
                    .foregroundStyle(AppColor.bone)
                    .tint(AppColor.amber)
                    .padding(14)
                    .background(AppColor.nightRaised)
                }
                if !completed.isEmpty {
                    DisclosureGroup("Completed earlier rounds · \(completed.count) series") {
                        seriesGrid(completed)
                    }
                    .font(AppFont.bodySmall.weight(.semibold))
                    .foregroundStyle(AppColor.bone)
                    .tint(AppColor.amber)
                    .padding(14)
                    .background(AppColor.nightRaised)
                }
                Label("A light marks a confirmed series win. Team names and win counts carry the meaning without color.", systemImage: "lightbulb.fill")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.boneMuted)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .refreshable { await store.refresh() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ordered postseason bracket")
    }

    private func raceHero(_ payload: PostseasonPayload) -> some View {
        let eliminated = Set(payload.series.filter { $0.state == "complete" }
            .flatMap { item in item.participants.filter { $0.teamId != item.winnerTeamId }.compactMap(\.teamId) })
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(payload.phase == "field-setting"
                         ? "THE FIELD IS FORMING"
                         : payload.phase == "complete" ? "THE TITLE IS DECIDED" : "THE ROAD TO THE TITLE")
                        .font(AppFont.displayMedium)
                        .foregroundStyle(AppColor.bone)
                    Text(championName(in: payload).map { "Champion · \($0)" }
                         ?? (payload.phase == "field-setting"
                             ? "12 places · qualification still being confirmed"
                             : "\(eliminated.count) eliminated · 12 team slots"))
                        .font(AppFont.bodySmall)
                        .foregroundStyle(AppColor.boneDim)
                }
                Spacer(minLength: 12)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppColor.amber)
                    .accessibilityHidden(true)
            }
            OctoberRouteGlyph(series: series, reduceMotion: reduceMotion)
                .frame(height: 72)
                .accessibilityHidden(true)
            HStack {
                Text("ROOTING FOR")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.boneMuted)
                Menu {
                    Button("Watch the whole field") { store.setRootingTeam(nil) }
                    ForEach(rootingChoices, id: \.teamId) { club in
                        Button(club.name ?? "Team") { if let id = club.teamId { store.setRootingTeam(id) } }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(rootingName)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(AppFont.bodySmall.weight(.semibold))
                    .foregroundStyle(AppColor.amber)
                    .frame(minHeight: 44)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(AppColor.nightRaised)
        .overlay(alignment: .leading) { Rectangle().fill(AppColor.amber).frame(width: 3) }
    }

    private var rootingChoices: [PostseasonClub] {
        let all = series.flatMap(\.participants).filter(\.resolved)
        return Dictionary(grouping: all, by: \.teamId).compactMap { $0.value.first }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private var rootingName: String {
        guard let id = store.selectedRootingTeamID else { return "Whole field" }
        return rootingChoices.first(where: { $0.teamId == id })?.name ?? "Choose a team"
    }

    private func seriesRoute(_ item: PostseasonSeries) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(roundTitle(item.round).uppercased())
                    .font(AppFont.label)
                    .tracking(0.8)
                    .foregroundStyle(AppColor.boneMuted)
                Spacer()
                Text(item.league ?? "BRACKET SLOT")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.amber)
            }
            ForEach(item.participants) { participant in
                Button { selectedTeamJourney = participant } label: {
                    clubLine(participant, wins: participant.teamId.flatMap { item.wins(for: $0) })
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this team’s postseason journey")
            }
            ForEach(item.unresolvedSlots, id: \.self) { slot in
                HStack(spacing: 8) {
                    Circle().fill(AppColor.boneMuted.opacity(0.45)).frame(width: 8, height: 8)
                    Text(slot).font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
                    Spacer()
                    Text("SLOT").font(AppFont.label).foregroundStyle(AppColor.boneMuted)
                }
                .frame(minHeight: 28)
            }
            HStack {
                Text(seriesStateLabel(item))
                    .font(AppFont.label)
                    .foregroundStyle(item.state == "live" ? AppColor.amber : AppColor.boneMuted)
                Spacer()
                Text(item.requiredWins.map { "FIRST TO \($0)" } ?? "RESULT UNKNOWN")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.boneMuted)
            }
            .padding(.top, 2)
            Button("SERIES DETAILS") { selectedSeries = item }
                .font(AppFont.label)
                .foregroundStyle(AppColor.boneMuted)
                .frame(minHeight: 44, alignment: .leading)
        }
        .padding(14)
        .background(AppColor.nightRaised)
        .overlay(alignment: .top) { Rectangle().fill(seriesAccent(item)).frame(height: 2) }
        .contentShape(Rectangle())
    }

    private func clubLine(_ club: PostseasonClub, wins: Int?) -> some View {
        let tint = club.teamId.flatMap(teamColor) ?? AppColor.boneMuted
        return HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(club.name ?? club.slot ?? "Team to be determined")
                .font(AppFont.bodySmall.weight(.semibold))
                .foregroundStyle(club.resolved ? AppColor.bone : AppColor.boneDim)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let wins {
                HStack(spacing: 3) {
                    ForEach(0..<min(wins, 4), id: \.self) { _ in Image(systemName: "lightbulb.fill") }
                    Text("\(wins)").monospacedDigit()
                }
                .font(AppFont.label)
                .foregroundStyle(AppColor.amber)
                .accessibilityLabel("\(wins) confirmed series wins")
            } else {
                Text("· · ·").font(AppFont.label).foregroundStyle(AppColor.boneMuted)
            }
        }
        .frame(minHeight: 34)
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

    private func tonightCard(_ game: PostseasonGame, payload: PostseasonPayload) -> some View {
        let localDate = game.startDate
        let associated = game.seriesId.flatMap { id in series.first(where: { $0.id == id }) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(associated.map { roundTitle($0.round) } ?? "POSTSEASON")
                    .font(AppFont.label).foregroundStyle(AppColor.amber)
                Spacer()
                Text(game.timeTBD || localDate == nil ? "TIME TBD" : localDate!.formatted(date: .abbreviated, time: .shortened))
                    .font(AppFont.label).foregroundStyle(AppColor.boneMuted)
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

    private func callsView(_ payload: PostseasonPayload) -> some View {
        let established = series.filter {
            $0.participants.count == 2 && $0.requiredWins != nil
                && ($0.state != "complete" || store.call(for: $0) != nil)
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MY CALLS").font(AppFont.displayMedium).foregroundStyle(AppColor.bone)
                    Text("A call stays on this device. A fresh entry opens for every new series.")
                        .font(AppFont.bodySmall).foregroundStyle(AppColor.boneMuted)
                }
                if established.isEmpty {
                    Text("Calls open when both teams in a series are established.")
                        .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(AppColor.nightRaised)
                }
                ForEach(established) { item in
                    Button { selectedCall = item } label: { callRow(item) }
                        .buttonStyle(.plain)
                        .disabled(!store.mayEdit(item) && store.call(for: item) == nil)
                }
                championPicker
            }
            .padding(14)
        }
    }

    private func callRow(_ item: PostseasonSeries) -> some View {
        let existing = store.call(for: item)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(roundTitle(item.round)).font(AppFont.label).foregroundStyle(AppColor.boneMuted)
                Spacer()
                Text(existing?.outcome == "correct" ? "CALLED IT" : existing?.outcome == "missed" ? "OCTOBER HAD OTHER PLANS" : existing?.entryCategory.uppercased() ?? "MAKE A CALL")
                    .font(AppFont.label).foregroundStyle(AppColor.amber)
            }
            Text(item.participants.compactMap(\.name).joined(separator: "  ·  "))
                .font(AppFont.body.weight(.semibold)).foregroundStyle(AppColor.bone)
            if let existing {
                Text("Pick: \(teamName(existing.winnerTeamID)) in \(existing.seriesLength) · \(existing.entryCategory == "pre-series" ? "Pre-series" : "From here")\(existing.exactLength == true ? " · Exact length" : "")")
                    .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
            } else {
                Text("Pick the series winner and length")
                    .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColor.nightRaised)
        .overlay(alignment: .top) { Rectangle().fill(AppColor.rule).frame(height: 1) }
        .contentShape(Rectangle())
    }

    private var championPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHAMPION CALL · OPTIONAL").font(AppFont.label).foregroundStyle(AppColor.boneMuted)
            Menu {
                Button("No champion call") { store.saveChampion(nil) }
                ForEach(rootingChoices, id: \.teamId) { club in
                    Button(club.name ?? "Team") { if let id = club.teamId { store.saveChampion(id) } }
                }
            } label: {
                Label(store.calls.championTeamID.map(teamName) ?? "Choose a champion", systemImage: "trophy")
                    .font(AppFont.bodySmall.weight(.semibold))
                    .foregroundStyle(AppColor.amber)
                    .frame(minHeight: 44)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.nightRaised)
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

    private func leagueFilter(_ series: PostseasonSeries) -> Bool {
        switch league {
        case .american: series.league == "AL"
        case .national: series.league == "NL"
        case .final: series.league == "MLB"
        }
    }

    private func raceLeagueFilter(_ item: PostseasonSeries) -> Bool {
        if widestLayout { return item.league == "AL" || item.league == "NL" || item.league == "MLB" }
        return leagueFilter(item)
    }

    private func seriesGrid(_ items: [PostseasonSeries]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: widestLayout ? 2 : 1), spacing: 12) {
            ForEach(items) { item in
                seriesRoute(item)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(accessibleSeries(item))
            }
        }
    }

    private func currentRound(in payload: PostseasonPayload) -> String? {
        let games = payload.games
        let live = games.first(where: { $0.abstractState == "Live" })
        if let live, let id = live.seriesId, let match = series.first(where: { $0.id == id }) { return match.round }
        let today = DateFormatter()
        today.calendar = Calendar(identifier: .gregorian)
        today.timeZone = TimeZone(identifier: "America/New_York")
        today.dateFormat = "yyyy-MM-dd"
        let todayKey = today.string(from: Date())
        let upcoming = games.filter { ["Preview", "Scheduled"].contains($0.abstractState) && ($0.gameDate?.prefix(10).description ?? "") >= todayKey }
            .min { ($0.gameDate ?? "") < ($1.gameDate ?? "") }
        if let upcoming, let id = upcoming.seriesId, let match = series.first(where: { $0.id == id }) { return match.round }
        let final = games.filter { $0.abstractState == "Final" }.max { ($0.gameDate ?? "") < ($1.gameDate ?? "") }
        if let final, let id = final.seriesId, let match = series.first(where: { $0.id == id }) { return match.round }
        return series.first?.round
    }

    private func roundRank(_ round: String) -> Int {
        ["wild-card": 0, "division-series": 1, "league-championship": 2, "world-series": 3][round] ?? 4
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

    private func seriesStateLabel(_ item: PostseasonSeries) -> String {
        if item.state == "scheduled", let payload,
           roundRank(item.round) > roundRank(currentRound(in: payload) ?? "wild-card") {
            return "POTENTIAL SERIES"
        }
        return switch item.state {
        case "live": "IN PROGRESS"
        case "complete": "SERIES COMPLETE"
        case "unknown": "RESULT UNDER REVIEW"
        default: "AWAITING FIRST PITCH"
        }
    }

    private func seriesAccent(_ item: PostseasonSeries) -> Color {
        if item.state == "live" { return AppColor.amber }
        return item.participants.first?.teamId.flatMap(teamColor) ?? AppColor.rule
    }

    private func teamColor(_ teamID: Int) -> Color? {
        guard let team = HubTeam.allCases.first(where: { $0.mlbID == teamID }) else { return nil }
        return Color(hubHex: team.definition.colors.teamTint)
    }

    private func teamName(_ teamID: Int) -> String {
        HubTeam.allCases.first(where: { $0.mlbID == teamID })?.fullName ?? "Team"
    }

    private func championName(in payload: PostseasonPayload) -> String? {
        guard payload.phase == "complete",
              let winner = payload.series.first(where: { $0.round == "world-series" })?.winnerTeamId else { return nil }
        return teamName(winner)
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

    private func accessibleSeries(_ item: PostseasonSeries) -> String {
        let teams = item.participants.map { $0.name ?? $0.slot ?? "Team to be determined" }.joined(separator: " versus ")
        return "\(roundTitle(item.round)), \(teams), \(seriesStateLabel(item)). Tap for series details."
    }
}

private struct OctoberRouteGlyph: View {
    let series: [PostseasonSeries]
    let reduceMotion: Bool
    @State private var openingProgress = 0.0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let confirmed = series.reduce(0) { $0 + ($1.wins?.values.reduce(0, +) ?? 0) }
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 4, y: 55))
                    path.addCurve(to: CGPoint(x: width * 0.48, y: 26), control1: CGPoint(x: width * 0.18, y: 6), control2: CGPoint(x: width * 0.3, y: 73))
                    path.addCurve(to: CGPoint(x: width - 31, y: 26), control1: CGPoint(x: width * 0.66, y: -8), control2: CGPoint(x: width * 0.8, y: 60))
                }
                .trim(from: 0, to: openingProgress)
                .stroke(AppColor.boneMuted.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 6]))
                ForEach(0..<12, id: \.self) { index in
                    let x = CGFloat(index) * (width - 36) / 11 + 5
                    let y = CGFloat(42 + sin(Double(index) * .pi / 5) * 12)
                    Circle().fill(index < min(confirmed, 12) ? AppColor.amber : AppColor.nightCell)
                        .frame(width: index < min(confirmed, 12) ? 10 : 7, height: index < min(confirmed, 12) ? 10 : 7)
                        .overlay(Circle().stroke(AppColor.boneMuted.opacity(0.55), lineWidth: 1))
                        .position(x: x, y: y)
                }
                Image(systemName: "sparkle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppColor.amber)
                    .position(x: width - 14, y: 25)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.8), value: confirmed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.95), value: openingProgress)
            .onAppear { openingProgress = 1 }
        }
    }
}

private struct OctoberSeriesDetail: View {
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

private struct OctoberTeamJourney: View {
    let team: PostseasonClub
    let series: [PostseasonSeries]

    private var journey: [PostseasonSeries] {
        series.filter { item in item.participants.contains(where: { $0.teamId == team.teamId }) }
            .sorted { roundOrder($0.round) < roundOrder($1.round) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(team.name ?? team.slot ?? "Team to be determined")
                        .font(AppFont.displayMedium).foregroundStyle(AppColor.bone)
                    if journey.isEmpty {
                        Text("This bracket slot has not been established yet.")
                            .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
                    }
                    ForEach(journey) { item in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(item.round.replacingOccurrences(of: "-", with: " ").uppercased())
                                Spacer()
                                Text(item.state.uppercased())
                            }
                            .font(AppFont.label).foregroundStyle(AppColor.boneMuted)
                            HStack {
                                Text("Series score")
                                Spacer()
                                Text(item.wins(for: team.teamId ?? -1).map(String.init) ?? "Unknown")
                                    .foregroundStyle(AppColor.amber)
                            }
                            .font(AppFont.bodySmall).foregroundStyle(AppColor.bone)
                            Text(teamConsequences(in: item))
                                .font(AppFont.bodySmall).foregroundStyle(AppColor.boneDim)
                            Text("Next: \(nextDescription(for: item))")
                                .font(AppFont.bodySmall).foregroundStyle(AppColor.boneMuted)
                        }
                        .padding(14)
                        .background(AppColor.nightRaised)
                    }
                }
                .padding(18)
            }
            .background(AppColor.night.ignoresSafeArea())
            .navigationTitle("Team Journey")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private func teamConsequences(in item: PostseasonSeries) -> String {
        guard let required = item.requiredWins, let teamID = team.teamId,
              let wins = item.wins else { return "Win/loss consequences are not established from the available series data." }
        let ownWins = wins[String(teamID)] ?? 0
        let opponentWins = item.participants.first(where: { $0.teamId != teamID })?.teamId
            .flatMap { wins[String($0)] } ?? 0
        if item.winnerTeamId == teamID { return "Series winner. This path advances." }
        if item.winnerTeamId != nil { return "Eliminated in this series. The completed path remains in the record." }
        if ownWins == required - 1, opponentWins == required - 1 { return "Win: advance. Loss: eliminated." }
        if ownWins == required - 1 { return "A win advances. A loss lets the opponent continue." }
        if opponentWins == required - 1 { return "A loss eliminates this team. A win keeps the series alive." }
        return "The series continues; neither team can clinch with one win."
    }

    private func roundOrder(_ round: String) -> Int {
        ["wild-card": 0, "division-series": 1, "league-championship": 2, "world-series": 3][round] ?? 4
    }

    private func nextDescription(for item: PostseasonSeries) -> String {
        guard let nextID = item.nextSlots?.first,
              let next = series.first(where: { $0.id == nextID }) else {
            return "bracket slot not established"
        }
        return bracketLabel(next)
    }
}

private struct OctoberCallEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var winnerID: Int?
    @State private var length = 4
    @State private var shareItems: [Any] = []
    @State private var sharing = false
    let series: PostseasonSeries
    let store: PostseasonStore

    private var requiredWins: Int { series.requiredWins ?? 2 }
    private var possibleLengths: [Int] { (requiredWins...(requiredWins * 2 - 1)).map { $0 } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("PICK A SIDE")
                    .font(AppFont.displayMedium).foregroundStyle(AppColor.bone)
                ForEach(series.participants) { participant in
                    Button {
                        winnerID = participant.teamId
                        if length < requiredWins { length = requiredWins }
                    } label: {
                        HStack {
                            Text(participant.name ?? participant.slot ?? "Team")
                            Spacer()
                            if winnerID == participant.teamId { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColor.amber) }
                        }
                        .font(AppFont.body.weight(.semibold)).foregroundStyle(AppColor.bone)
                        .padding(14).background(AppColor.nightRaised)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .disabled(!store.mayEdit(series) && store.call(for: series) != nil)
                }
                Picker("Series length", selection: $length) {
                    ForEach(possibleLengths, id: \.self) { games in Text("In \(games)").tag(games) }
                }
                .pickerStyle(.segmented)
                .tint(AppColor.amber)
                .disabled(!store.mayEdit(series) && store.call(for: series) != nil)
                if let winnerID {
                    Text("A call is a prediction. It does not change who you are rooting for.")
                        .font(AppFont.bodySmall).foregroundStyle(AppColor.boneMuted)
                    Button(store.mayEdit(series) ? "Save and share my call" : "Share my call") {
                        if store.mayEdit(series) {
                            store.saveCall(series: series, winner: winnerID, length: length)
                        }
                        prepareShare(winnerID: winnerID)
                    }
                    .buttonStyle(HubProminentButtonStyle())
                    .frame(minHeight: 44)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(AppColor.night.ignoresSafeArea())
            .navigationTitle("My Call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(AppColor.bone) } }
            .sheet(isPresented: $sharing) { OctoberActivitySheet(items: shareItems) }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let existing = store.call(for: series) {
                winnerID = existing.winnerTeamID
                length = existing.seriesLength
            } else {
                winnerID = series.participants.first?.teamId
                length = requiredWins
            }
        }
    }

    @MainActor
    private func prepareShare(winnerID: Int) {
        let winner = teamName(winnerID)
        let round = series.round.replacingOccurrences(of: "-", with: " ").capitalized
        let webURL = URL(string: "https://red-sox.netlify.app/october/")!
        let savedCall = store.call(for: series)
        let outcome = savedCall?.outcome == "correct" ? "CALLED IT" : savedCall?.outcome == "missed" ? "OCTOBER HAD OTHER PLANS" : nil
        let color = HubTeam.allCases.first(where: { $0.mlbID == winnerID })?.definition.colors.teamTint ?? "#E8A33D"
        let ticket = OctoberTicketCard(
            winner: winner,
            round: round,
            length: length,
            outcome: outcome,
            exactLength: savedCall?.exactLength == true,
            teamColor: Color(hubHex: color)
        )
        let renderer = ImageRenderer(content: ticket.frame(width: 1080, height: 1350))
        renderer.scale = 1
        guard let image = renderer.uiImage else { return }
        let message = outcome.map { "\($0): I picked \(winner) in \(length) in the \(round). Your turn." }
            ?? "I called \(winner) in \(length) in the \(round). I called it. Your turn."
        shareItems = [image, message, webURL]
        sharing = true
    }

    private func teamName(_ id: Int) -> String {
        HubTeam.allCases.first(where: { $0.mlbID == id })?.fullName ?? "Team"
    }
}

private struct OctoberTicketCard: View {
    let winner: String
    let round: String
    let length: Int
    let outcome: String?
    let exactLength: Bool
    let teamColor: Color

    var body: some View {
        ZStack {
            AppColor.night
            VStack(alignment: .leading, spacing: 34) {
                HStack {
                    Text("HUB BALL").font(.custom("BarlowCondensed-SemiBold", size: 42)).tracking(4)
                    Spacer()
                    Text(Date.now.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.custom("Inter-Regular", size: 24).monospacedDigit())
                }
                Rectangle().fill(teamColor).frame(height: 4)
                VStack(alignment: .leading, spacing: 14) {
                    Text(outcome ?? "MY OCTOBER CALL")
                        .font(.custom("Inter-Medium", size: 25)).tracking(3)
                        .foregroundStyle(AppColor.boneMuted)
                    Text(winner.uppercased())
                        .font(.custom("BarlowCondensed-SemiBold", size: 100))
                        .minimumScaleFactor(0.62).lineLimit(2)
                        .foregroundStyle(AppColor.bone)
                    Text("TO WIN THE \(round.uppercased())")
                        .font(.custom("Inter-Regular", size: 29)).tracking(1.5)
                    Text("IN \(length) GAMES")
                        .font(.custom("Inter-Medium", size: 34).monospacedDigit())
                        .foregroundStyle(teamColor)
                    if exactLength {
                        Text("EXACT LENGTH · BONUS BADGE")
                            .font(.custom("Inter-Medium", size: 22))
                            .tracking(1.4)
                            .foregroundStyle(AppColor.amber)
                    }
                }
                Spacer()
                    Text("I CALLED IT. YOUR TURN.")
                    .font(.custom("BarlowCondensed-SemiBold", size: 36)).tracking(1.2)
                Text("HUB BALL · BASEBALL AFTER DARK")
                    .font(.custom("Inter-Regular", size: 20)).tracking(2)
                    .foregroundStyle(AppColor.boneMuted)
            }
            .foregroundStyle(AppColor.bone)
            .padding(62)
        }
    }
}

private struct OctoberActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
