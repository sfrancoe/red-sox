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
            VStack(spacing: 0) {
                LazyVStack(spacing: 0) {
                    scheduleHeader

                    Divider()
                        .overlay(AppColor.navy.opacity(0.22))

                    ForEach(Array(schedule.games.enumerated()), id: \.element.id) { index, game in
                        scheduleRow(game)

                        if index < schedule.games.count - 1 {
                            Divider()
                                .overlay(AppColor.border.opacity(0.9))
                        }
                    }
                }
                .background(AppColor.paper)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppColor.border.opacity(0.85), lineWidth: 1)
                }
                .shadow(color: AppColor.navy.opacity(0.08), radius: 12, y: 4)

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

    private var scheduleHeader: some View {
        HStack(spacing: 8) {
            Text("DATE")
                .frame(width: 76, alignment: .leading)
            Text("TIME")
                .frame(width: 54, alignment: .leading)
            Text("MATCHUP")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("REC")
                .frame(width: 44, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .black))
        .tracking(0.55)
        .foregroundStyle(AppColor.red)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func scheduleRow(_ game: ScheduledGame) -> some View {
        HStack(spacing: 8) {
            Text(game.formattedDay.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(0.2)
                .foregroundStyle(AppColor.navy)
                .frame(width: 76, alignment: .leading)

            Text(game.formattedTime)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 54, alignment: .leading)

            HStack(spacing: 3) {
                Text(game.locationWord)
                    .foregroundStyle(.secondary)

                Text(game.opponent)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.navy)

                if game.doubleheader {
                    Text("G\(game.gameNumber)")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(AppColor.red)
                }

                if let matchup = game.probableMatchup {
                    Text("· \(matchup)")
                        .foregroundStyle(AppColor.green)
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(game.opponentRecord)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
