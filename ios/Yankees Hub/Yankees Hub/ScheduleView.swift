import SwiftUI

struct ScheduleView: View {
    @Environment(\.hubContentWidth) private var contentWidth
    @State private var store = ScheduleStore()
    @State private var selectedGameID: Int?

    private let weekdayLabels = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paleRed.ignoresSafeArea()

                Group {
                    if let schedule = store.schedule {
                        scheduleContent(schedule)
                    } else if store.isLoading {
                        ProgressView("Loading the schedule…")
                            .tint(.white)
                            .foregroundStyle(.white)
                    } else {
                        errorView
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await loadSchedule()
        }
    }

    private func scheduleContent(_ schedule: Schedule) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if contentWidth >= 850 {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 16) {
                            ForEach(calendarMonths(for: schedule)) { month in
                                monthCard(month, schedule: schedule)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        if let game = selectedGame(in: schedule) {
                            gameDetailCard(game)
                                .frame(width: 340)
                        }
                    }
                } else {
                    ForEach(calendarMonths(for: schedule)) { month in
                        monthCard(month, schedule: schedule)
                    }
                    if let game = selectedGame(in: schedule) {
                        gameDetailCard(game)
                    }
                }

                Text("\(schedule.games.count) games remaining · Through \(formattedSeasonEnd(schedule.regularSeasonEnd))")
                    .font(.system(size: contentWidth >= 650 ? 12 : 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .padding(.vertical, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .foregroundStyle(AppColor.ink)
        }
        .refreshable {
            await loadSchedule()
        }
    }

    private func monthCard(_ month: CalendarMonth, schedule: Schedule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(month.title.uppercased())
                .font(.system(size: contentWidth >= 650 ? 19 : 17, weight: .black))
                .tracking(0.8)
                .foregroundStyle(AppColor.navy)

            LazyVGrid(columns: calendarColumns, spacing: 3) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: contentWidth >= 650 ? 12 : 8, weight: .black))
                        .tracking(0.25)
                        .foregroundStyle(AppColor.hunterGreen)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(month.days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date, games: games(on: date, in: schedule))
                    } else {
                        Color.clear
                            .frame(height: contentWidth >= 650 ? 92 : 67)
                    }
                }
            }
        }
        .cardStyle(padding: 12)
    }

    private func dayCell(_ date: Date, games: [ScheduledGame]) -> some View {
        let game = games.first
        let selected = games.contains { $0.id == selectedGameID }
        let accent = game?.location == "home" ? AppColor.red : AppColor.hunterGreen

        return VStack(spacing: 3) {
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: contentWidth >= 650 ? 13 : 11, weight: .bold))
                .foregroundStyle(selected ? Color.white : AppColor.navy)

            if let game {
                Text("\(game.locationWord) \(opponentCode(game.opponent))")
                    .font(.system(size: contentWidth >= 650 ? 12 : 10, weight: .black))
                    .foregroundStyle(selected ? Color.white : accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(game.formattedTime)
                    .font(.system(size: contentWidth >= 650 ? 12 : 7, weight: .semibold))
                    .foregroundStyle(selected ? Color.white.opacity(0.88) : AppColor.ink.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if games.count > 1 || game.doubleheader {
                    Text("DH")
                        .font(.system(size: contentWidth >= 650 ? 12 : 7, weight: .black))
                        .foregroundStyle(selected ? Color.white : AppColor.red)
                }
            } else {
                Text("—")
                    .font(.system(size: contentWidth >= 650 ? 12 : 8, weight: .medium))
                    .foregroundStyle(AppColor.border)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: contentWidth >= 650 ? 92 : 67)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? accent : game == nil ? AppColor.paleBlue.opacity(0.36) : accent.opacity(0.09))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    selected ? accent : isToday(date) ? AppColor.navy : AppColor.border.opacity(0.75),
                    lineWidth: selected || isToday(date) ? 1.5 : 0.7
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            if let game {
                withAnimation(.easeOut(duration: 0.18)) {
                    selectedGameID = game.id
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(game == nil ? [] : .isButton)
    }

    private func gameDetailCard(_ game: ScheduledGame) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.fullFormattedDay.uppercased())
                        .font(.system(size: contentWidth >= 650 ? 16 : 14, weight: .black))
                        .tracking(0.45)
                        .foregroundStyle(AppColor.red)

                    Text("\(game.locationWord) \(game.opponent)")
                        .font(.system(size: contentWidth >= 650 ? 26 : 24, weight: .black))
                        .foregroundStyle(AppColor.navy)
                }

                Spacer()

                Text(game.formattedTime)
                    .font(.system(size: contentWidth >= 650 ? 22 : 20, weight: .black))
                    .foregroundStyle(AppColor.hunterGreen)
            }

            Divider()

            HStack {
                detailItem("VENUE", game.venue)
                Spacer()
                detailItem("OPPONENT", game.opponentRecord, alignment: .trailing)
            }

            if game.showProbables {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PROJECTED STARTERS")
                        .font(.system(size: contentWidth >= 650 ? 15 : 13, weight: .black))
                        .tracking(0.45)
                        .foregroundStyle(AppColor.red)

                    HStack(alignment: .top) {
                        starterDetail(
                            "NEW YORK",
                            pitcherName(game.favoriteTeamPitcher),
                            game.favoriteTeamPitcherRecord
                        )
                        Spacer()
                        Text("VS.")
                            .font(.system(size: contentWidth >= 650 ? 14 : 12, weight: .black))
                            .foregroundStyle(AppColor.border)
                            .padding(.top, 13)
                        Spacer()
                        starterDetail(
                            game.opponent.uppercased(),
                            pitcherName(game.opponentPitcher),
                            game.opponentPitcherRecord,
                            alignment: .trailing
                        )
                    }
                }
                .padding(14)
                .background(AppColor.paleBlue.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if game.doubleheader {
                Text("DOUBLEHEADER · GAME \(game.gameNumber)")
                    .font(.system(size: contentWidth >= 650 ? 12 : 9, weight: .black))
                    .foregroundStyle(AppColor.red)
            }
        }
        .cardStyle(padding: 16)
    }

    private func detailItem(
        _ label: String,
        _ value: String,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.system(size: contentWidth >= 650 ? 13 : 11, weight: .black))
                .tracking(0.35)
                .foregroundStyle(AppColor.hunterGreen)
            Text(value.isEmpty ? "To be announced" : value)
                .font(.system(size: contentWidth >= 650 ? 19 : 17, weight: .bold))
                .foregroundStyle(AppColor.ink)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
        }
    }

    private func starterDetail(
        _ label: String,
        _ name: String,
        _ record: String?,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(label)
                .font(.system(size: contentWidth >= 650 ? 12 : 10, weight: .black))
                .tracking(0.35)
                .foregroundStyle(AppColor.hunterGreen)
            Text(name)
                .font(.system(size: contentWidth >= 650 ? 20 : 18, weight: .black))
                .foregroundStyle(AppColor.navy)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
            if !name.isEmpty, name != "To be announced" {
                Text(recordLabel(record))
                    .font(.system(size: contentWidth >= 650 ? 16 : 14, weight: .bold))
                    .foregroundStyle(AppColor.hunterGreen)
            }
        }
    }

    private func recordLabel(_ value: String?) -> String {
        guard let value, !value.isEmpty, value != "—" else {
            return "Record unavailable"
        }
        return value.replacingOccurrences(of: "-", with: "–")
    }

    private func loadSchedule() async {
        await store.load()
        guard let schedule = store.schedule else { return }
        if selectedGameID == nil || !schedule.games.contains(where: { $0.id == selectedGameID }) {
            selectedGameID = schedule.games.first?.id
        }
    }

    private func selectedGame(in schedule: Schedule) -> ScheduledGame? {
        schedule.games.first { $0.id == selectedGameID } ?? schedule.games.first
    }

    private func games(on date: Date, in schedule: Schedule) -> [ScheduledGame] {
        schedule.games.filter { game in
            guard let gameDate = game.date else { return false }
            return easternCalendar.isDate(gameDate, inSameDayAs: date)
        }
    }

    private func calendarMonths(for schedule: Schedule) -> [CalendarMonth] {
        guard let firstGameDate = schedule.games.first?.date,
              let seasonEnd = seasonEndDate(schedule.regularSeasonEnd) else {
            return []
        }

        var cursor = firstDayOfMonth(firstGameDate)
        let finalMonth = firstDayOfMonth(seasonEnd)
        var months: [CalendarMonth] = []

        while cursor <= finalMonth {
            let dayRange = easternCalendar.range(of: .day, in: .month, for: cursor) ?? 1..<2
            let leadingBlanks = easternCalendar.component(.weekday, from: cursor) - 1
            var days = Array<Date?>(repeating: nil, count: leadingBlanks)
            days.append(contentsOf: dayRange.compactMap { day in
                easternCalendar.date(byAdding: .day, value: day - 1, to: cursor)
            }.map(Optional.some))
            while days.count % 7 != 0 {
                days.append(nil)
            }

            months.append(
                CalendarMonth(
                    id: monthID(cursor),
                    title: cursor.formatted(.dateTime.month(.wide).year()),
                    days: days
                )
            )
            guard let next = easternCalendar.date(byAdding: .month, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return months
    }

    private var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func firstDayOfMonth(_ date: Date) -> Date {
        let components = easternCalendar.dateComponents([.year, .month], from: date)
        return easternCalendar.date(from: components) ?? date
    }

    private func seasonEndDate(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return easternCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func monthID(_ date: Date) -> String {
        let parts = easternCalendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    private func isToday(_ date: Date) -> Bool {
        easternCalendar.isDateInToday(date)
    }

    private func pitcherName(_ value: String) -> String {
        value.isEmpty ? "To be announced" : value
    }

    private func opponentCode(_ opponent: String) -> String {
        [
            "Angels": "LAA", "Astros": "HOU", "Athletics": "ATH",
            "Blue Jays": "TOR", "Braves": "ATL", "Brewers": "MIL",
            "Cardinals": "STL", "Cubs": "CHC", "Diamondbacks": "ARI",
            "Dodgers": "LAD", "Giants": "SF", "Guardians": "CLE",
            "Mariners": "SEA", "Marlins": "MIA", "Mets": "NYM",
            "Nationals": "WSH", "Orioles": "BAL", "Padres": "SD",
            "Phillies": "PHI", "Pirates": "PIT", "Rangers": "TEX",
            "Rays": "TB", "Reds": "CIN", "Rockies": "COL",
            "Royals": "KC", "Tigers": "DET", "Twins": "MIN",
            "White Sox": "CWS", "Yankees": "NYY"
        ][opponent] ?? String(opponent.prefix(3)).uppercased()
    }

    private func formattedSeasonEnd(_ value: String) -> String {
        guard let date = seasonEndDate(value) else { return value }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Schedule Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(store.errorMessage ?? "The schedule could not be loaded.")
        } actions: {
            Button("Try Again") {
                Task { await loadSchedule() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.red)
        }
    }
}

private struct CalendarMonth: Identifiable {
    let id: String
    let title: String
    let days: [Date?]
}

#Preview {
    ScheduleView()
}
