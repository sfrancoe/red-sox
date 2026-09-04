import SwiftUI

struct StandingsView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @State private var store = StandingsStore()

    var body: some View {
        ZStack {
            AppColor.paleRed.ignoresSafeArea()

            Group {
                if let feed = store.feed {
                    standingsContent(feed)
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

    private func standingsContent(_ feed: StandingsFeed) -> some View {
        VStack(spacing: 0) {
            modePicker

            ScrollView {
                LazyVStack(spacing: 5) {
                    if store.mode == .divisions {
                        HubCardGrid(minimumWidth: 440, compactSpacing: 5) {
                            ForEach(feed.divisions) { division in
                                standingsCard(
                                    title: division.name,
                                    teams: division.teams,
                                    gamesBackTitle: "GB",
                                    showsCutoff: false
                                )
                            }
                        }
                    } else {
                        standingsCard(
                            title: "AL Wild Card",
                            teams: feed.wildCard,
                            gamesBackTitle: "WCGB",
                            showsCutoff: true
                        )

                        Text("Top three teams hold the wild-card positions.")
                            .font(.system(size: contentWidth >= 650 ? 13 : 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    Text("Updated \(feed.updatedText) · \(feed.source)")
                        .font(.system(size: contentWidth >= 650 ? 12 : 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
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
        showsCutoff: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            standingsHeader(title: title, gamesBackTitle: gamesBackTitle)

            ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                if showsCutoff && index == 3 {
                    cutoffLine
                }
                standingsRow(team, gamesBackTitle: gamesBackTitle)
            }
        }
        .cardStyle(padding: 10)
    }

    private func standingsHeader(title: String, gamesBackTitle: String) -> some View {
        HStack(spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: contentWidth >= 650 ? 18 : 16, weight: .black))
                .foregroundStyle(AppColor.navy)
                .frame(width: contentWidth >= 650 ? 160 : nil, alignment: .leading)
                .frame(maxWidth: contentWidth >= 650 ? nil : .infinity, alignment: .leading)
            Text("W").frame(minWidth: 28, maxWidth: contentWidth >= 650 ? .infinity : (28))
            Text("L").frame(minWidth: 28, maxWidth: contentWidth >= 650 ? .infinity : (28))
            Text("PCT").frame(minWidth: 46, maxWidth: contentWidth >= 650 ? .infinity : (46))
            Text(gamesBackTitle).frame(minWidth: gamesBackTitle == "WCGB" ? 48 : 38, maxWidth: contentWidth >= 650 ? .infinity : (gamesBackTitle == "WCGB" ? 48 : 38))
            Text("L10").frame(minWidth: 42, maxWidth: contentWidth >= 650 ? .infinity : (42))
            Text("STRK").frame(minWidth: 38, maxWidth: contentWidth >= 650 ? .infinity : (38))
        }
        .font(.system(size: contentWidth >= 650 ? 13 : 11, weight: .black))
        .foregroundStyle(AppColor.hunterGreen)
        .padding(.horizontal, 5)
        .padding(.bottom, 2)
    }

    private func standingsRow(_ team: StandingsTeam, gamesBackTitle: String) -> some View {
        let gamesBack = gamesBackTitle == "WCGB" ? team.wildCardGamesBack : team.gamesBack
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                Text(team.rank)
                    .font(.system(size: contentWidth >= 650 ? 14 : 12, weight: team.isRedSox ? .black : .bold, design: .monospaced))
                    .foregroundStyle(AppColor.hunterGreen)
                    .frame(width: 15)
                Text(team.cityName)
                    .font(.system(size: contentWidth >= 650 ? 16 : 14, weight: team.isRedSox ? .black : .semibold))
                    .lineLimit(1)
            }
            .frame(width: contentWidth >= 650 ? 160 : nil, alignment: .leading)
                .frame(maxWidth: contentWidth >= 650 ? nil : .infinity, alignment: .leading)

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
                .font(.system(size: contentWidth >= 650 ? 16 : 14, weight: team.isRedSox ? .black : .bold, design: .monospaced))
                .foregroundStyle(team.streak.hasPrefix("W") ? AppColor.green : AppColor.red)
                .frame(minWidth: 38, maxWidth: contentWidth >= 650 ? .infinity : (38))
        }
        .font(.system(size: contentWidth >= 650 ? 16 : 14, weight: .semibold, design: .monospaced))
        .foregroundStyle(team.isRedSox ? AppColor.navy : AppColor.hunterGreen)
        .padding(.horizontal, 5)
        .padding(.vertical, contentWidth >= 650 ? 13 : 7)
        .background(team.isRedSox ? AppColor.paleBlue : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func tableValue(
        _ value: String,
        width: CGFloat,
        emphasized: Bool = false
    ) -> some View {
        Text(value)
            .font(.system(size: contentWidth >= 650 ? 16 : 14, weight: emphasized ? .black : .semibold, design: .monospaced))
            .foregroundStyle(emphasized ? AppColor.navy : AppColor.hunterGreen)
            .frame(minWidth: width, maxWidth: contentWidth >= 650 ? .infinity : (width))
    }

    private var cutoffLine: some View {
        HStack(spacing: 8) {
            Rectangle().fill(AppColor.red.opacity(0.55)).frame(height: 1)
            Text("PLAYOFF CUT")
                .font(.system(size: contentWidth >= 650 ? 13 : 11, weight: .black))
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
