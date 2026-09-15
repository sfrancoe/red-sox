import SwiftUI

struct SeasonLeadersView: View {
    @State private var store: SeasonLeadersStore
    @State private var scope: LeaderboardScope = .mlb
    @State private var detail: LeaderboardDetail?
    private let team: HubTeam

    init(team: HubTeam = .boston) {
        self.team = team
        _store = State(initialValue: SeasonLeadersStore(team: team))
    }

    var body: some View {
        ZStack {
            AppColor.paleRed.ignoresSafeArea()
            if store.seasons.isEmpty && !store.isLoading { errorView }
            else { VStack(spacing: 0) { scopeControl; content } }
        }
        .navigationTitle("Season Leaders")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load()
            if scope != .team { for year in store.sortedYears { await store.loadComparison(year: year) } }
        }
        .sheet(item: $detail) { LeaderboardDetailSheet(detail: $0) }
    }

    private var scopeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Compare leaders").font(.caption.weight(.bold)).tracking(0.5)
            Picker("Compare leaders", selection: $scope) {
                ForEach(LeaderboardScope.allCases) { item in
                    Text(item.title(for: team)).tag(item).accessibilityLabel(item.accessibilityTitle(for: team))
                }
            }.pickerStyle(.segmented)
            if scope == .team { Text("See how your team stacks up in \(team.definition.league) and MLB.").font(.caption) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10).background(AppColor.paleRed)
        .onChange(of: scope) { newScope in
            guard newScope != .team else { return }
            Task { for year in store.sortedYears { await store.loadComparison(year: year) } }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if store.seasons.isEmpty { ProgressView("Loading season leaders…").padding(.top, 48) }
                else {
                    HubCardGrid {
                        ForEach(store.sortedYears, id: \.self) { year in
                            if let season = store.seasons[year] { yearCard(year: year, season: season) }
                        }
                    }
                    Text("AVG and OPS use qualified hitters. WHIP requires at least 40 innings.")
                        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(16).foregroundStyle(AppColor.ink)
        }
        .refreshable {
            await store.load()
            if scope != .team { for year in store.sortedYears { await store.retryComparison(year: year) } }
        }
    }

    private func yearCard(year: String, season: SeasonLeaders) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            yearHeader(year: year, season: season)
            VStack(spacing: 0) {
                if scope == .team {
                    ForEach(Array(season.categories.enumerated()), id: \.element.id) { index, category in
                        teamCategory(category)
                        if index < season.categories.count - 1 { divider }
                    }
                } else { comparisonCategories(year: year) }
            }
        }.cardStyle().animation(.easeInOut(duration: 0.18), value: scope)
    }

    @ViewBuilder private func comparisonCategories(year: String) -> some View {
        if let payload = store.comparison(year: year), let key = scope.payloadKey(for: team), let categories = payload.scopes[key] {
            ForEach(Array(SeasonLeaders.categoryTitles.enumerated()), id: \.element) { index, title in
                comparisonCategory(title: title, category: categories[title.lowercased()], year: year, payload: payload)
                if index < SeasonLeaders.categoryTitles.count - 1 { divider }
            }
        } else if let error = store.comparisonErrors[year] {
            VStack(alignment: .leading, spacing: 8) {
                Text(error).font(.subheadline.weight(.semibold))
                HStack { Button("Retry") { Task { await store.retryComparison(year: year) } }; Button("Back to Team") { scope = .team } }.buttonStyle(.bordered)
            }.padding(.vertical, 12)
        } else { ProgressView("Loading league leaders…").padding(.vertical, 28) }
    }

    private func yearHeader(year: String, season: SeasonLeaders) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(year).font(.system(size: 32, weight: .black, design: .rounded)).foregroundStyle(isCurrentSeason(year) ? AppColor.red : AppColor.navy)
                Image(systemName: "crown.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(AppColor.accent)
            }
            Spacer()
            Text(scope == .team ? season.record : scope.heading(for: team)).font(.subheadline.weight(.bold))
        }
    }

    private func teamCategory(_ category: LeaderCategory) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(category.title).font(.subheadline.weight(.black)).tracking(0.7).foregroundStyle(AppColor.green)
            ForEach(Array(category.leaders.prefix(10).enumerated()), id: \.element.id) { index, leader in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    rankText("\(index + 1)"); LeaderName(name: leader.name, abbreviation: team.abbreviation); Spacer(minLength: 2)
                    Text(leader.value).fontWeight(index == 0 ? .bold : .regular).monospacedDigit()
                }.font(.callout)
            }
        }.padding(.vertical, 10)
    }

    private func comparisonCategory(title: String, category: ComparisonCategory?, year: String, payload: LeagueLeadersPayload) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.black)).tracking(0.7).foregroundStyle(AppColor.green)
                Text(category?.eligibility ?? "Comparison unavailable").font(.caption).foregroundStyle(AppColor.ink.opacity(0.7))
            }
            if let category, category.isAvailable {
                ForEach(category.topTen) { leader in
                    CompactLeaderRow(leader: leader, selectedTeamID: team.definition.mlbID)
                }
                let supplement = category.teamSupplement(teamID: team.definition.mlbID)
                if !supplement.isEmpty {
                    Divider().padding(.top, 5)
                    Text("\(team.abbreviation) · TEAM TOP 3")
                        .font(.caption.weight(.bold)).foregroundStyle(AppColor.green).padding(.top, 3)
                    ForEach(supplement) { leader in
                        CompactLeaderRow(leader: leader, selectedTeamID: team.definition.mlbID)
                    }
                }
                Button("Category details & source") { detail = LeaderboardDetail(year: year, title: title, scopeName: scope.heading(for: team), category: category, generatedAt: payload.generatedAt, teamID: team.definition.mlbID, teamName: team.definition.shortName) }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            } else { Text(category?.message ?? "Comparison unavailable.").font(.subheadline) }
        }.padding(.vertical, 10)
    }

    private func rankText(_ text: String) -> some View { Text(text).font(.subheadline.weight(.black)).foregroundStyle(AppColor.red).frame(minWidth: 28, alignment: .leading) }
    private var divider: some View { Divider().overlay(AppColor.navy.opacity(0.5)) }
    private func isCurrentSeason(_ year: String) -> Bool { year == String(Calendar.current.component(.year, from: .now)) }
    private var errorView: some View {
        ContentUnavailableView { Label("Leaders Unavailable", systemImage: "wifi.exclamationmark") } description: { Text(store.errorMessage ?? "The season leaders could not be loaded.") } actions: { Button("Try Again") { Task { await store.load() } }.buttonStyle(HubProminentButtonStyle()).tint(AppColor.red) }
    }
}

