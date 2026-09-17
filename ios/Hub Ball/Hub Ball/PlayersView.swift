import SwiftUI

struct PlayersView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @State private var store: PlayersStore
    @State private var path: [Int] = []

    let team: HubTeam
    let requestedPlayerID: Int?
    let onRequestHandled: () -> Void

    init(team: HubTeam, requestedPlayerID: Int? = nil, onRequestHandled: @escaping () -> Void = {}) {
        self.team = team
        _store = State(initialValue: PlayersStore(team: team))
        self.requestedPlayerID = requestedPlayerID
        self.onRequestHandled = onRequestHandled
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let feed = store.feed {
                    directory(feed)
                } else if store.isLoading {
                    ProgressView("Loading players…")
                        .tint(AppColor.steel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    errorView
                }
            }
            .background(AppColor.night)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Int.self) { playerID in
                if let player = store.player(id: playerID) {
                    PlayerReferenceView(team: team, player: player, source: store.feed?.source, store: store)
                } else {
                    ContentUnavailableView("Player unavailable", systemImage: "person.crop.circle.badge.questionmark")
                }
            }
        }
        .task {
            await store.load()
            openRequestedPlayerIfAvailable()
        }
        .onChange(of: requestedPlayerID) { _, _ in openRequestedPlayerIfAvailable() }
    }

    private func directory(_ feed: PlayersFeed) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                searchField
                filterBar
                spreadsheetHeader
                if store.visiblePlayers.isEmpty {
                    ContentUnavailableView.search(text: store.searchText)
                        .frame(minHeight: 280)
                } else {
                    ForEach(store.visiblePlayers) { player in
                        NavigationLink(value: player.id) {
                            spreadsheetRow(player)
                        }
                        .buttonStyle(.plain)
                    }
                }
                sourceFooter(feed.source)
            }
            .padding(.bottom, 20)
        }
        .refreshable { await store.load() }
        .background(AppColor.night)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.steel)
            TextField("Search players", text: $store.searchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundStyle(AppColor.bone)
                .tint(AppColor.steel)
        }
        .font(AppFont.bodySmall)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(AppColor.nightRaised)
        .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(PlayerPositionFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { store.filter = filter }
                    } label: {
                        Text(filter.title)
                            .font(AppFont.label.weight(.semibold))
                            .foregroundStyle(store.filter == filter ? AppColor.bone : AppColor.boneMuted)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(store.filter == filter ? AppColor.nightCell : AppColor.nightRaised)
                            .overlay(alignment: .bottom) {
                                if store.filter == filter {
                                    Rectangle().fill(AppColor.amber).frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.filter == filter ? .isSelected : [])
                }
            }
            .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var spreadsheetHeader: some View {
        HStack(spacing: 0) {
            sortHeader(.number, width: 42, alignment: .leading)
            sortHeader(.name, width: contentWidth >= 520 ? 240 : 200, alignment: .leading)
            sortHeader(.position, width: 48, alignment: .leading)
            sortHeader(.batsThrows, width: 48, alignment: .leading)
            if contentWidth >= 520 { sortHeader(.age, width: 40, alignment: .leading) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 33)
        .padding(.horizontal, 16)
        .background(AppColor.nightRaised)
        .overlay(alignment: .top) { Rectangle().fill(AppColor.rule).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(AppColor.rule).frame(height: 1) }
    }

    private func sortHeader(_ column: PlayerDirectorySort, width: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        Button { store.toggleSort(column) } label: {
            HStack(spacing: 3) {
                Text(column.title.uppercased())
                if store.sort == column {
                    Image(systemName: store.sortsAscending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .font(AppFont.label.weight(.semibold))
            .foregroundStyle(store.sort == column ? AppColor.bone : AppColor.boneMuted)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(column.title)")
    }

    private func spreadsheetRow(_ player: RedSoxPlayer) -> some View {
        HStack(spacing: 0) {
            Text(player.number ?? "—")
                .font(AppFont.number.monospacedDigit())
                .foregroundStyle(AppColor.boneDim)
                .frame(width: 42, alignment: .leading)
            Text(player.name)
                .font(AppFont.bodySmall.weight(.medium))
                .foregroundStyle(AppColor.bone)
                .lineLimit(1)
                .frame(width: contentWidth >= 520 ? 240 : 200, alignment: .leading)
            Text(player.position.abbreviation)
                .font(AppFont.label.monospaced())
                .foregroundStyle(AppColor.boneDim)
                .frame(width: 48, alignment: .leading)
            Text("\(player.bats?.shortHand ?? "—")/\(player.throws?.shortHand ?? "—")")
                .font(AppFont.label.monospaced())
                .foregroundStyle(AppColor.boneDim)
                .frame(width: 48, alignment: .leading)
            if contentWidth >= 520 {
                Text(player.age.map(String.init) ?? "—")
                    .font(AppFont.label.monospacedDigit())
                    .foregroundStyle(AppColor.boneDim)
                    .frame(width: 40, alignment: .leading)
            }
        }
        .frame(minHeight: 40)
        .padding(.horizontal, 16)
        .background(AppColor.night)
        .overlay(alignment: .bottom) { Rectangle().fill(AppColor.rule).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(player.name), number \(player.number ?? "unassigned"), \(player.position.name), bats \(player.bats ?? "unavailable"), throws \(player.throws ?? "unavailable")")
        .accessibilityHint("Opens career card")
    }

    private func sourceFooter(_ source: PlayersSource) -> some View {
        Text(source.attribution)
            .font(AppFont.label)
            .foregroundStyle(AppColor.boneMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }

    private func openRequestedPlayerIfAvailable() {
        guard let requestedPlayerID, store.player(id: requestedPlayerID) != nil else { return }
        path = [requestedPlayerID]
        onRequestHandled()
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Players Unavailable", systemImage: "person.3.fill")
        } description: {
            Text(store.errorMessage ?? "The roster could not be loaded.")
        } actions: {
            Button("Try Again") { Task { await store.load() } }
                .buttonStyle(HubProminentButtonStyle())
                .tint(AppColor.amber)
        }
        .foregroundStyle(AppColor.bone)
    }
}

private enum PlayerRecordMode: String, CaseIterable, Identifiable {
    case batting
    case pitching

    var id: String { rawValue }
    var title: String { self == .batting ? "Batting" : "Pitching" }
}

private enum CareerScope: String, CaseIterable, Identifiable {
    case mlb = "MLB"
    case league = "Minor League"
    case both = "Both"

    var id: String { rawValue }
}

private struct PlayerReferenceView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @Environment(\.dismiss) private var dismiss
    let team: HubTeam
    let player: RedSoxPlayer
    let source: PlayersSource?
    let store: PlayersStore
    @State private var mode: PlayerRecordMode
    @State private var scope: CareerScope = .mlb

    init(team: HubTeam, player: RedSoxPlayer, source: PlayersSource?, store: PlayersStore) {
        self.team = team
        self.player = player
        self.source = source
        self.store = store
        _mode = State(initialValue: player.positionFilter == .pitcher ? .pitching : .batting)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                biographyPanel
                careerPanel
                if !player.education.entries.isEmpty { educationPanel }
                sourcePanel
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .background(AppColor.night)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.bone)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Back to players")
            }
            ToolbarItem(placement: .principal) {
                playerNavigationTitle
            }
        }
        .task { await store.loadCareer(for: player) }
    }

    private var biographyPanel: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 9) {
            GridRow {
                bioValue("BATS", player.bats ?? "—")
                bioValue("THROWS", player.throws ?? "—")
                bioValue("BORN", player.formattedShortDate(player.birthDate) ?? "—")
            }
            GridRow {
                bioValue("BIRTHPLACE", player.birthplace.isEmpty ? "—" : player.birthplace)
                bioValue("MLB DEBUT", player.formattedShortDate(player.debutDate) ?? "—")
                bioValue("STATUS", player.rosterStatus)
            }
        }
        .padding(14)
        .background(AppColor.nightRaised)
        .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
    }

    @ViewBuilder
    private func bioValue(_ label: String, _ value: String) -> some View {
        if contentWidth < 460 {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppFont.label.weight(.semibold))
                    .foregroundStyle(AppColor.boneMuted)
                Text(value)
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.boneDim)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(AppFont.label.weight(.semibold))
                    .foregroundStyle(AppColor.boneMuted)
                    .frame(width: 74, alignment: .leading)
                Text(value)
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.boneDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var playerNavigationTitle: some View {
        HStack(spacing: 12) {
            Text(player.number ?? "—")
                .font(.custom("Inter-Medium", size: 24).monospacedDigit())
                .foregroundStyle(AppColor.amber)
            Text(player.fullName ?? player.name)
                .font(.custom("BarlowCondensed-SemiBold", size: 27))
                .foregroundStyle(AppColor.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(player.position.abbreviation)
                .font(.custom("Inter-Medium", size: 24).monospaced())
                .foregroundStyle(AppColor.boneDim)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var careerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasBothRecords { recordModePicker }
            scopePicker

            if let career = store.career(for: player) {
                careerTable(career)
                careerFooter(career)
            } else if store.isLoadingCareer(for: player) {
                HStack(spacing: 8) {
                    ProgressView().tint(AppColor.steel)
                    Text("Loading career record…")
                }
                .font(AppFont.bodySmall)
                .foregroundStyle(AppColor.boneDim)
                .padding(16)
            } else {
                unavailableCareer
            }
        }
        .background(AppColor.nightRaised)
        .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
    }

    private var hasBothRecords: Bool {
        if let career = store.career(for: player) {
            return !career.battingRows.isEmpty && !career.pitchingRows.isEmpty
        }
        return player.careerStats?.batting != nil && player.careerStats?.pitching != nil
    }

    private var recordModePicker: some View {
        HStack(spacing: 0) {
            ForEach(PlayerRecordMode.allCases) { option in
                Button { mode = option } label: {
                    Text(option.title)
                        .font(AppFont.label.weight(.semibold))
                        .foregroundStyle(mode == option ? AppColor.bone : AppColor.boneMuted)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(mode == option ? AppColor.nightCell : AppColor.night)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private var scopePicker: some View {
        HStack(spacing: 6) {
            ForEach(CareerScope.allCases) { option in
                Button { scope = option } label: {
                    Text(option.rawValue)
                        .font(AppFont.label)
                        .foregroundStyle(scope == option ? AppColor.bone : AppColor.boneMuted)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(scope == option ? AppColor.nightCell : AppColor.night)
                        .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private func careerTable(_ career: PlayerCareerFeed) -> some View {
        if mode == .batting {
            let rows = career.battingRows.filter { includes(level: $0.level, league: $0.league) }
            if rows.isEmpty { noRows } else { battingTable(rows) }
        } else {
            let rows = career.pitchingRows.filter { includes(level: $0.level, league: $0.league) }
            if rows.isEmpty { noRows } else { pitchingTable(rows) }
        }
    }

    private var noRows: some View {
        Text("No \(scope.rawValue.lowercased()) regular-season rows are available for this record.")
            .font(AppFont.bodySmall)
            .foregroundStyle(AppColor.boneMuted)
            .padding(16)
    }

    private func includes(level: String?, league: String?) -> Bool {
        guard scope != .both else { return true }
        let description = "\(level ?? "") \(league ?? "")".lowercased()
        let isMLB = description.contains("mlb") || description.contains("major")
        return scope == .mlb ? isMLB : !isMLB
    }

    private func battingTable(_ rows: [PlayerBattingSeason]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    tableHeader("YEAR", 48, leading: true); tableHeader("TEAM", 58, leading: true)
                }
                .background(AppColor.nightCell)
                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        tableValue("\(row.season)", 48, leading: true); tableValue(compactTeamName(row.team), 58, leading: true)
                    }
                    .background(row.rowType == "subtotal" ? AppColor.nightCell : AppColor.night)
                }
            }
            .zIndex(1)

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        tableHeader("LEVEL", 55, leading: true)
                        tableHeader("G", 40); tableHeader("AB", 46); tableHeader("R", 40); tableHeader("H", 40)
                        tableHeader("2B", 40); tableHeader("3B", 40); tableHeader("HR", 40); tableHeader("RBI", 46)
                        tableHeader("SB", 40); tableHeader("BB", 40); tableHeader("SO", 40); tableHeader("AVG", 50)
                        tableHeader("OBP", 50); tableHeader("SLG", 50); tableHeader("OPS", 50)
                    }
                    .background(AppColor.nightCell)
                    ForEach(rows) { row in
                        HStack(spacing: 0) {
                            tableValue(row.level ?? row.league ?? "—", 55, leading: true)
                            tableValue(row.games, 40); tableValue(row.atBats, 46); tableValue(row.runs, 40); tableValue(row.hits, 40)
                            tableValue(row.doubles, 40); tableValue(row.triples, 40); tableValue(row.homeRuns, 40); tableValue(row.runsBattedIn, 46)
                            tableValue(row.stolenBases, 40); tableValue(row.walks, 40); tableValue(row.strikeouts, 40); tableValue(rate(row.average), 50)
                            tableValue(rate(row.onBasePercentage), 50); tableValue(rate(row.sluggingPercentage), 50); tableValue(rate(row.ops), 50)
                        }
                        .background(row.rowType == "subtotal" ? AppColor.nightCell : AppColor.night)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(battingAccessibility(row))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pitchingTable(_ rows: [PlayerPitchingSeason]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    tableHeader("YEAR", 48, leading: true); tableHeader("TEAM", 58, leading: true)
                }
                .background(AppColor.nightCell)
                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        tableValue("\(row.season)", 48, leading: true); tableValue(compactTeamName(row.team), 58, leading: true)
                    }
                    .background(row.rowType == "subtotal" ? AppColor.nightCell : AppColor.night)
                }
            }
            .zIndex(1)

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        tableHeader("LEVEL", 55, leading: true)
                        tableHeader("G", 40); tableHeader("GS", 40); tableHeader("W", 40); tableHeader("L", 40)
                        tableHeader("SV", 40); tableHeader("IP", 50); tableHeader("H", 40); tableHeader("ER", 40)
                        tableHeader("HR", 40); tableHeader("BB", 40); tableHeader("SO", 40); tableHeader("ERA", 50); tableHeader("WHIP", 54)
                    }
                    .background(AppColor.nightCell)
                    ForEach(rows) { row in
                        HStack(spacing: 0) {
                            tableValue(row.level ?? row.league ?? "—", 55, leading: true)
                            tableValue(row.games, 40); tableValue(row.gamesStarted, 40); tableValue(row.wins, 40); tableValue(row.losses, 40)
                            tableValue(row.saves, 40); tableValue(row.inningsPitched, 50); tableValue(row.hits, 40); tableValue(row.earnedRuns, 40)
                            tableValue(row.homeRuns, 40); tableValue(row.walks, 40); tableValue(row.strikeouts, 40); tableValue(decimal(row.era), 50); tableValue(rate(row.whip), 54)
                        }
                        .background(row.rowType == "subtotal" ? AppColor.nightCell : AppColor.night)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(pitchingAccessibility(row))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableHeader(_ text: String, _ width: CGFloat, leading: Bool = false) -> some View {
        Text(text)
            .font(AppFont.label.weight(.semibold))
            .foregroundStyle(AppColor.bone)
            .padding(.leading, leading ? 5 : 0)
            .frame(width: width, height: 31, alignment: leading ? .leading : .center)
            .overlay(alignment: .trailing) { Rectangle().fill(AppColor.rule).frame(width: 1) }
    }

    private func tableValue(_ value: String?, _ width: CGFloat, leading: Bool = false) -> some View {
        Text(value ?? "—")
            .font(AppFont.label.monospacedDigit())
            .foregroundStyle(AppColor.boneDim)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, leading ? 5 : 0)
            .frame(width: width, height: 31, alignment: leading ? .leading : .center)
            .overlay(alignment: .trailing) { Rectangle().fill(AppColor.rule).frame(width: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(AppColor.rule).frame(height: 1) }
    }

    private func tableValue(_ value: Int?, _ width: CGFloat) -> some View { tableValue(value.map(String.init), width) }

    private func rate(_ value: Double?) -> String? {
        guard let value else { return nil }
        let rendered = String(format: "%.3f", value)
        return rendered.hasPrefix("0.") ? String(rendered.dropFirst()) : rendered
    }

    private func decimal(_ value: Double?) -> String? {
        guard let value else { return nil }
        return String(format: "%.2f", value)
    }

    /// The provider stores full club names. The history grid deliberately uses a
    /// compact, stable label so that more statistics remain visible on a phone.
    private func compactTeamName(_ team: String) -> String {
        let mlbAbbreviations = [
            "Arizona Diamondbacks": "ARI", "Atlanta Braves": "ATL", "Baltimore Orioles": "BAL",
            "Boston Red Sox": "BOS", "Chicago Cubs": "CHC", "Chicago White Sox": "CWS",
            "Cincinnati Reds": "CIN", "Cleveland Guardians": "CLE", "Cleveland Indians": "CLE",
            "Colorado Rockies": "COL", "Detroit Tigers": "DET", "Houston Astros": "HOU",
            "Kansas City Royals": "KC", "Los Angeles Angels": "LAA", "Los Angeles Dodgers": "LAD",
            "Miami Marlins": "MIA", "Milwaukee Brewers": "MIL", "Minnesota Twins": "MIN",
            "New York Mets": "NYM", "New York Yankees": "NYY", "Oakland Athletics": "OAK",
            "Athletics": "ATH", "Philadelphia Phillies": "PHI", "Pittsburgh Pirates": "PIT",
            "San Diego Padres": "SD", "San Francisco Giants": "SF", "Seattle Mariners": "SEA",
            "St. Louis Cardinals": "STL", "Tampa Bay Rays": "TB", "Texas Rangers": "TEX",
            "Toronto Blue Jays": "TOR", "Washington Nationals": "WSH"
        ]
        if let abbreviation = mlbAbbreviations[team] { return abbreviation }
        if let teams = team.split(separator: " ").first, Int(teams) != nil, team.hasSuffix("teams") {
            return "\(teams) TM"
        }
        let words = team.split(separator: " ").filter { !$0.isEmpty }
        guard words.count > 1 else { return team }
        return words.compactMap(\.first).map(String.init).joined().uppercased()
    }

    private func battingAccessibility(_ row: PlayerBattingSeason) -> String {
        "\(row.season), \(row.team), \(row.level ?? row.league ?? "level unavailable"). \(row.games ?? 0) games, \(row.hits ?? 0) hits, \(row.homeRuns ?? 0) home runs."
    }

    private func pitchingAccessibility(_ row: PlayerPitchingSeason) -> String {
        "\(row.season), \(row.team), \(row.level ?? row.league ?? "level unavailable"). \(row.games ?? 0) games, \(row.wins ?? 0) wins, \(row.strikeouts ?? 0) strikeouts."
    }

    private func careerFooter(_ career: PlayerCareerFeed) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let dataAsOf = career.dataAsOf {
                Text("DATA AS OF \(dataAsOf.uppercased())")
            }
            if let note = career.coverage?.first(where: { $0.status != "available" })?.note {
                Text(note)
            }
        }
        .font(AppFont.label)
        .foregroundStyle(AppColor.boneMuted)
        .padding(12)
    }

    private var unavailableCareer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DETAILED RECORD UNAVAILABLE")
                .font(AppFont.label.weight(.semibold))
                .foregroundStyle(AppColor.amber)
            Text(store.careerError(for: player) ?? "This roster snapshot includes verified biography and career totals, but not a season-by-season record for this player.")
                .font(AppFont.bodySmall)
                .foregroundStyle(AppColor.boneDim)
            if let through = player.careerStats?.throughSeason {
                Text("Existing MLB totals are through \(through). No missing season has been represented as a zero.")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.boneMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .overlay(alignment: .leading) { Rectangle().fill(AppColor.amber).frame(width: 3) }
    }

    private var educationPanel: some View {
        detailPanel("EDUCATION") {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(player.education.entries, id: \.self) { entry in
                    Text(entry)
                        .font(AppFont.bodySmall)
                        .foregroundStyle(AppColor.boneDim)
                }
            }
        }
    }

    private var sourcePanel: some View {
        detailPanel("SOURCES") {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.career(for: player)?.source?.attribution ?? source?.attribution ?? "Open source player data")
                if let attribution = source?.statsAttribution { Text(attribution) }
                HStack(spacing: 16) {
                    if let url = player.sourceURL { Link("Wikidata", destination: url) }
                    if let url = player.articleURL { Link("Wikipedia", destination: url) }
                    if let value = store.career(for: player)?.source?.url, let url = URL(string: value) { Link("Career source", destination: url) }
                }
                .font(AppFont.label.weight(.semibold))
                .foregroundStyle(AppColor.steel)
            }
            .font(AppFont.label)
            .foregroundStyle(AppColor.boneMuted)
        }
    }

    private func detailPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.displaySmall)
                .foregroundStyle(AppColor.bone)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(AppColor.rule).frame(height: 1) }
            content().padding(12)
        }
        .background(AppColor.nightRaised)
        .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
    }
}

private extension String {
    var shortHand: String {
        switch lowercased() {
        case "left": "L"
        case "right": "R"
        case "switch": "S"
        default: self
        }
    }
}

#Preview {
    PlayersView(team: .boston)
        .environment(\.hubContentWidth, 390)
}
