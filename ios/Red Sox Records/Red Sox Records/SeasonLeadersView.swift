import SwiftUI

struct SeasonLeadersView: View {
    @State private var store = SeasonLeadersStore()
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

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
                Text(year)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(year == "2026" ? AppColor.red : AppColor.navy)

                Spacer()

                Text(season.record)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(season.categories) { category in
                    categoryCell(category)
                }
            }
        }
        .cardStyle()
    }

    private func categoryCell(_ category: LeaderCategory) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColor.red)
                Text(category.title)
                    .font(.caption.weight(.black))
                    .tracking(0.7)
                    .foregroundStyle(AppColor.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(category.leaders.prefix(3).enumerated()), id: \.element.id) { index, leader in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(AppColor.red)
                            .frame(width: 10, alignment: .leading)

                        Text(leader.name)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Spacer(minLength: 2)

                        Text(leader.value)
                            .fontWeight(index == 0 ? .bold : .regular)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
        .background(AppColor.paleBlue.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
