import SwiftUI

struct SeasonLeadersView: View {
    @State private var store = SeasonLeadersStore()

    var body: some View {
        ZStack {
            AppColor.paleRed.ignoresSafeArea()

            Group {
                if !store.seasons.isEmpty {
                    leadersContent
                } else if store.isLoading {
                    ProgressView("Loading season leaders…")
                        .tint(AppColor.red)
                } else {
                    errorView
                }
            }
        }
        .navigationTitle("Season Leaders")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load()
        }
    }

    private var leadersContent: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(store.sortedYears, id: \.self) { year in
                    if let season = store.seasons[year] {
                        yearCard(year: year, season: season)
                    }
                }

                Text("AVG and OPS use qualified hitters. WHIP requires at least 40 innings.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.84))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let metadata = store.metadata {
                    Text("Updated \(metadata.updatedText) · MLB + Baseball Reference")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.84))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                }
            }
            .padding(16)
            .foregroundStyle(AppColor.ink)
        }
        .refreshable {
            await store.load()
        }
    }

    private func yearCard(year: String, season: SeasonLeaders) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(year)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(year == "2026" ? AppColor.red : AppColor.navy)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(red: 0.84, green: 0.64, blue: 0.12))
                }

                Spacer()

                Text(season.record)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(season.categories.enumerated()), id: \.element.id) { index, category in
                    categoryCell(category)

                    if index < season.categories.count - 1 {
                        Divider()
                            .overlay(AppColor.border)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func categoryCell(_ category: LeaderCategory) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(category.title)
                .font(.caption.weight(.black))
                .tracking(0.7)
                .foregroundStyle(AppColor.green)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(category.leaders.prefix(3).enumerated()), id: \.element.id) { index, leader in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(AppColor.red)
                            .frame(width: 10, alignment: .leading)

                        Text(leader.name)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        Text(leader.value)
                            .fontWeight(index == 0 ? .bold : .regular)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Leaders Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(store.errorMessage ?? "The season leaders could not be loaded.")
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
        SeasonLeadersView()
    }
}
