import SwiftUI

struct StandingsView: View {
    @State private var store = StandingsStore()

    var body: some View {
        ZStack {
            AppColor.cream.ignoresSafeArea()

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
        .task {
            await store.load()
        }
    }

    private func standingsContent(_ feed: StandingsFeed) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                statusCard(feed)

                Picker("Standings view", selection: $store.mode) {
                    ForEach(StandingsMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

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

                    Label("The top three teams hold the wild-card positions.", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(AppColor.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                Text("Updated \(feed.updatedText) · \(feed.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
            .padding(16)
            .foregroundStyle(AppColor.ink)
        }
        .refreshable {
            await store.load()
        }
    }

    private func statusCard(_ feed: StandingsFeed) -> some View {
        let redSox = feed.wildCard.first(where: \.isRedSox)
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColor.red)
                    .frame(width: 48, height: 48)
                Image(systemName: "baseball.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("AMERICAN LEAGUE")
                    .font(.caption.weight(.black))
                    .tracking(1)
                    .foregroundStyle(AppColor.green)
                Text("Boston’s playoff position")
                    .font(.headline)
                    .foregroundStyle(AppColor.navy)
                if let redSox {
                    Text("\(redSox.wins)–\(redSox.losses)  ·  WC #\(redSox.rank)  ·  \(redSox.wildCardGamesBack) WCGB")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppColor.red)
                }
            }

            Spacer(minLength: 0)
        }
        .cardStyle()
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
                    .font(.headline.weight(.black))
                    .foregroundStyle(AppColor.navy)
                Spacer()
                if let redSox = teams.first(where: \.isRedSox) {
                    Text("BOSTON: \(ordinalRank(redSox.rank))")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(AppColor.red)
                }
            }
            .padding(.bottom, 12)

            standingsHeader(gamesBackTitle)

            ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                if showsCutoff && index == 3 {
                    cutoffLine
                }
                standingsRow(team, gamesBackTitle: gamesBackTitle)
            }
        }
        .cardStyle()
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
        .font(.caption2.weight(.black))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func standingsRow(_ team: StandingsTeam, gamesBackTitle: String) -> some View {
        let gamesBack = gamesBackTitle == "WCGB" ? team.wildCardGamesBack : team.gamesBack
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                Text(team.rank)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(team.abbreviation)
                    .fontWeight(team.isRedSox ? .black : .bold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            tableValue("\(team.wins)", width: 28)
            tableValue("\(team.losses)", width: 28)
            tableValue(team.pct, width: 46)
            tableValue(gamesBack, width: gamesBackTitle == "WCGB" ? 48 : 38)
            tableValue(team.lastTen, width: 42)
            Text(team.streak)
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(team.streak.hasPrefix("W") ? AppColor.green : AppColor.red)
                .frame(width: 38)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(team.isRedSox ? AppColor.navy : AppColor.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
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

    private func tableValue(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(.caption2.monospacedDigit())
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
                .font(.system(size: 8, weight: .black))
                .tracking(0.5)
                .foregroundStyle(AppColor.red)
            Rectangle().fill(AppColor.red.opacity(0.55)).frame(height: 1)
        }
        .padding(.vertical, 2)
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
