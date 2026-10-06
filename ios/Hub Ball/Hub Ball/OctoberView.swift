import SwiftUI

private enum OctoberSection: String, CaseIterable {
    case race = "Bracket"
    case history = "Statistics"
    case news = "Latest News"
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
    @State private var newsStore = PostseasonNewsStore(season: OctoberFeature.season)
    @State private var section: OctoberSection = .race
    @State private var historyGroup: PostseasonHistoryGroup = .hitting
    @State private var historyLeague: PostseasonHistoryLeague = .both
    @State private var historyTeamID: Int?
    @State private var historyCategoryKey = "ops"
    @State private var historyMinimumByGroup: [PostseasonHistoryGroup: Int] = [:]
    @State private var historySortColumn: PostseasonHistorySortColumn = .career
    @State private var historySortDescending = true
    @State private var selectedHistoryPlayer: PostseasonPlayerSelection?
    @State private var newsLeague: PostseasonHistoryLeague = .both
    @State private var selectedSeries: PostseasonSeries?
    @State private var selectedScorecardGame: PostseasonGame?
    private let historyMetricColumnWidth: CGFloat = 42
    private var historySampleColumnWidth: CGFloat { historyGroup == .hitting ? 24 : 34 }
    private let historyStatColumnSpacing: CGFloat = 2
    private func historyValueColumnWidth(showsSample: Bool, isSeason: Bool = false) -> CGFloat {
        (isSeason ? historySeasonMetricColumnWidth : historyMetricColumnWidth)
            + (showsSample ? historySampleColumnWidth + historyStatColumnSpacing : 0)
    }
    private let historyHeaderColor = Color(hubHex: "#647B90")
    private let historyTeamColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
    private let historyMinimumOptions = [0, 3, 5, 10, 15, 20]
    private var historyMinimum: Int { historyMinimumByGroup[historyGroup, default: 0] }
    private let historySeasonMetricColumnWidth: CGFloat = 56

    private var payload: PostseasonPayload? { store.snapshot }
    private var series: [PostseasonSeries] { payload?.series ?? [] }

