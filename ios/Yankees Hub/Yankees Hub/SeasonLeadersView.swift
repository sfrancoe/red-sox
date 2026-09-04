import SwiftUI

struct SeasonLeadersView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @State private var store = SeasonLeadersStore()

    var body: some View {
        ZStack {
            AppColor.paleRed.ignoresSafeArea()

            Group {
                if !store.seasons.isEmpty {
                    if contentWidth >= 650 {
                        tabletLeadersContent
                    } else {
                        leadersContent
                    }
                } else if store.isLoading {
                    ProgressView("Loading season leaders…")
                        .tint(.white)
                        .foregroundStyle(.white)
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

    private var tabletLeadersContent: some View {
        VStack(spacing: 10) {
            let years = store.sortedYears
            ForEach(Array(stride(from: 0, to: years.count, by: 2)), id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(Array(years.dropFirst(row).prefix(2)), id: \.self) { year in
                        if let season = store.seasons[year] {
                            VStack(alignment: .leading, spacing: 8) {
                                yearHeader(year: year, season: season)
                                GeometryReader { space in
                                    let rowHeight = max(0, (space.size.height - 8) / 3)
                                    ScrollView {
                                        if space.size.height > space.size.width {
                                            VStack(spacing: 0) {
                                                ForEach(season.categories) { category in
                                                    portraitCategory(category)
                                                        .frame(minHeight: max(0, space.size.height / 6))
                                                }
                                            }
                                        } else {
                                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                                                      alignment: .leading, spacing: 4) {
                                                ForEach(season.categories) { category in
                                                    categoryCell(category, compact: rowHeight < 100)
                                                        .frame(minHeight: rowHeight, alignment: .center)
                                                }
                                            }
                                        }
                                    }
                                    .refreshable { await store.load() }
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(AppColor.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            footer
        }
        .padding(12)
        .foregroundStyle(AppColor.ink)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AVG and OPS use qualified hitters. WHIP requires at least 40 innings.")
                .font(.caption)
            if let metadata = store.metadata {
                Text("Updated \(metadata.updatedText) · MLB + Baseball Reference")
                    .font(.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(Color.white.opacity(0.84))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var leadersContent: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                HubCardGrid {
                    ForEach(store.sortedYears, id: \.self) { year in
                        if let season = store.seasons[year] {
                            yearCard(year: year, season: season)
                        }
                    }
                }

                footer

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
            yearHeader(year: year, season: season)

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

    private func yearHeader(year: String, season: SeasonLeaders) -> some View {
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
    }

    private func portraitCategory(_ category: LeaderCategory) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(category.title)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(AppColor.green)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(AppColor.border)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(category.leaders.prefix(3).enumerated()), id: \.element.id) { index, leader in
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColor.red)
                            .frame(width: 10)
                        Text(leader.name)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(leader.value)
                            .monospacedDigit()
                            .fontWeight(index == 0 ? .bold : .regular)
                    }
                    .font(.system(size: 15))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func categoryCell(_ category: LeaderCategory, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            Text(category.title)
                .font(.caption.weight(.black))
                .tracking(0.7)
                .foregroundStyle(AppColor.green)

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
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
        .padding(.vertical, compact ? 2 : 11)
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
