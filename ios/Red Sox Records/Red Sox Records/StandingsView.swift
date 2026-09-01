import SwiftUI

struct StandingsView: View {
    @State private var store = StandingsStore()

    var body: some View {
        ZStack {
            AppColor.paleRed.ignoresSafeArea()

            Group {
                if let feed = store.feed {
                    standingsContent(feed)
                } else if store.isLoading {
                    ProgressView("Loading standings…")
                        .tint(AppColor.red)
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

    private func standingsContent(_ feed: StandingsFeed) -> some View {
        VStack(spacing: 0) {
            modePicker

            ScrollView {
                LazyVStack(spacing: 5) {
                    if store.mode == .divisions {
                        ForEach(feed.divisions) { division in
                            standingsCard(
                                title: division.name,
                                teams: division.teams,
                                gamesBackTitle: "GB",
                                showsCutoff: false
                            )
                        }
                    } else {
                        standingsCard(
                            title: "AL Wild Card",
                            teams: feed.wildCard,
                            gamesBackTitle: "WCGB",
                            showsCutoff: true
                        )

                        Text("Top three teams hold the wild-card positions.")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    Text("Updated \(feed.updatedText) · \(feed.source)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .foregroundStyle(AppColor.ink)
            }
            .dynamicTypeSize(.xSmall)
            .refreshable {
                await store.load()
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(StandingsMode.allCases) { mode in
                Button {
                    store.mode = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 14, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(store.mode == mode ? AppColor.hunterGreen : Color.white)
                        .background(store.mode == mode ? Color.white : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AppColor.hunterGreen)
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func standingsCard(
        title: String,
        teams: [StandingsTeam],
        gamesBackTitle: String,
        showsCutoff: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(AppColor.navy)
                Spacer()
                if let redSox = teams.first(where: \.isRedSox) {
                    Text("BOSTON: \(ordinalRank(redSox.rank))")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(AppColor.red)
                }
            }
            .padding(.bottom, 5)

            standingsHeader(gamesBackTitle)

            ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                if showsCutoff && index == 3 {
                    cutoffLine
                }
                standingsRow(team, gamesBackTitle: gamesBackTitle)
            }
        }
        .cardStyle(padding: 8)
    }

    private func standingsHeader(_ gamesBackTitle: String) -> some View {
        HStack(spacing: 0) {
            Text("TEAM").frame(maxWidth: .infinity, alignment: .leading)
            Text("W").frame(width: 28)
            Text("L").frame(width: 28)
            Text("PCT").frame(width: 46)
            Text(gamesBackTitle).frame(width: gamesBackTitle == "WCGB" ? 48 : 38)
            Text("L10").frame(width: 42)
            Text("STRK").frame(width: 38)
        }
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(AppColor.hunterGreen)
        .padding(.horizontal, 5)
        .padding(.bottom, 2)
    }

    private func standingsRow(_ team: StandingsTeam, gamesBackTitle: String) -> some View {
        let gamesBack = gamesBackTitle == "WCGB" ? team.wildCardGamesBack : team.gamesBack
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                Text(team.rank)
                    .font(.system(size: 12, weight: team.isRedSox ? .black : .bold, design: .monospaced))
                    .foregroundStyle(AppColor.hunterGreen)
                    .frame(width: 15)
                Text(team.abbreviation)
                    .fontWeight(team.isRedSox ? .black : .bold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            tableValue("\(team.wins)", width: 28, emphasized: team.isRedSox)
            tableValue("\(team.losses)", width: 28, emphasized: team.isRedSox)
            tableValue(team.pct, width: 46, emphasized: team.isRedSox)
            tableValue(
                gamesBack,
                width: gamesBackTitle == "WCGB" ? 48 : 38,
                emphasized: team.isRedSox
            )
            tableValue(team.lastTen, width: 42, emphasized: team.isRedSox)
            Text(team.streak)
                .font(.system(size: 14, weight: team.isRedSox ? .black : .bold, design: .monospaced))
                .foregroundStyle(team.streak.hasPrefix("W") ? AppColor.green : AppColor.red)
                .frame(width: 38)
        }
        .font(.system(size: 14, weight: .semibold, design: .monospaced))
        .foregroundStyle(team.isRedSox ? AppColor.navy : AppColor.hunterGreen)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(team.isRedSox ? AppColor.paleBlue : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(alignment: .leading) {
            if team.isRedSox {
                Capsule()
                    .fill(AppColor.red)
                    .frame(width: 3)
                    .padding(.vertical, 5)
            }
        }
    }

    private func tableValue(
        _ value: String,
        width: CGFloat,
        emphasized: Bool = false
    ) -> some View {
        Text(value)
            .font(.system(size: 14, weight: emphasized ? .black : .semibold, design: .monospaced))
            .foregroundStyle(emphasized ? AppColor.navy : AppColor.hunterGreen)
            .frame(width: width)
    }

    private func ordinalRank(_ rank: String) -> String {
        switch rank {
        case "1": "1ST"
        case "2": "2ND"
        case "3": "3RD"
        default: "\(rank)TH"
        }
    }

    private var cutoffLine: some View {
        HStack(spacing: 8) {
            Rectangle().fill(AppColor.red.opacity(0.55)).frame(height: 1)
            Text("PLAYOFF CUT")
                .font(.system(size: 11, weight: .black))
                .tracking(0.5)
                .foregroundStyle(AppColor.red)
            Rectangle().fill(AppColor.red.opacity(0.55)).frame(height: 1)
        }
        .padding(.vertical, 1)
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
