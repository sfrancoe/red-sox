import SwiftUI

struct PlayersView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @State private var store = PlayersStore()
    @State private var path: [Int] = []

    let requestedPlayerID: Int?
    let onRequestHandled: () -> Void

    init(requestedPlayerID: Int? = nil, onRequestHandled: @escaping () -> Void = {}) {
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    errorView
                }
            }
            .background(AppColor.cream)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Int.self) { playerID in
                if let player = store.player(id: playerID) {
                    PlayerReferenceView(player: player, source: store.feed?.source)
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
                directoryHeader(feed)
                filterBar
                if store.visiblePlayers.isEmpty {
                    ContentUnavailableView.search(text: store.searchText)
                        .frame(minHeight: 300)
                } else {
                    ForEach(store.visiblePlayers) { player in
                        NavigationLink(value: player.id) {
                            rosterRow(player)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 76)
                    }
                }
                sourceFooter(feed.source)
            }
        }
        .background(AppColor.cream)
        .refreshable { await store.load() }
        .searchable(text: $store.searchText, prompt: "Search player or position")
    }

    private func directoryHeader(_ feed: PlayersFeed) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(AppColor.teamAccent)
                Image(systemName: "baseball.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AppColor.ink)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: -3) {
                Text("BOSTON BASEBALL")
                    .font(.system(size: contentWidth >= 650 ? 35 : 27, weight: .black))
                    .foregroundStyle(AppColor.ink)
                Text("PLAYER REFERENCE")
                    .font(.system(size: contentWidth >= 650 ? 25 : 20, weight: .medium))
                    .foregroundStyle(AppColor.ink)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(feed.playerCount)")
                    .font(.title2.weight(.black).monospacedDigit())
                Text("PLAYERS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppColor.ink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(PlayerPositionFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { store.filter = filter }
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppColor.ink)
                            .padding(.horizontal, 15)
                            .frame(height: 38)
                            .background(store.filter == filter ? AppColor.accentSoft : AppColor.paper)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.filter == filter ? .isSelected : [])
                }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(AppColor.teamAccent).frame(height: 2) }
    }

    private func rosterRow(_ player: RedSoxPlayer) -> some View {
        HStack(spacing: 12) {
            monogram(player, width: 52, height: 64, fontSize: 19)
            VStack(alignment: .leading, spacing: 3) {
                Text(player.name)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(AppColor.ink)
                Text("\(player.position.name) · \(player.rosterStatus)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.ink)
                if let age = player.age {
                    Text("Age \(age)\(player.birthplace.isEmpty ? "" : " · \(player.birthplace)")")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.ink)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(player.number.map { "#\($0)" } ?? "")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(AppColor.darkRed)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColor.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func monogram(_ player: RedSoxPlayer, width: CGFloat, height: CGFloat, fontSize: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(AppColor.paper)
            Text(player.initials)
                .font(.system(size: fontSize, weight: .black))
                .foregroundStyle(AppColor.navy)
        }
        .frame(width: width, height: height)
        .overlay { Rectangle().stroke(AppColor.border, lineWidth: AppColor.panelBorderWidth) }
        .accessibilityHidden(true)
    }

    private func sourceFooter(_ source: PlayersSource) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(source.attribution)
            if let statsAttribution = source.statsAttribution {
                Text(statsAttribution)
            }
        }
        .font(.caption2)
        .foregroundStyle(AppColor.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColor.paper)
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
                .tint(AppColor.darkRed)
        }
    }
}