private struct LeaderboardDetail: Identifiable {
    let year: String; let title: String; let scopeName: String; let category: ComparisonCategory; let generatedAt: String; let teamID: Int; let teamName: String
    var id: String { "\(year)-\(scopeName)-\(title)" }
}

private struct LeaderboardDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let detail: LeaderboardDetail
    var body: some View {
        NavigationStack {
            List {
                Section("\(detail.year) · \(detail.scopeName)") { Text(detail.title).font(.title2.weight(.bold)); Text(detail.category.eligibility) }
                Section("Top 10") { ForEach(detail.category.topTen) { leaderRow($0) } }
                let teamOutsideTopTen = detail.category.teamSupplement(teamID: detail.teamID)
                if !teamOutsideTopTen.isEmpty {
                    Section("\(detail.teamName) · Top 3") { ForEach(teamOutsideTopTen) { leaderRow($0) } }
                }
                Section("Source") { Text("MLB Stats API · Generated \(detail.generatedAt)").font(.footnote) }
            }.environment(\.defaultMinListRowHeight, 28)
                .scrollContentBackground(.hidden).background(AppColor.night).foregroundStyle(AppColor.ink)
                .navigationTitle("League Leaders").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }

    private func leaderRow(_ leader: ComparisonLeader) -> some View {
        CompactLeaderRow(leader: leader, selectedTeamID: detail.teamID)
            .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
    }
}

private struct LeaderName: View {
    let name: String
    let abbreviation: String
    var body: some View {
        (Text(name) + Text("  \(abbreviation)").font(.caption.weight(.semibold)).foregroundColor(AppColor.ink.opacity(0.65)))
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }
}

private struct CompactLeaderRow: View {
    let leader: ComparisonLeader
    let selectedTeamID: Int
    private var isSelectedTeam: Bool { leader.teamID == selectedTeamID }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(leader.rankText).font(.caption.weight(.black)).foregroundStyle(AppColor.red)
                .frame(minWidth: 30, alignment: .leading)
            LeaderName(name: leader.name, abbreviation: leader.teamAbbreviation ?? "TOT")
            if isSelectedTeam {
                Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(AppColor.green)
            }
            Spacer(minLength: 2)
            Text(leader.displayValue).fontWeight(leader.rank == 1 ? .bold : .regular).monospacedDigit()
        }
        .font(.callout).padding(.horizontal, 4).padding(.vertical, 2)
        .background(isSelectedTeam ? AppColor.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(leader.name), \(leader.teamAbbreviation ?? "multiple teams"), \(leader.tied ? "tied for" : "ranked") \(leader.rank), \(leader.displayValue)\(isSelectedTeam ? ", your team" : "")")
    }
}

private extension SeasonLeaders { static let categoryTitles = ["HR", "AVG", "OPS", "RBI", "WHIP", "WAR"] }

#Preview { NavigationStack { SeasonLeadersView() } }
