import SwiftUI

struct ScheduleView: View {
    @State private var store = ScheduleStore()

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.cream.ignoresSafeArea()

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
            LazyVStack(spacing: 10) {
                masthead(gameCount: schedule.games.count)

                ForEach(schedule.games) { game in
                    scheduleRow(game)
                }

                Text("Schedule through \(formattedSeasonEnd(schedule.regularSeasonEnd)) · \(schedule.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .foregroundStyle(AppColor.ink)
        }
        .refreshable {
            await store.load()
        }
    }

    private func masthead(gameCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("THE STRETCH RUN")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(AppColor.red)
                Text("Schedule")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(AppColor.navy)
                Text("\(gameCount) games remaining")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "calendar")
                .font(.title)
                .foregroundStyle(AppColor.red)
        }
        .padding(.bottom, 6)
    }

    private func scheduleRow(_ game: ScheduledGame) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(game.formattedDay.uppercased())
                    .font(.caption.weight(.black))
                    .tracking(0.5)

                Text("·")
                    .foregroundStyle(.secondary)

                Text(game.formattedTime)
                    .font(.caption.weight(.bold))

                Spacer()

                Text(game.location == "home" ? "HOME" : "AWAY")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(AppColor.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColor.paleBlue)
                    .clipShape(Capsule())
            }

            HStack(spacing: 5) {
                Text(game.locationWord)
                    .foregroundStyle(.secondary)
                Text(game.opponent)
                    .fontWeight(.bold)
                Text("(\(game.opponentRecord))")
                    .foregroundStyle(.secondary)

                if let matchup = game.probableMatchup {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(matchup)
                        .foregroundStyle(AppColor.green)
                }
            }
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .cardStyle()
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
