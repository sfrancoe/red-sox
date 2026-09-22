import SwiftUI

struct PlayersView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .background(AppColor.night.ignoresSafeArea())
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
                if store.visiblePlayers.isEmpty {
                    ContentUnavailableView.search(text: store.searchText)
                        .frame(minHeight: 280)
                } else {
                    if usesExpandedReadingLayout {
                        expandedSortBar
                    } else {
                        spreadsheetHeader
                    }
                    ForEach(store.visiblePlayers) { player in
                        NavigationLink(value: player.id) {
                            if usesExpandedReadingLayout {
                                expandedDirectoryRow(player)
                            } else {
                                spreadsheetRow(player)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                sourceFooter(feed.source)
            }
            .padding(.bottom, 20)
        }
        .refreshable { await store.load() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.night.ignoresSafeArea())
    }

    private var usesExpandedReadingLayout: Bool {
        dynamicTypeSize.usesExpandedReadingLayout
    }

    private var expandedSortBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Player order", selection: Binding(
                get: { store.sort },
                set: { store.toggleSort($0) }
            )) {
                ForEach(PlayerDirectorySort.allCases) { column in
                    Text(directorySortTitle(column)).tag(column)
                }
            }
            .accessibilityValue("\(directorySortTitle(store.sort)), \(store.sortsAscending ? "ascending" : "descending")")

            Picker("Sort direction", selection: $store.sortsAscending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
        }
        .pickerStyle(.menu)
        .font(.body)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, directoryHorizontalPadding)
        .padding(.vertical, 8)
        .background(AppColor.nightRaised)
    }

    private func directorySortTitle(_ column: PlayerDirectorySort) -> String {
        switch column {
        case .number: "Number"
        case .name: "Player"
        case .position: "Position"
        case .batsThrows: "Bats / throws"
        case .age: "Age"
        }
    }

    private func expandedDirectoryRow(_ player: RedSoxPlayer) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColor.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Number \(player.number ?? "—")")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppColor.amber)
            }
            let metadataSpacing: CGFloat = contentWidth < 460 ? 7 : 12
            if contentWidth < 460 || dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: metadataSpacing) {
                    playerDirectoryValue("Position", player.position.name)
                    playerDirectoryValue("Bats / throws", "\(player.bats?.shortHand ?? "—") / \(player.throws?.shortHand ?? "—")")
                    playerDirectoryValue("Age", player.age.map(String.init) ?? "—")
                }
            } else {
                HStack(spacing: metadataSpacing) {
                    playerDirectoryValue("Position", player.position.name)
                    playerDirectoryValue("Bats / throws", "\(player.bats?.shortHand ?? "—") / \(player.throws?.shortHand ?? "—")")
                    playerDirectoryValue("Age", player.age.map(String.init) ?? "—")
                }
            }
        }
        .padding(.horizontal, directoryHorizontalPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.night)
        .overlay(alignment: .bottom) { Rectangle().fill(AppColor.rule).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(player.name), number \(player.number ?? "unassigned"), \(player.position.name), bats \(player.bats ?? "unavailable"), throws \(player.throws ?? "unavailable"), age \(player.age.map(String.init) ?? "unavailable")")
        .accessibilityHint("Opens career card")
    }

    private func playerDirectoryValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(AppColor.boneMuted)
            Text(value).font(.subheadline).foregroundStyle(AppColor.boneDim).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.steel)
            TextField(
                "Search players",
                text: $store.searchText,
                prompt: Text("Search players").foregroundStyle(AppColor.boneDim)
            )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundStyle(AppColor.bone)
                .tint(AppColor.steel)
        }
        .font(contentWidth >= 650 ? AppFont.body : AppFont.bodySmall)
        .padding(.horizontal, 12)
        .frame(minHeight: contentWidth >= 650 ? 48 : 44)
        .background(AppColor.nightRaised)
        .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
        .padding(.horizontal, directoryHorizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var filterBar: some View {
        if usesExpandedReadingLayout {
            Picker("Player position", selection: $store.filter) {
                ForEach(PlayerPositionFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, directoryHorizontalPadding)
            .padding(.bottom, 12)
        } else if contentWidth >= 650 {
            HStack(spacing: 8) {
                ForEach(PlayerPositionFilter.allCases) { filter in
                    positionFilterButton(filter, expands: true)
                }
            }
            .padding(.horizontal, directoryHorizontalPadding)
            .padding(.bottom, 14)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PlayerPositionFilter.allCases) { filter in
                        positionFilterButton(filter, expands: false)
                    }
                }
            }
            .padding(.horizontal, directoryHorizontalPadding)
            .padding(.bottom, 12)
        }
    }

    private func positionFilterButton(_ filter: PlayerPositionFilter, expands: Bool) -> some View {
        let isSelected = store.filter == filter
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { store.filter = filter }
        } label: {
            Text(filter.title)
                .font((contentWidth >= 650 ? AppFont.bodySmall : AppFont.label).weight(.semibold))
                .foregroundStyle(isSelected ? AppColor.bone : AppColor.boneDim)
                .lineLimit(1)
                .minimumScaleFactor(usesExpandedReadingLayout ? 1 : 0.85)
                .padding(.horizontal, contentWidth >= 650 ? 10 : 14)
                .frame(maxWidth: expands ? .infinity : nil)
                .frame(minHeight: contentWidth >= 650 ? 48 : 44)
                .background(isSelected ? AppColor.night : AppColor.nightRaised)
                .overlay {
                    Rectangle().stroke(isSelected ? AppColor.amber : AppColor.rule, lineWidth: isSelected ? 2 : 1)
                }
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Rectangle().fill(AppColor.amber).frame(height: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: expands ? .infinity : nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var spreadsheetHeader: some View {
        HStack(spacing: 0) {
            sortHeader(.number, width: numberColumnWidth, alignment: .leading)
            sortHeader(.name, alignment: .leading)
            sortHeader(.position, width: positionColumnWidth, alignment: .leading)
            sortHeader(.batsThrows, width: batsThrowsColumnWidth, alignment: .leading)
            if showsAgeColumn { sortHeader(.age, width: ageColumnWidth, alignment: .leading) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: contentWidth >= 650 ? 40 : 36)
        .padding(.horizontal, directoryHorizontalPadding)
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
                .frame(width: numberColumnWidth, alignment: .leading)
            Text(player.name)
                .font((contentWidth >= 650 ? AppFont.body : AppFont.bodySmall).weight(.medium))
                .foregroundStyle(AppColor.bone)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(player.position.abbreviation)
                .font(AppFont.label.monospaced())
                .foregroundStyle(AppColor.boneDim)
                .frame(width: positionColumnWidth, alignment: .leading)
            Text("\(player.bats?.shortHand ?? "—")/\(player.throws?.shortHand ?? "—")")
                .font(AppFont.label.monospaced())
                .foregroundStyle(AppColor.boneDim)
                .frame(width: batsThrowsColumnWidth, alignment: .leading)
            if showsAgeColumn {
                Text(player.age.map(String.init) ?? "—")
                    .font(AppFont.label.monospacedDigit())
                    .foregroundStyle(AppColor.boneDim)
                    .frame(width: ageColumnWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: contentWidth >= 650 ? 48 : 44)
        .padding(.horizontal, directoryHorizontalPadding)
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
            .background(AppColor.night)
    }

    private var directoryHorizontalPadding: CGFloat { contentWidth >= 650 ? 24 : 16 }
    private var numberColumnWidth: CGFloat { contentWidth >= 650 ? 64 : 42 }
    private var positionColumnWidth: CGFloat { contentWidth >= 650 ? 76 : 48 }
    private var batsThrowsColumnWidth: CGFloat { contentWidth >= 650 ? 76 : 48 }
    private var ageColumnWidth: CGFloat { contentWidth >= 650 ? 56 : 40 }
    private var showsAgeColumn: Bool { contentWidth >= 520 }

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

private enum BattingCareerSort: String, CaseIterable {
    case year, team, level, games, atBats, runs, hits, homeRuns, triples, doubles
    case runsBattedIn, stolenBases, walks, strikeouts, average, onBasePercentage
    case sluggingPercentage, ops

    var title: String {
        switch self {
        case .year: "Year"
        case .team: "Team"
        case .level: "Level"
        case .games: "G"
        case .atBats: "AB"
        case .runs: "R"
        case .hits: "H"
        case .homeRuns: "HR"
        case .triples: "3B"
        case .doubles: "2B"
        case .runsBattedIn: "RBI"
        case .stolenBases: "SB"
        case .walks: "BB"
        case .strikeouts: "SO"
        case .average: "AVG"
        case .onBasePercentage: "OBP"
        case .sluggingPercentage: "SLG"
        case .ops: "OPS"
        }
    }
}

private enum PitchingCareerSort: String, CaseIterable {
    case year, team, level, games, gamesStarted, wins, losses, saves, inningsOuts
    case hits, earnedRuns, homeRuns, walks, strikeouts, era, whip

    var title: String {
        switch self {
        case .year: "Year"
        case .team: "Team"
        case .level: "Level"
        case .games: "G"
        case .gamesStarted: "GS"
        case .wins: "W"
        case .losses: "L"
        case .saves: "SV"
        case .inningsOuts: "IP"
        case .hits: "H"
        case .earnedRuns: "ER"
        case .homeRuns: "HR"
        case .walks: "BB"
        case .strikeouts: "SO"
        case .era: "ERA"
        case .whip: "WHIP"
        }
    }
}

private struct PlayerReferenceView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    let team: HubTeam
    let player: RedSoxPlayer
    let source: PlayersSource?
    let store: PlayersStore
    @State private var mode: PlayerRecordMode
    @State private var scope: CareerScope = .mlb
    @State private var battingSort: BattingCareerSort = .year
    @State private var battingSortsAscending = true
    @State private var pitchingSort: PitchingCareerSort = .year
    @State private var pitchingSortsAscending = true

    init(team: HubTeam, player: RedSoxPlayer, source: PlayersSource?, store: PlayersStore) {
        self.team = team
        self.player = player
        self.source = source
        self.store = store
        _mode = State(initialValue: player.positionFilter == .pitcher ? .pitching : .batting)
    }

    private var usesExpandedReadingLayout: Bool {
        dynamicTypeSize.usesExpandedReadingLayout
    }

    private var careerRowHeight: CGFloat {
        usesExpandedReadingLayout ? 54 : 31
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if usesExpandedReadingLayout { expandedPlayerTitle }
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
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back to players")
            }
            ToolbarItem(placement: .principal) {
                if !usesExpandedReadingLayout { playerNavigationTitle }
            }
        }
        .task { await store.loadCareer(for: player) }
    }

    @ViewBuilder
    private var biographyPanel: some View {
        if usesExpandedReadingLayout {
            VStack(alignment: .leading, spacing: 10) {
                bioValue("BATS", player.bats ?? "—")
                bioValue("THROWS", player.throws ?? "—")
                bioValue("BORN", player.formattedShortDate(player.birthDate) ?? "—")
                bioValue("BIRTHPLACE", player.birthplace.isEmpty ? "—" : player.birthplace)
                bioValue("MLB DEBUT", player.formattedShortDate(player.debutDate) ?? "—")
                bioValue("STATUS", player.rosterStatus)
            }
            .padding(14)
            .background(AppColor.nightRaised)
            .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
        } else {
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
    }

    @ViewBuilder
    private func bioValue(_ label: String, _ value: String) -> some View {
        if usesExpandedReadingLayout || contentWidth < 460 {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppFont.label.weight(.semibold))
                    .foregroundStyle(AppColor.boneMuted)
                Text(value)
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.boneDim)
                    .lineLimit(usesExpandedReadingLayout ? nil : 2)
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
                    .lineLimit(usesExpandedReadingLayout ? nil : 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var expandedPlayerTitle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(player.fullName ?? player.name)
                .font(AppFont.displayMedium)
                .fixedSize(horizontal: false, vertical: true)
            Text("Number \(player.number ?? "—") · \(player.position.name)")
                .font(AppFont.body)
                .foregroundStyle(AppColor.amber)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var playerNavigationTitle: some View {
        HStack(spacing: 12) {
            Text(player.number.map { "#\($0)" } ?? "—")
                .font(AppFont.displaySmall.monospacedDigit())
                .foregroundStyle(AppColor.amber)
            Text(player.fullName ?? player.name)
                .font(AppFont.displayMedium)
                .foregroundStyle(AppColor.bone)
                .lineLimit(usesExpandedReadingLayout ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
            Text(player.position.abbreviation)
                .font(AppFont.label.weight(.semibold).monospaced())
                .foregroundStyle(AppColor.boneDim)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(AppColor.nightCell)
                .overlay { Capsule().stroke(AppColor.rule, lineWidth: 1) }
                .clipShape(Capsule())
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
        let layout = usesExpandedReadingLayout ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            ForEach(PlayerRecordMode.allCases) { option in
                Button { mode = option } label: {
                    Text(option.title)
                        .font(AppFont.label.weight(.semibold))
                        .foregroundStyle(mode == option ? AppColor.bone : AppColor.boneMuted)
                        .frame(maxWidth: .infinity, minHeight: usesExpandedReadingLayout ? 44 : 34)
                        .background(mode == option ? AppColor.nightCell : AppColor.night)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private var scopePicker: some View {
        let layout = usesExpandedReadingLayout ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            ForEach(CareerScope.allCases) { option in
                Button { scope = option } label: {
                    Text(option.rawValue)
                        .font(AppFont.label)
                        .foregroundStyle(scope == option ? AppColor.bone : AppColor.boneMuted)
                        .frame(maxWidth: .infinity, minHeight: usesExpandedReadingLayout ? 44 : 30)
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
            if rows.isEmpty {
                noRows
            } else if usesExpandedReadingLayout {
                expandedBattingTable(rows)
            } else {
                battingTable(rows)
            }
        } else {
            let rows = career.pitchingRows.filter { includes(level: $0.level, league: $0.league) }
            if rows.isEmpty {
                noRows
            } else if usesExpandedReadingLayout {
                expandedPitchingTable(rows)
            } else {
                pitchingTable(rows)
            }
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
        let summaryRows = battingSummaryRows(rows)
        let sortedRows = sortedBattingRows(rows)
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    battingHeader(.year, 48, leading: true); battingHeader(.team, 58, leading: true)
                }
                .background(AppColor.nightCell)
                ForEach(sortedRows) { row in
                    HStack(spacing: 0) {
                        tableValue("\(row.season)", 48, leading: true); tableValue(compactTeamName(row.team), 58, leading: true)
                    }
                    .background(row.rowType == "subtotal" ? AppColor.nightCell : AppColor.night)
                }
                HStack(spacing: 0) {
                    summaryValue("TOT", 48, leading: true); summaryValue("AVG", 58, leading: true)
                }
            }
            .zIndex(1)

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        battingHeader(.level, 55, leading: true)
                        battingHeader(.games, 40); battingHeader(.atBats, 46); battingHeader(.runs, 40); battingHeader(.hits, 40)
                        battingHeader(.homeRuns, 40); battingHeader(.triples, 40); battingHeader(.doubles, 40); battingHeader(.runsBattedIn, 46)
                        battingHeader(.stolenBases, 40); battingHeader(.walks, 40); battingHeader(.strikeouts, 40); battingHeader(.average, 50)
                        battingHeader(.onBasePercentage, 50); battingHeader(.sluggingPercentage, 50); battingHeader(.ops, 50)
                    }
                    .background(AppColor.nightCell)
                    ForEach(sortedRows) { row in
                        HStack(spacing: 0) {
                            tableValue(row.level ?? row.league ?? "—", 55, leading: true)
                            tableValue(row.games, 40); tableValue(row.atBats, 46); tableValue(row.runs, 40); tableValue(row.hits, 40)
                            tableValue(row.homeRuns, 40); tableValue(row.triples, 40); tableValue(row.doubles, 40); tableValue(row.runsBattedIn, 46)
                            tableValue(row.stolenBases, 40); tableValue(row.walks, 40); tableValue(row.strikeouts, 40); tableValue(rate(row.average), 50)
                            tableValue(rate(row.onBasePercentage), 50); tableValue(rate(row.sluggingPercentage), 50); tableValue(rate(row.ops), 50)
                        }
                        .background(row.rowType == "subtotal" ? AppColor.nightCell : AppColor.night)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(battingAccessibility(row))
                    }
                    HStack(spacing: 0) {
                        summaryValue("—", 55, leading: true)
                        summaryValue(total(summaryRows.map(\.games)), 40); summaryValue(total(summaryRows.map(\.atBats)), 46); summaryValue(total(summaryRows.map(\.runs)), 40); summaryValue(total(summaryRows.map(\.hits)), 40)
                        summaryValue(total(summaryRows.map(\.homeRuns)), 40); summaryValue(total(summaryRows.map(\.triples)), 40); summaryValue(total(summaryRows.map(\.doubles)), 40); summaryValue(total(summaryRows.map(\.runsBattedIn)), 46)
                        summaryValue(total(summaryRows.map(\.stolenBases)), 40); summaryValue(total(summaryRows.map(\.walks)), 40); summaryValue(total(summaryRows.map(\.strikeouts)), 40); summaryValue(rate(battingRate(summaryRows, \.average)), 50)
                        summaryValue(rate(battingRate(summaryRows, \.onBasePercentage)), 50); summaryValue(rate(battingRate(summaryRows, \.sluggingPercentage)), 50); summaryValue(rate(battingRate(summaryRows, \.ops)), 50)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Career totals. " + spokenMetrics(battingTotals(summaryRows)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pitchingTable(_ rows: [PlayerPitchingSeason]) -> some View {
        let summaryRows = pitchingSummaryRows(rows)
        let sortedRows = sortedPitchingRows(rows)
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    pitchingHeader(.year, 48, leading: true); pitchingHeader(.team, 58, leading: true)
                }
                .background(AppColor.nightCell)
                ForEach(sortedRows) { row in
                    HStack(spacing: 0) {
                        tableValue("\(row.season)", 48, leading: true); tableValue(compactTeamName(row.team), 58, leading: true)
                    }
                    .background(row.rowType == "subtotal" ? AppColor.nightCell : AppColor.night)
                }
                HStack(spacing: 0) {
                    summaryValue("TOT", 48, leading: true); summaryValue("AVG", 58, leading: true)
                }
            }
            .zIndex(1)

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        pitchingHeader(.level, 55, leading: true)
                        pitchingHeader(.games, 40); pitchingHeader(.gamesStarted, 40); pitchingHeader(.wins, 40); pitchingHeader(.losses, 40)
                        pitchingHeader(.saves, 40); pitchingHeader(.inningsOuts, 50); pitchingHeader(.hits, 40); pitchingHeader(.earnedRuns, 40)
                        pitchingHeader(.homeRuns, 40); pitchingHeader(.walks, 40); pitchingHeader(.strikeouts, 40); pitchingHeader(.era, 50); pitchingHeader(.whip, 54)
                    }
                    .background(AppColor.nightCell)
                    ForEach(sortedRows) { row in
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
                    HStack(spacing: 0) {
                        summaryValue("—", 55, leading: true)
                        summaryValue(total(summaryRows.map(\.games)), 40); summaryValue(total(summaryRows.map(\.gamesStarted)), 40); summaryValue(total(summaryRows.map(\.wins)), 40); summaryValue(total(summaryRows.map(\.losses)), 40)
                        summaryValue(total(summaryRows.map(\.saves)), 40); summaryValue(inningsPitched(summaryRows), 50); summaryValue(total(summaryRows.map(\.hits)), 40); summaryValue(total(summaryRows.map(\.earnedRuns)), 40)
                        summaryValue(total(summaryRows.map(\.homeRuns)), 40); summaryValue(total(summaryRows.map(\.walks)), 40); summaryValue(total(summaryRows.map(\.strikeouts)), 40); summaryValue(decimal(earnedRunAverage(summaryRows)), 50); summaryValue(rate(walksAndHitsPerInning(summaryRows)), 54)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Career totals. " + spokenMetrics(pitchingTotals(summaryRows)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct CareerMetric: Identifiable {
        let label: String
        let value: String?
        var id: String { label }
    }

    private func battingMetrics(_ row: PlayerBattingSeason) -> [CareerMetric] {
        [
            .init(label: "Games", value: row.games.map(String.init)),
            .init(label: "At bats", value: row.atBats.map(String.init)),
            .init(label: "Runs", value: row.runs.map(String.init)),
            .init(label: "Hits", value: row.hits.map(String.init)),
            .init(label: "Home runs", value: row.homeRuns.map(String.init)),
            .init(label: "Triples", value: row.triples.map(String.init)),
            .init(label: "Doubles", value: row.doubles.map(String.init)),
            .init(label: "Runs batted in", value: row.runsBattedIn.map(String.init)),
            .init(label: "Stolen bases", value: row.stolenBases.map(String.init)),
            .init(label: "Walks", value: row.walks.map(String.init)),
            .init(label: "Strikeouts", value: row.strikeouts.map(String.init)),
            .init(label: "Batting average", value: rate(row.average)),
            .init(label: "On-base percentage", value: rate(row.onBasePercentage)),
            .init(label: "Slugging percentage", value: rate(row.sluggingPercentage)),
            .init(label: "OPS", value: rate(row.ops))
        ]
    }

    private func pitchingMetrics(_ row: PlayerPitchingSeason) -> [CareerMetric] {
        [
            .init(label: "Games", value: row.games.map(String.init)),
            .init(label: "Games started", value: row.gamesStarted.map(String.init)),
            .init(label: "Wins", value: row.wins.map(String.init)),
            .init(label: "Losses", value: row.losses.map(String.init)),
            .init(label: "Saves", value: row.saves.map(String.init)),
            .init(label: "Innings pitched", value: row.inningsPitched),
            .init(label: "Hits", value: row.hits.map(String.init)),
            .init(label: "Earned runs", value: row.earnedRuns.map(String.init)),
            .init(label: "Home runs", value: row.homeRuns.map(String.init)),
            .init(label: "Walks", value: row.walks.map(String.init)),
            .init(label: "Strikeouts", value: row.strikeouts.map(String.init)),
            .init(label: "Earned run average", value: decimal(row.era)),
            .init(label: "WHIP", value: rate(row.whip))
        ]
    }

    private func battingTotals(_ rows: [PlayerBattingSeason]) -> [CareerMetric] {
        [
            .init(label: "Games", value: total(rows.map(\.games))),
            .init(label: "At bats", value: total(rows.map(\.atBats))),
            .init(label: "Runs", value: total(rows.map(\.runs))),
            .init(label: "Hits", value: total(rows.map(\.hits))),
            .init(label: "Home runs", value: total(rows.map(\.homeRuns))),
            .init(label: "Triples", value: total(rows.map(\.triples))),
            .init(label: "Doubles", value: total(rows.map(\.doubles))),
            .init(label: "Runs batted in", value: total(rows.map(\.runsBattedIn))),
            .init(label: "Stolen bases", value: total(rows.map(\.stolenBases))),
            .init(label: "Walks", value: total(rows.map(\.walks))),
            .init(label: "Strikeouts", value: total(rows.map(\.strikeouts))),
            .init(label: "Batting average", value: rate(battingRate(rows, \.average))),
            .init(label: "On-base percentage", value: rate(battingRate(rows, \.onBasePercentage))),
            .init(label: "Slugging percentage", value: rate(battingRate(rows, \.sluggingPercentage))),
            .init(label: "OPS", value: rate(battingRate(rows, \.ops)))
        ]
    }

    private func pitchingTotals(_ rows: [PlayerPitchingSeason]) -> [CareerMetric] {
        [
            .init(label: "Games", value: total(rows.map(\.games))),
            .init(label: "Games started", value: total(rows.map(\.gamesStarted))),
            .init(label: "Wins", value: total(rows.map(\.wins))),
            .init(label: "Losses", value: total(rows.map(\.losses))),
            .init(label: "Saves", value: total(rows.map(\.saves))),
            .init(label: "Innings pitched", value: inningsPitched(rows)),
            .init(label: "Hits", value: total(rows.map(\.hits))),
            .init(label: "Earned runs", value: total(rows.map(\.earnedRuns))),
            .init(label: "Home runs", value: total(rows.map(\.homeRuns))),
            .init(label: "Walks", value: total(rows.map(\.walks))),
            .init(label: "Strikeouts", value: total(rows.map(\.strikeouts))),
            .init(label: "Earned run average", value: decimal(earnedRunAverage(rows))),
            .init(label: "WHIP", value: rate(walksAndHitsPerInning(rows)))
        ]
    }

    private func spokenMetrics(_ metrics: [CareerMetric]) -> String {
        metrics.map { "\($0.label): \($0.value ?? "unavailable")" }.joined(separator: "; ")
    }

    private func expandedBattingTable(_ rows: [PlayerBattingSeason]) -> some View {
        let summaryRows = battingSummaryRows(rows)
        return LazyVStack(alignment: .leading, spacing: 10) {
            expandedBattingSortBar
            ForEach(sortedBattingRows(rows)) { row in
                VStack(alignment: .leading, spacing: 8) {
                    expandedCareerRecordHeader(season: row.season, team: row.team, level: row.level ?? row.league, rowType: row.rowType)
                    expandedMetrics(battingMetrics(row))
                }
                .padding(12)
                .background(row.rowType == "subtotal" ? AppColor.nightCell : AppColor.night)
                .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
                .accessibilityElement(children: .contain)
            }
            expandedCareerTotalsHeader("Career totals", detail: "Aggregated across \(summaryRows.count) season record\(summaryRows.count == 1 ? "" : "s")")
            expandedMetrics(battingTotals(summaryRows))
                .accessibilityIdentifier("career.batting.totals")
        }
        .padding(12)
    }

    private func expandedPitchingTable(_ rows: [PlayerPitchingSeason]) -> some View {
        let summaryRows = pitchingSummaryRows(rows)
        return LazyVStack(alignment: .leading, spacing: 10) {
            expandedPitchingSortBar
            ForEach(sortedPitchingRows(rows)) { row in
                VStack(alignment: .leading, spacing: 8) {
                    expandedCareerRecordHeader(season: row.season, team: row.team, level: row.level ?? row.league, rowType: row.rowType)
                    expandedMetrics(pitchingMetrics(row))
                }
                .padding(12)
                .background(row.rowType == "subtotal" ? AppColor.nightCell : AppColor.night)
                .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
                .accessibilityElement(children: .contain)
            }
            expandedCareerTotalsHeader("Career totals", detail: "Aggregated across \(summaryRows.count) season record\(summaryRows.count == 1 ? "" : "s")")
            expandedMetrics(pitchingTotals(summaryRows))
                .accessibilityIdentifier("career.pitching.totals")
        }
        .padding(12)
    }

    private func expandedMetrics(_ metrics: [CareerMetric]) -> some View {
        // One full-width record prevents four-digit totals and rates from splitting
        // across lines on narrow phones at the largest accessibility categories.
        // Each record has only 13–15 metrics. Resolve their heights together so
        // nested lazy estimates cannot move the career totals during scrolling.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(metrics) { metric in
                expandedCareerMetric(metric.label, metric.value)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var expandedBattingSortBar: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 6) {
                ForEach(BattingCareerSort.allCases, id: \.rawValue) { column in
                    expandedCareerSortButton(column.title, isSelected: battingSort == column, ascending: battingSortsAscending) {
                        toggleBattingSort(column)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Batting career sort controls")
    }

    private var expandedPitchingSortBar: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 6) {
                ForEach(PitchingCareerSort.allCases, id: \.rawValue) { column in
                    expandedCareerSortButton(column.title, isSelected: pitchingSort == column, ascending: pitchingSortsAscending) {
                        togglePitchingSort(column)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pitching career sort controls")
    }

    private func expandedCareerSortButton(_ title: String, isSelected: Bool, ascending: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if isSelected { Image(systemName: ascending ? "arrow.up" : "arrow.down") }
            }
            .font(AppFont.label.weight(.semibold))
            .foregroundStyle(isSelected ? AppColor.bone : AppColor.boneDim)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(isSelected ? AppColor.nightCell : AppColor.night)
            .overlay { Rectangle().stroke(isSelected ? AppColor.amber : AppColor.rule, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? (ascending ? "Ascending" : "Descending") : "Not selected")
    }

    private func expandedCareerRecordHeader(season: Int, team: String, level: String?, rowType: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(season))
                    .font(AppFont.body.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppColor.amber)
                Text(team)
                    .font(AppFont.body.weight(.semibold))
                    .foregroundStyle(AppColor.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text([level, rowType == "subtotal" ? "Season subtotal" : nil].compactMap { $0 }.joined(separator: " · "))
                .font(AppFont.label)
                .foregroundStyle(AppColor.boneMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expandedCareerTotalsHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppFont.body.weight(.bold))
                .foregroundStyle(AppColor.bone)
            Text(detail)
                .font(AppFont.label)
                .foregroundStyle(AppColor.boneMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expandedCareerMetric(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(AppFont.label.weight(.semibold))
                .foregroundStyle(AppColor.boneMuted)
            Text(value ?? "—")
                .font(AppFont.body.monospacedDigit())
                .foregroundStyle(AppColor.bone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(AppColor.night)
        .overlay { Rectangle().stroke(AppColor.rule, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "unavailable")
    }

    private func battingHeader(_ column: BattingCareerSort, _ width: CGFloat, leading: Bool = false) -> some View {
        sortableHeader(
            column.title,
            width,
            leading: leading,
            isSelected: battingSort == column,
            ascending: battingSortsAscending,
            action: { toggleBattingSort(column) }
        )
    }

    private func pitchingHeader(_ column: PitchingCareerSort, _ width: CGFloat, leading: Bool = false) -> some View {
        sortableHeader(
            column.title,
            width,
            leading: leading,
            isSelected: pitchingSort == column,
            ascending: pitchingSortsAscending,
            action: { togglePitchingSort(column) }
        )
    }

    private func sortableHeader(
        _ text: String,
        _ width: CGFloat,
        leading: Bool,
        isSelected: Bool,
        ascending: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(text)
                if isSelected {
                    Image(systemName: ascending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .font(AppFont.label.weight(.semibold))
            .foregroundStyle(isSelected ? AppColor.bone : AppColor.boneMuted)
            .padding(.leading, leading ? 5 : 0)
            .frame(width: width, height: careerRowHeight, alignment: leading ? .leading : .center)
            .overlay(alignment: .trailing) { Rectangle().fill(AppColor.rule).frame(width: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(text)")
        .accessibilityValue(isSelected ? (ascending ? "Ascending" : "Descending") : "Not selected")
    }

    private func toggleBattingSort(_ column: BattingCareerSort) {
        if battingSort == column {
            battingSortsAscending.toggle()
        } else {
            battingSort = column
            battingSortsAscending = true
        }
    }

    private func togglePitchingSort(_ column: PitchingCareerSort) {
        if pitchingSort == column {
            pitchingSortsAscending.toggle()
        } else {
            pitchingSort = column
            pitchingSortsAscending = true
        }
    }

    private func sortedBattingRows(_ rows: [PlayerBattingSeason]) -> [PlayerBattingSeason] {
        rows.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch battingSort {
            case .year: comparison = sortComparison(lhs.season, rhs.season, ascending: battingSortsAscending)
            case .team: comparison = sortComparison(lhs.team, rhs.team, ascending: battingSortsAscending)
            case .level: comparison = sortComparison(lhs.level, rhs.level, ascending: battingSortsAscending)
            case .games: comparison = sortComparison(lhs.games, rhs.games, ascending: battingSortsAscending)
            case .atBats: comparison = sortComparison(lhs.atBats, rhs.atBats, ascending: battingSortsAscending)
            case .runs: comparison = sortComparison(lhs.runs, rhs.runs, ascending: battingSortsAscending)
            case .hits: comparison = sortComparison(lhs.hits, rhs.hits, ascending: battingSortsAscending)
            case .homeRuns: comparison = sortComparison(lhs.homeRuns, rhs.homeRuns, ascending: battingSortsAscending)
            case .triples: comparison = sortComparison(lhs.triples, rhs.triples, ascending: battingSortsAscending)
            case .doubles: comparison = sortComparison(lhs.doubles, rhs.doubles, ascending: battingSortsAscending)
            case .runsBattedIn: comparison = sortComparison(lhs.runsBattedIn, rhs.runsBattedIn, ascending: battingSortsAscending)
            case .stolenBases: comparison = sortComparison(lhs.stolenBases, rhs.stolenBases, ascending: battingSortsAscending)
            case .walks: comparison = sortComparison(lhs.walks, rhs.walks, ascending: battingSortsAscending)
            case .strikeouts: comparison = sortComparison(lhs.strikeouts, rhs.strikeouts, ascending: battingSortsAscending)
            case .average: comparison = sortComparison(lhs.average, rhs.average, ascending: battingSortsAscending)
            case .onBasePercentage: comparison = sortComparison(lhs.onBasePercentage, rhs.onBasePercentage, ascending: battingSortsAscending)
            case .sluggingPercentage: comparison = sortComparison(lhs.sluggingPercentage, rhs.sluggingPercentage, ascending: battingSortsAscending)
            case .ops: comparison = sortComparison(lhs.ops, rhs.ops, ascending: battingSortsAscending)
            }
            return comparison == .orderedSame
                ? stableRowOrder(lhs.season, lhs.team, lhs.id, rhs.season, rhs.team, rhs.id)
                : comparison == .orderedAscending
        }
    }

    private func sortedPitchingRows(_ rows: [PlayerPitchingSeason]) -> [PlayerPitchingSeason] {
        rows.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch pitchingSort {
            case .year: comparison = sortComparison(lhs.season, rhs.season, ascending: pitchingSortsAscending)
            case .team: comparison = sortComparison(lhs.team, rhs.team, ascending: pitchingSortsAscending)
            case .level: comparison = sortComparison(lhs.level, rhs.level, ascending: pitchingSortsAscending)
            case .games: comparison = sortComparison(lhs.games, rhs.games, ascending: pitchingSortsAscending)
            case .gamesStarted: comparison = sortComparison(lhs.gamesStarted, rhs.gamesStarted, ascending: pitchingSortsAscending)
            case .wins: comparison = sortComparison(lhs.wins, rhs.wins, ascending: pitchingSortsAscending)
            case .losses: comparison = sortComparison(lhs.losses, rhs.losses, ascending: pitchingSortsAscending)
            case .saves: comparison = sortComparison(lhs.saves, rhs.saves, ascending: pitchingSortsAscending)
            case .inningsOuts: comparison = sortComparison(lhs.inningsOuts, rhs.inningsOuts, ascending: pitchingSortsAscending)
            case .hits: comparison = sortComparison(lhs.hits, rhs.hits, ascending: pitchingSortsAscending)
            case .earnedRuns: comparison = sortComparison(lhs.earnedRuns, rhs.earnedRuns, ascending: pitchingSortsAscending)
            case .homeRuns: comparison = sortComparison(lhs.homeRuns, rhs.homeRuns, ascending: pitchingSortsAscending)
            case .walks: comparison = sortComparison(lhs.walks, rhs.walks, ascending: pitchingSortsAscending)
            case .strikeouts: comparison = sortComparison(lhs.strikeouts, rhs.strikeouts, ascending: pitchingSortsAscending)
            case .era: comparison = sortComparison(lhs.era, rhs.era, ascending: pitchingSortsAscending)
            case .whip: comparison = sortComparison(lhs.whip, rhs.whip, ascending: pitchingSortsAscending)
            }
            return comparison == .orderedSame
                ? stableRowOrder(lhs.season, lhs.team, lhs.id, rhs.season, rhs.team, rhs.id)
                : comparison == .orderedAscending
        }
    }

    private func sortComparison<Value: Comparable>(_ lhs: Value?, _ rhs: Value?, ascending: Bool) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs == rhs { return .orderedSame }
            return (ascending ? lhs < rhs : lhs > rhs) ? .orderedAscending : .orderedDescending
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        }
    }

    private func sortComparison<Value: Comparable>(_ lhs: Value, _ rhs: Value, ascending: Bool) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return (ascending ? lhs < rhs : lhs > rhs) ? .orderedAscending : .orderedDescending
    }

    private func stableRowOrder(_ lhsSeason: Int, _ lhsTeam: String, _ lhsID: String, _ rhsSeason: Int, _ rhsTeam: String, _ rhsID: String) -> Bool {
        if lhsSeason != rhsSeason { return lhsSeason < rhsSeason }
        if lhsTeam != rhsTeam { return lhsTeam < rhsTeam }
        return lhsID < rhsID
    }

    private func tableValue(_ value: String?, _ width: CGFloat, leading: Bool = false) -> some View {
        Text(value ?? "—")
            .font(AppFont.label.monospacedDigit())
            .foregroundStyle(AppColor.boneDim)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, leading ? 5 : 0)
            .frame(width: width, height: careerRowHeight, alignment: leading ? .leading : .center)
            .overlay(alignment: .trailing) { Rectangle().fill(AppColor.rule).frame(width: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(AppColor.rule).frame(height: 1) }
    }

    private func tableValue(_ value: Int?, _ width: CGFloat) -> some View { tableValue(value.map(String.init), width) }

    private func summaryValue(_ value: String?, _ width: CGFloat, leading: Bool = false) -> some View {
        Text(value ?? "—")
            .font(AppFont.label.weight(.semibold).monospacedDigit())
            .foregroundStyle(AppColor.bone)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, leading ? 5 : 0)
            .frame(width: width, height: careerRowHeight, alignment: leading ? .leading : .center)
            .background(AppColor.nightCell)
            .overlay(alignment: .trailing) { Rectangle().fill(AppColor.rule).frame(width: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(AppColor.rule).frame(height: 1) }
    }

    private func battingSummaryRows(_ rows: [PlayerBattingSeason]) -> [PlayerBattingSeason] {
        rowsBySeason(rows) { $0.season }
    }

    private func pitchingSummaryRows(_ rows: [PlayerPitchingSeason]) -> [PlayerPitchingSeason] {
        rowsBySeason(rows) { $0.season }
    }

    private func rowsBySeason<Row>(_ rows: [Row], season: (Row) -> Int, rowType: (Row) -> String?) -> [Row] {
        Dictionary(grouping: rows, by: season)
            .keys
            .sorted()
            .flatMap { year in
                let seasonRows = Dictionary(grouping: rows, by: season)[year] ?? []
                let subtotals = seasonRows.filter { rowType($0) == "subtotal" }
                return subtotals.isEmpty ? seasonRows : subtotals
            }
    }

    private func rowsBySeason(_ rows: [PlayerBattingSeason], _ season: (PlayerBattingSeason) -> Int) -> [PlayerBattingSeason] {
        rowsBySeason(rows, season: season, rowType: \.rowType)
    }

    private func rowsBySeason(_ rows: [PlayerPitchingSeason], _ season: (PlayerPitchingSeason) -> Int) -> [PlayerPitchingSeason] {
        rowsBySeason(rows, season: season, rowType: \.rowType)
    }

    private func total(_ values: [Int?]) -> String? {
        let values = values.compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return String(values.reduce(0, +))
    }

    private func battingRate(_ rows: [PlayerBattingSeason], _ keyPath: KeyPath<PlayerBattingSeason, Double?>) -> Double? {
        weightedAverage(rows.compactMap { row in
            row[keyPath: keyPath].map { ($0, row.atBats) }
        })
    }

    private func weightedAverage(_ values: [(Double, Int?)]) -> Double? {
        guard !values.isEmpty else { return nil }
        let weighted = values.compactMap { pair -> (Double, Int)? in
            guard let weight = pair.1, weight > 0 else { return nil }
            return (pair.0, weight)
        }
        guard !weighted.isEmpty else {
            return values.map(\.0).reduce(0, +) / Double(values.count)
        }
        let totalWeight = weighted.reduce(0) { $0 + $1.1 }
        return weighted.reduce(0) { $0 + $1.0 * Double($1.1) } / Double(totalWeight)
    }

    private func inningsPitched(_ rows: [PlayerPitchingSeason]) -> String? {
        guard let outs = totalOuts(rows) else { return nil }
        return "\(outs / 3).\(outs % 3)"
    }

    private func earnedRunAverage(_ rows: [PlayerPitchingSeason]) -> Double? {
        guard let outs = totalOuts(rows), let earnedRuns = totalInt(rows.map(\.earnedRuns)), outs > 0 else { return nil }
        return Double(earnedRuns * 27) / Double(outs)
    }

    private func walksAndHitsPerInning(_ rows: [PlayerPitchingSeason]) -> Double? {
        guard let outs = totalOuts(rows), let walks = totalInt(rows.map(\.walks)), let hits = totalInt(rows.map(\.hits)), outs > 0 else { return nil }
        return Double((walks + hits) * 3) / Double(outs)
    }

    private func totalOuts(_ rows: [PlayerPitchingSeason]) -> Int? {
        totalInt(rows.map(\.inningsOuts))
    }

    private func totalInt(_ values: [Int?]) -> Int? {
        let values = values.compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

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
        "\(row.season), \(row.team), \(row.level ?? row.league ?? "level unavailable"). " + spokenMetrics(battingMetrics(row))
    }

    private func pitchingAccessibility(_ row: PlayerPitchingSeason) -> String {
        "\(row.season), \(row.team), \(row.level ?? row.league ?? "level unavailable"). " + spokenMetrics(pitchingMetrics(row))
    }

    @ViewBuilder
    private func careerFooter(_ career: PlayerCareerFeed) -> some View {
        if let note = career.coverage?.first(where: { $0.status != "available" })?.note {
            Text(note)
                .font(AppFont.label)
                .foregroundStyle(AppColor.boneMuted)
                .padding(12)
        }
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
