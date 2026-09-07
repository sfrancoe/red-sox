import SwiftUI

struct StandingsView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @State private var store: StandingsStore

    init(team: HubTeam = .boston) {
        _store = State(initialValue: StandingsStore(team: team))
    }

    var body: some View {
        ZStack {
            AppColor.paleRed.ignoresSafeArea()

            Group {
                if store.feeds.count == StandingsLeague.allCases.count {
                    if contentWidth >= 650 {
                        tabletStandingsContent
                    } else {
                        phoneStandingsContent
                    }
                } else if store.isLoading {
                    ProgressView("Loading standings…")
                        .tint(.white)
                        .foregroundStyle(.white)
                } else {
                    errorView
                }
            }
        }
        .navigationTitle("Standings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColor.paleRed, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await store.load()
        }
    }

    private var phoneStandingsContent: some View {
        VStack(spacing: 0) {
            modePicker

            ScrollView {
                LazyVStack(spacing: 5) {
                    if let league = store.mode.league,
                       let feed = store.feeds[league] {
                        HubCardGrid(minimumWidth: 440, compactSpacing: 5) {
                            ForEach(feed.divisions) { division in
                                standingsCard(
                                    title: division.name,
                                    teams: division.teams,
                                    gamesBackTitle: "GB",
                                    showsCutoff: false,
                                    highlightsFavorite: league == store.selectedLeague
                                )
                            }
                        }
                    } else if let feed = store.feeds[store.selectedLeague] {
                        standingsCard(
                            title: "\(store.selectedLeague.shortName) Wild Card",
                            teams: feed.wildCard,
                            gamesBackTitle: "WCGB",
                            showsCutoff: true,
                            highlightsFavorite: true
                        )

                        Text("Top three teams hold the wild-card positions.")
                            .font(.system(size: contentWidth >= 650 ? 13 : 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    standingsFooter
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .foregroundStyle(AppColor.ink)
            }
            .dynamicTypeSize(contentWidth >= 650 ? .large : .xSmall)
            .refreshable {
                await store.load()
            }
        }
        .padding(.top, contentWidth >= 650 ? 16 : 12)
    }

    private var tabletStandingsContent: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(StandingsLeague.allCases) { league in
                    if let feed = store.feeds[league] {
                        leagueSection(feed, league: league)
                    }
                }
                standingsFooter
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(AppColor.ink)
        }
        .dynamicTypeSize(.xSmall)
        .refreshable { await store.load() }
    }

    private func leagueSection(_ feed: StandingsFeed, league: StandingsLeague) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(league.fullName.uppercased())
                .font(.system(size: 13, weight: .black))
                .tracking(0.4)
                .foregroundStyle(.white)

            HStack(alignment: .top, spacing: 5) {
                VStack(spacing: 2) {
                    ForEach(feed.divisions) { division in
                        standingsCard(
                            title: division.name,
                            teams: division.teams,
                            gamesBackTitle: "GB",
                            showsCutoff: false,
                            highlightsFavorite: league == store.selectedLeague,
                            compact: true
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)

                VStack(spacing: 2) {
                    standingsCard(
                        title: "\(league.shortName) Wild Card",
                        teams: feed.wildCard,
                        gamesBackTitle: "WCGB",
                        showsCutoff: true,
                        highlightsFavorite: league == store.selectedLeague,
                        compact: true
                    )
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var standingsFooter: some View {
        let updates = StandingsLeague.allCases.compactMap { store.feeds[$0]?.updatedText }
        let updated = updates.first ?? "—"
        return Text("Updated \(updated) · MLB Stats API")
            .font(.system(size: contentWidth >= 650 ? 12 : 10, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.72))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(StandingsMode.allCases) { mode in
                Button {
                    store.mode = mode
                } label: {
                    Text(mode.title)
                        .font(
                            .system(
                                size: store.mode == mode ? 16 : 13,
                                weight: store.mode == mode ? .black : .semibold
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColor.navy.opacity(0.28), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func standingsCard(
        title: String,
        teams: [StandingsTeam],
        gamesBackTitle: String,
        showsCutoff: Bool,
        highlightsFavorite: Bool,
        compact: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            standingsHeader(title: title, gamesBackTitle: gamesBackTitle, compact: compact)

            ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                if showsCutoff && index == 3 {
                    cutoffLine(compact: compact)
                }
                standingsRow(
                    team,
                    gamesBackTitle: gamesBackTitle,
                    highlightsFavorite: highlightsFavorite,
                    compact: compact
                )
            }
        }
        .cardStyle(padding: compact ? 4 : 10)
    }

    private func standingsHeader(title: String, gamesBackTitle: String, compact: Bool) -> some View {
        let widths = columnWidths(compact: compact, gamesBackTitle: gamesBackTitle)
        return HStack(spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: compact ? 11 : (contentWidth >= 650 ? 18 : 16), weight: .black))
                .foregroundStyle(AppColor.navy)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("W").frame(width: widths.wins)
            Text("L").frame(width: widths.losses)
            Text("PCT").frame(width: widths.pct)
            Text(gamesBackTitle).frame(width: widths.gamesBack)
            Text("L10").frame(width: widths.lastTen)
            Text("STRK").frame(width: widths.streak)
        }
        .font(.system(size: compact ? 8 : (contentWidth >= 650 ? 13 : 11), weight: .black))
        .foregroundStyle(AppColor.hunterGreen)
        .padding(.horizontal, compact ? 2 : 5)
        .padding(.bottom, compact ? 0 : 2)
    }

    private func standingsRow(
        _ team: StandingsTeam,
        gamesBackTitle: String,
        highlightsFavorite: Bool,
        compact: Bool
    ) -> some View {
        let gamesBack = gamesBackTitle == "WCGB" ? team.wildCardGamesBack : team.gamesBack
        let emphasized = highlightsFavorite && team.isFavorite
        let widths = columnWidths(compact: compact, gamesBackTitle: gamesBackTitle)
        return HStack(spacing: 0) {
            HStack(spacing: compact ? 2 : 5) {
                Text(team.rank)
                    .font(.system(size: compact ? 9 : (contentWidth >= 650 ? 14 : 12), weight: emphasized ? .black : .bold, design: .monospaced))
                    .foregroundStyle(AppColor.hunterGreen)
                    .frame(width: compact ? 11 : 15)
                Text(team.cityName)
                    .font(.system(size: compact ? 11 : (contentWidth >= 650 ? 16 : 14), weight: emphasized ? .black : .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            tableValue("\(team.wins)", width: widths.wins, emphasized: emphasized, compact: compact)
            tableValue("\(team.losses)", width: widths.losses, emphasized: emphasized, compact: compact)
            tableValue(team.pct, width: widths.pct, emphasized: emphasized, compact: compact)
            tableValue(
                gamesBack,
                width: widths.gamesBack,
                emphasized: emphasized,
                compact: compact
            )
            tableValue(team.lastTen, width: widths.lastTen, emphasized: emphasized, compact: compact)
            Text(team.streak)
                .font(.system(size: compact ? 10 : (contentWidth >= 650 ? 16 : 14), weight: emphasized ? .black : .bold, design: .monospaced))
                .foregroundStyle(team.streak.hasPrefix("W") ? AppColor.green : AppColor.red)
                .frame(width: widths.streak)
        }
        .font(.system(size: compact ? 10 : (contentWidth >= 650 ? 16 : 14), weight: .semibold, design: .monospaced))
        .foregroundStyle(emphasized ? AppColor.navy : AppColor.hunterGreen)
        .padding(.horizontal, compact ? 2 : 5)
        .padding(.vertical, compact ? 1 : (contentWidth >= 650 ? 13 : 7))
        .background(emphasized ? AppColor.paleBlue : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 9, style: .continuous))
    }

    private func tableValue(
        _ value: String,
        width: CGFloat,
        emphasized: Bool = false,
        compact: Bool = false
    ) -> some View {
        Text(value)
            .font(.system(size: compact ? 10 : (contentWidth >= 650 ? 16 : 14), weight: emphasized ? .black : .semibold, design: .monospaced))
            .foregroundStyle(emphasized ? AppColor.navy : AppColor.hunterGreen)
            .frame(width: width)
    }

    private func columnWidths(compact: Bool, gamesBackTitle: String) -> (
        wins: CGFloat,
        losses: CGFloat,
        pct: CGFloat,
        gamesBack: CGFloat,
        lastTen: CGFloat,
        streak: CGFloat
    ) {
        if compact {
            return (21, 21, 36, gamesBackTitle == "WCGB" ? 37 : 29, 32, 31)
        }
        return (28, 28, 46, gamesBackTitle == "WCGB" ? 48 : 38, 42, 38)
    }

    private func cutoffLine(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(AppColor.red.opacity(0.55)).frame(height: 1)
            Text("PLAYOFF CUT")
                .font(.system(size: compact ? 8 : (contentWidth >= 650 ? 13 : 11), weight: .black))
                .tracking(0.5)
                .foregroundStyle(AppColor.red)
            Rectangle().fill(AppColor.red.opacity(0.55)).frame(height: 1)
        }
        .padding(.vertical, compact ? 0 : 1)
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Standings Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(store.errorMessage ?? "The standings could not be loaded.")
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
    NavigationStack {
        StandingsView()
    }
}
