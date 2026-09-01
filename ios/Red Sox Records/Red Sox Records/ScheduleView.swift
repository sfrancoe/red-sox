import SwiftUI

struct ScheduleView: View {
    @State private var store = ScheduleStore()

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                Group {
                    if let schedule = store.schedule {
                        scheduleContent(schedule)
                    } else if store.isLoading {
                        ProgressView("Loading the schedule…")
                            .tint(AppColor.red)
                    } else {
                        errorView
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await store.load()
        }
    }

    private func scheduleContent(_ schedule: Schedule) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(schedule.games) { game in
                    scheduleRow(game)
                }

                Text("\(schedule.games.count) games remaining · Through \(formattedSeasonEnd(schedule.regularSeasonEnd))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .foregroundStyle(AppColor.ink)
        }
        .refreshable {
            await store.load()
        }
    }

    private func scheduleRow(_ game: ScheduledGame) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(game.formattedDay.uppercased())
                    .font(.system(size: 12, weight: .black))
                    .tracking(0.5)
                    .foregroundStyle(AppColor.navy)

                Text("·")
                    .foregroundStyle(.secondary)

                Text(game.formattedTime)
                    .font(.system(size: 11, weight: .bold))

                Spacer()

                if game.doubleheader {
                    Text("G\(game.gameNumber)")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(AppColor.navy)
                }

                Text(game.location == "home" ? "HOME" : "AWAY")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(AppColor.red)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppColor.paleBlue)
                    .clipShape(Capsule())
            }

            HStack(spacing: 4) {
                Text(game.locationWord)
                    .foregroundStyle(.secondary)
                Text(game.opponent)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColor.navy)
                Text("(\(game.opponentRecord))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if let matchup = game.probableMatchup {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(matchup)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.green)
                }
            }
            .font(.system(size: 12))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
        .cardStyle(padding: 12)
        .dynamicTypeSize(.xSmall)
    }

    private func formattedSeasonEnd(_ value: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Schedule Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(store.errorMessage ?? "The schedule could not be loaded.")
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
    ScheduleView()
}