    var body: some View {
        ZStack {
            AppColor.night.ignoresSafeArea()
            VStack(spacing: 0) {
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
                    } else if section == .news {
                        newsView
                    } else if let payload {
                        switch section {
                        case .race: raceView(payload)
                        case .history, .news: EmptyView()
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
            async let newsRefresh: Void = newsStore.refresh()
            _ = await (postseasonRefresh, historyRefresh, newsRefresh)
            while !Task.isCancelled, scenePhase == .active {
                if store.snapshot?.phase == "complete" { break }
                let delay = store.snapshot?.isLive == true ? 30.0 : 60.0
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, scenePhase == .active else { break }
                await store.refresh()
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-show-playoff-history") {
                section = .history
            } else if ProcessInfo.processInfo.arguments.contains("-show-playoff-news") {
                section = .news
            }
            #endif
        }
        .sheet(item: $selectedScorecardGame) { game in
            PostseasonScorecardSheet(game: game)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedSeries) { series in
            OctoberSeriesDetail(series: series, allSeries: self.series, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedHistoryPlayer) { selection in
            if let team = HubTeam.allCases.first(where: { $0.mlbID == selection.teamID }) {
                PostseasonPlayerCardSheet(team: team, playerID: selection.playerID)
            } else {
                ContentUnavailableView("Player card unavailable", systemImage: "person.crop.circle.badge.questionmark")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedHistoryPlayer = nil }
                        }
                    }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func raceView(_ payload: PostseasonPayload) -> some View {
        PlayoffBracketView(payload: payload, onSelect: { selectedSeries = $0 },
                          onSelectGame: { selectedScorecardGame = $0 })
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
            ProgressView("Loading postseason statistics…")
                .tint(AppColor.amber)
                .foregroundStyle(AppColor.bone)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Postseason statistics aren’t available yet.")
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Picker("Player group", selection: $historyGroup) {
                        ForEach(PostseasonHistoryGroup.allCases, id: \.self) { group in
                            Text(group.rawValue).tag(group)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: historyGroup) { _, group in
                        historyCategoryKey = group == .hitting ? "ops" : "wins"
                        historySortColumn = .career
                        historySortDescending = true
                    }

                    Picker("League", selection: $historyLeague) {
                        ForEach(PostseasonHistoryLeague.allCases, id: \.self) { league in
                            Text(league.rawValue).tag(league)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: historyLeague) { _, _ in historyTeamID = nil }
                }

                LazyVGrid(columns: historyTeamColumns, spacing: 6) {
                    ForEach(payload.teams) { team in
                        let selected = historyTeamID == team.teamId
                        let enabled = historyLeague == .both || historyLeague.rawValue == team.league
                        Button(historyTeamCode(team.abbreviation)) {
                            historyTeamID = selected ? nil : team.teamId
                        }
                        .font(AppFont.label)
                        .foregroundStyle(selected ? AppColor.night : AppColor.bone)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(selected ? AppColor.amber : AppColor.nightRaised, in: Capsule())
                        .opacity(enabled ? 1 : 0.4)
                        .disabled(!enabled)
                        .buttonStyle(.plain)
                        .accessibilityLabel(team.name)
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                        .accessibilityHint("Tap again to show all teams in this league")
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        historyStatisticControl(categories, selected: selected)
                        Spacer(minLength: 8)
                        historyMinimumPicker
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        historyStatisticControl(categories, selected: selected)
                        HStack(spacing: 0) {
                            Spacer(minLength: 8)
                            historyMinimumPicker
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let selected {
                    historyBoard(
                        sortedHistoryEntries(selected.entries, payload: payload),
                        category: selected,
                        season: payload.season
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .accessibilityIdentifier("playoffs.history")
        .refreshable { await historyStore.refresh() }
    }

    private func historyStatisticControl(
        _ categories: [PostseasonHistoryCategory],
        selected: PostseasonHistoryCategory?
    ) -> some View {
        HStack(spacing: 8) {
            Text("STATISTIC")
                .font(AppFont.label.weight(.bold))
                .foregroundStyle(AppColor.boneMuted)
            Menu {
                ForEach(categories) { category in
                    Button {
                        historyCategoryKey = category.key
                        historySortColumn = .career
                        historySortDescending = category.higherIsBetter
                    } label: {
                        if historyCategoryKey == category.key {
                            Label(category.label, systemImage: "checkmark")
                        } else {
                            Text(category.label)
                        }
                    }
                }
            } label: {
                historyMenuLabel(selected?.label ?? "Choose")
            }
            .accessibilityLabel("Statistic")
            .accessibilityValue(selected?.label ?? "None selected")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var historyMinimumPicker: some View {
        HStack(spacing: 6) {
            Text(historyGroup == .hitting ? "Minimum Plate Appearances" : "Minimum Innings")
                .font(AppFont.label)
                .foregroundStyle(AppColor.boneMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Menu {
                ForEach(historyMinimumOptions, id: \.self) { minimum in
                    Button {
                        historyMinimumByGroup[historyGroup] = minimum
                    } label: {
                        let title = minimum == 0 ? "0 (no minimum)" : String(minimum)
                        if historyMinimum == minimum {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            } label: {
                historyMenuLabel(String(historyMinimum))
                    .monospacedDigit()
            }
            .accessibilityIdentifier("playoffs.history.minimum")
            .accessibilityLabel("Minimum \(historyGroup.sampleUnit)")
            .accessibilityValue(historyMinimum == 0 ? "No minimum" : String(historyMinimum))
            .accessibilityHint("Filters the \(historySortColumn == .season ? "season" : "career") column. Zero shows all players.")
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func historyMenuLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(AppFont.bodySmall.weight(.semibold))
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppColor.amber)
        }
        .foregroundStyle(AppColor.bone)
        .frame(minWidth: 44, minHeight: 44)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColor.rule).frame(height: 1)
        }
    }

    @ViewBuilder
    private var newsView: some View {
        if let news = newsStore.snapshot {
            postseasonNews(news)
        } else if newsStore.isLoading {
            ProgressView("Finding the latest playoff reporting…")
                .tint(AppColor.amber)
                .foregroundStyle(AppColor.bone)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Latest playoff reporting isn’t available yet.")
                    .font(AppFont.displayMedium)
                Text("The bracket and historical rankings are still available.")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.boneDim)
                Button("Try again") { Task { await newsStore.refresh() } }
                    .buttonStyle(HubProminentButtonStyle())
                    .frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .foregroundStyle(AppColor.bone)
        }
    }

    private func postseasonNews(_ payload: PostseasonNewsPayload) -> some View {
        let articles = payload.articles.filter { article in
            switch newsLeague {
            case .both: true
            case .american: article.league == "AL"
            case .national: article.league == "NL"
            }
        }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("PAST \(payload.windowHours) HOURS")
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.amber)
                        Text("\(payload.articles.count) stories · \(payload.coveredTeamCount) of \(payload.teamCount) teams")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(AppColor.boneDim)
                    }
                    Spacer()
                    Picker("League", selection: $newsLeague) {
                        ForEach(PostseasonHistoryLeague.allCases, id: \.self) { league in
                            Text(league.rawValue).tag(league)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 190)
                }

                if articles.isEmpty {
                    Text("No \(newsLeague.rawValue == "Both" ? "" : newsLeague.rawValue + " ")stories were published in this window.")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(AppColor.boneDim)
                        .padding(.vertical, 24)
                } else {
                    ForEach(articles) { article in
                        postseasonNewsCard(article)
                    }
                }

                Text("Checked \(payload.generatedText) · All times ET · Headlines link to their publishers")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.boneDim)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .accessibilityIdentifier("playoffs.news")
        .refreshable { await newsStore.refresh() }
    }

    @ViewBuilder
    private func postseasonNewsCard(_ article: PostseasonNewsArticle) -> some View {
        if let url = URL.safeWeb(article.url) {
            Link(destination: url) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(article.source)
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.boneMuted)
                        Spacer(minLength: 8)
                        Text(article.publishedText)
                            .font(AppFont.label)
                            .monospacedDigit()
                            .foregroundStyle(AppColor.boneDim)
                            .multilineTextAlignment(.trailing)
                    }
                    Text("\(article.title) \(Image(systemName: "arrow.up.right.square"))")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.bone)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppColor.nightRaised)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AppColor.separator).frame(height: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(article.title), \(article.source), \(article.publishedText)\(article.publishedSource == "publisher" ? " Eastern Time" : "")")
        }
    }

    private func historyBoard(
        _ entries: [PostseasonHistoryEntry],
        category: PostseasonHistoryCategory,
        season: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: -4) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text("POSTSEASON")
                        .font(AppFont.label.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: historyValueColumnWidth(showsSample: false, isSeason: true) + historyValueColumnWidth(showsSample: true) + 8)
                }
                HStack(spacing: 8) {
                    Text("PLAYER")
                        .font(AppFont.label.weight(.bold))
                        .foregroundStyle(historyHeaderColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 22, alignment: .bottomLeading)
                    historySortButton(.season, title: String(season), category: category)
                    historySortButton(.career, title: "Career", category: category)
                }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(AppColor.rule).frame(height: 1) }

            if entries.isEmpty {
                Text(historyMinimum > 0
                     ? "No players meet the minimum of \(historyMinimum) \(historyGroup.sampleUnit) for \(historySortColumn == .season ? String(season) : "their postseason career") with these filters."
                     : "No postseason statistics for this selection yet.")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.boneDim)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Button {
                                    selectedHistoryPlayer = PostseasonPlayerSelection(playerID: entry.playerId, teamID: entry.teamId)
                                } label: {
                                    Text(entry.name)
                                        .font(AppFont.bodySmall.weight(.semibold))
                                        .foregroundStyle(AppColor.bone)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens player card")
                                Text(historyTeamCode(entry.teamAbbreviation))
                                    .font(AppFont.label)
                                    .foregroundStyle(AppColor.boneMuted)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            historyStatCell(entry.season, key: category.key, showsSample: false, isSeason: true)
                            historyStatCell(entry.career, key: category.key, showsSample: true)
                        }
                        .padding(.vertical, 5)
                        .overlay(alignment: .bottom) { Rectangle().fill(AppColor.rule).frame(height: 1) }
                    }
                }
            }
            Text(historyGroup == .hitting
                 ? "Career sample in parentheses: plate appearances (PA)."
                 : "Career sample in parentheses: innings pitched (IP).")
                .font(.caption2)
                .foregroundStyle(AppColor.boneMuted)
                .padding(.top, 8)
                .padding(.bottom, 4)
            if historyMinimum > 0 {
                Text("Minimum applies to the \(historySortColumn == .season ? String(season) : "Career") column.")
                    .font(.caption2)
                    .foregroundStyle(AppColor.boneMuted)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppColor.nightRaised)
    }

    private func historySortButton(
        _ column: PostseasonHistorySortColumn,
        title: String,
        category: PostseasonHistoryCategory
    ) -> some View {
        let active = historySortColumn == column
        let showsSample = column == .career
        let isSeason = column == .season
        return Button {
            if active {
                historySortDescending.toggle()
            } else {
                historySortColumn = column
                historySortDescending = category.higherIsBetter
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .foregroundStyle(historyHeaderColor)
                Image(systemName: active ? (historySortDescending ? "chevron.down" : "chevron.up") : "arrow.up.arrow.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(active ? AppColor.amber : historyHeaderColor)
            }
            .font(AppFont.label.weight(.bold))
            .frame(width: historyValueColumnWidth(showsSample: showsSample, isSeason: isSeason), height: 22, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(title) postseason statistics")
        .accessibilityValue(active ? (historySortDescending ? "Descending" : "Ascending") : "Not selected")
    }

    @ViewBuilder
    private func historyStatCell(_ stat: PostseasonHistoryStat?, key: String, showsSample: Bool, isSeason: Bool = false) -> some View {
        HStack(spacing: showsSample ? historyStatColumnSpacing : 0) {
            Text(stat.map { historyValue($0.value, key: key) } ?? "—")
                .font(.custom("Inter-Medium", size: 14, relativeTo: .body))
                .foregroundStyle(stat == nil ? AppColor.boneMuted : AppColor.bone)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: isSeason ? historySeasonMetricColumnWidth : historyMetricColumnWidth, alignment: .trailing)
            if showsSample {
                Text(stat.map { "(\(historySample($0)))" } ?? "")
                    .font(.custom("Inter-Medium", size: 11, relativeTo: .caption))
                    .foregroundStyle(AppColor.boneMuted)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: historySampleColumnWidth, alignment: .trailing)
            }
        }
        .frame(width: historyValueColumnWidth(showsSample: showsSample, isSeason: isSeason), alignment: .trailing)
    }

    private func sortedHistoryEntries(
        _ entries: [PostseasonHistoryEntry],
        payload: PostseasonHistoryPayload
    ) -> [PostseasonHistoryEntry] {
        let leagueByTeam = Dictionary(uniqueKeysWithValues: payload.teams.map { ($0.teamId, $0.league) })
        let filtered = historyLeague == .both
            ? entries
            : entries.filter { ($0.league ?? leagueByTeam[$0.teamId]) == historyLeague.rawValue }
        let teamEntries = historyTeamID.map { teamID in filtered.filter { $0.teamId == teamID } } ?? filtered
        let qualified = teamEntries.filter {
            $0.meetsMinimum(historyMinimum, group: historyGroup, column: historySortColumn)
        }
        return qualified.sorted { first, second in
            let firstValue = historySortColumn == .season ? first.season?.value : first.career?.value
            let secondValue = historySortColumn == .season ? second.season?.value : second.career?.value
            switch (firstValue, secondValue) {
            case let (a?, b?) where a != b:
                return historySortDescending ? a > b : a < b
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                let nameOrder = first.name.localizedStandardCompare(second.name)
                return nameOrder == .orderedSame ? first.playerId < second.playerId : nameOrder == .orderedAscending
            }
        }
    }

    private func historySample(_ stat: PostseasonHistoryStat) -> String {
        if let plateAppearances = stat.plateAppearances {
            return String(plateAppearances)
        }
        return stat.inningsPitched ?? "0.0"
    }

    private func historyTeamCode(_ abbreviation: String) -> String {
        switch abbreviation {
        case "TB": "TBR"
        case "SD": "SDP"
        default: abbreviation
        }
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
        let nextDate = upcoming.compactMap(\.calendarDateKey)
            .filter { $0 >= todayKey }.min()
        let next = upcoming.filter { $0.calendarDateKey == nextDate }
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