private struct PlayerReferenceView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    let player: RedSoxPlayer
    let source: PlayersSource?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                identityHeader
                sectionBar
                summaryGrid
                careerStatsSection
                referenceSection("Teams Played For") { teamsTable }
                referenceSection("Education") { educationRows }
                referenceSection("Sources") { sourceRows }
            }
        }
        .background(AppColor.cream)
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var identityHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            monogram
            VStack(alignment: .leading, spacing: 5) {
                Text(player.name)
                    .font(.system(size: contentWidth >= 650 ? 34 : 28, weight: .black))
                    .foregroundStyle(AppColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if contentWidth < 450 {
                    compactReferenceLine(player.position.name)
                    compactReferenceLine("Bats \(player.bats ?? "—") · Throws \(player.throws ?? "—")")
                    if let measurements { compactReferenceLine(measurements) }
                    compactReferenceLine("Boston Red Sox")
                } else {
                    referenceLine("Position", player.position.name)
                    referenceLine("Bats", player.bats ?? "—", trailingLabel: "Throws", trailingValue: player.throws ?? "—")
                    if let measurements { Text(measurements).font(.system(size: 13)).foregroundStyle(AppColor.ink) }
                    referenceLine("Current team", "Boston Red Sox")
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Text(player.rosterStatus.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 25)
                    .background(AppColor.accentSoft)
                    .clipShape(Rectangle())
                if let number = player.number {
                    Text("#\(number)")
                        .font(.system(size: 24, weight: .black).monospacedDigit())
                        .foregroundStyle(AppColor.darkRed)
                }
            }
            .frame(maxWidth: contentWidth >= 650 ? 150 : 92)
        }
        .padding(16)
    }

    private var monogram: some View {
        ZStack {
            Rectangle().fill(AppColor.paper)
            Text(player.initials)
                .font(.system(size: contentWidth >= 650 ? 34 : 27, weight: .black))
                .foregroundStyle(AppColor.navy)
        }
        .frame(width: contentWidth >= 650 ? 112 : 82, height: contentWidth >= 650 ? 132 : 104)
        .overlay { Rectangle().stroke(AppColor.border, lineWidth: AppColor.panelBorderWidth) }
        .accessibilityLabel("No player photograph")
    }

    @ViewBuilder
    private func referenceLine(_ label: String, _ value: String, trailingLabel: String? = nil, trailingValue: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text("\(label):").fontWeight(.bold)
            Text(value)
            if let trailingLabel, let trailingValue {
                Text("· \(trailingLabel):").fontWeight(.bold)
                Text(trailingValue)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(AppColor.ink)
    }

    private func compactReferenceLine(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppColor.ink.opacity(0.78))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var measurements: String? {
        let values = [player.height, player.weight.map { "\($0) lb" }].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }

    private var sectionBar: some View {
        HStack(spacing: 0) {
            ForEach(["SUMMARY", "TEAMS", "EDUCATION", "SOURCES"], id: \.self) { title in
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(title == "SUMMARY" ? AppColor.accentSoft : AppColor.paper)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(AppColor.teamAccent).frame(height: 2) }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: contentWidth >= 700 ? 6 : 3), spacing: 0) {
            summaryCell("AGE", player.age.map(String.init) ?? "—")
            summaryCell("BORN", player.formattedDate(player.birthDate) ?? "—")
            summaryCell("FROM", player.birthplace.isEmpty ? "—" : player.birthplace)
            summaryCell("DEBUT", player.debutDate ?? "—")
            summaryCell("DEBUT TEAM", player.debutTeam ?? "—")
            summaryCell("TEAMS", "\(player.teams.count)")
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func summaryCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(AppColor.darkRed)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 55, alignment: .topLeading)
        .padding(.horizontal, 10)
        .overlay(alignment: .trailing) { Divider() }
    }

    @ViewBuilder
    private var careerStatsSection: some View {
        let throughSeason = player.careerStats?.throughSeason ?? source?.statsThrough ?? 2025
        referenceSection("Career Statistics · Through \(throughSeason)") {
            if player.positionFilter == .pitcher, let stats = player.careerStats?.pitching {
                statGrid([
                    ("G", "\(stats.games)"), ("GS", "\(stats.gamesStarted)"),
                    ("W", "\(stats.wins)"), ("L", "\(stats.losses)"),
                    ("SV", "\(stats.saves)"), ("IP", stats.inningsPitched),
                    ("H", "\(stats.hits)"), ("ER", "\(stats.earnedRuns)"),
                    ("HR", "\(stats.homeRuns)"), ("BB", "\(stats.walks)"),
                    ("SO", "\(stats.strikeouts)"), ("ERA", decimal(stats.era, digits: 2)),
                    ("WHIP", rate(stats.whip)),
                ])
            } else if let stats = player.careerStats?.batting {
                statGrid([
                    ("G", "\(stats.games)"), ("PA", "\(stats.plateAppearances)"),
                    ("AB", "\(stats.atBats)"), ("R", "\(stats.runs)"),
                    ("H", "\(stats.hits)"), ("2B", "\(stats.doubles)"),
                    ("3B", "\(stats.triples)"), ("HR", "\(stats.homeRuns)"),
                    ("RBI", "\(stats.runsBattedIn)"), ("BB", "\(stats.walks)"),
                    ("SO", "\(stats.strikeouts)"), ("SB", "\(stats.stolenBases)"),
                    ("AVG", rate(stats.average)), ("OBP", rate(stats.onBasePercentage)),
                    ("SLG", rate(stats.sluggingPercentage)), ("OPS", rate(stats.ops)),
                ])
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Career statistics are not available in the completed 2025 data release.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.ink)
                    Text("This usually means the player debuted in 2026 or has not yet appeared in an MLB game.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
    }

    private func statGrid(_ values: [(String, String)]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: contentWidth >= 700 ? 7 : 4),
            spacing: 0
        ) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 3) {
                    Text(item.0)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(AppColor.darkRed)
                    Text(item.1)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AppColor.ink)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay(alignment: .trailing) { Divider() }
                .overlay(alignment: .bottom) { Divider() }
            }
        }
    }

    private func rate(_ value: Double?) -> String {
        guard let value else { return "—" }
        let rendered = String(format: "%.3f", value)
        return rendered.hasPrefix("0.") ? String(rendered.dropFirst()) : rendered
    }

    private func decimal(_ value: Double?, digits: Int) -> String {
        guard let value else { return "—" }
        return String(format: "%.*f", digits, value)
    }

    private func referenceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(AppColor.darkRed)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppColor.paper)
                .overlay(alignment: .bottom) { Rectangle().fill(AppColor.teamAccent).frame(height: 1) }
            content()
        }
    }

    private var teamsTable: some View {
        VStack(spacing: 0) {
            ForEach(Array(player.teams.enumerated()), id: \.offset) { index, team in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColor.ink)
                        .frame(width: 22, alignment: .trailing)
                    Text(team)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.ink)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                if index < player.teams.count - 1 { Divider().padding(.leading, 44) }
            }
        }
    }

    private var educationRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if player.education.entries.isEmpty {
                Text("No college or school is listed in the open data record.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.ink)
                    .padding(12)
            } else {
                ForEach(player.education.entries, id: \.self) { entry in
                    Text(entry)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.ink)
                        .padding(12)
                }
            }
        }
    }

    private var sourceRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(source?.attribution ?? "Open Wikimedia data")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.ink)
            if let statsAttribution = source?.statsAttribution {
                Text(statsAttribution)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.ink)
            }
            HStack(spacing: 18) {
                if let url = player.sourceURL { Link("Wikidata record", destination: url) }
                if let url = player.articleURL { Link("Wikipedia article", destination: url) }
                if let value = source?.statsUrl, let url = URL(string: value) {
                    Link("Retrosheet", destination: url)
                }
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AppColor.darkRed)
        }
        .padding(12)
    }
}

#Preview {
    PlayersView()
        .environment(\.hubContentWidth, 390)
}
