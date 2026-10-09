import Foundation
import Observation

@MainActor
@Observable
final class HomeStore {
    private let recentStore: RecentGameStore
    private let scheduleStore: ScheduleStore
    private let standingsStore: StandingsStore

    var recentGame: RecentGame? { recentStore.games.first }
    var schedule: Schedule? { scheduleStore.schedule }
    var standings: StandingsFeed? { standingsStore.feeds[standingsStore.selectedLeague] }
    var isLoading: Bool { recentStore.isLoading || scheduleStore.isLoading || standingsStore.isLoading }
    var errorMessage: String? { recentStore.errorMessage ?? scheduleStore.errorMessage ?? standingsStore.errorMessage }
    var sectionErrors: [String] {
        var errors: [String] = []
        if recentStore.errorMessage != nil { errors.append("Game recap unavailable") }
        if scheduleStore.errorMessage != nil { errors.append("Schedule unavailable") }
        if standingsStore.errors[standingsStore.selectedLeague] != nil { errors.append("Standings unavailable") }
        return errors
    }
    var favoriteStanding: StandingsTeam? {
        standings?.divisions.flatMap(\.teams).first(where: \.isFavorite)
    }

    init(team: HubTeam, recent: RecentGameStore, schedule: ScheduleStore, standings: StandingsStore) {
        recentStore = recent
        scheduleStore = schedule
        standingsStore = standings
    }

    func load() async {
        async let recent: Void = recentStore.load() // Also refreshes the shared schedule.
        async let standings: Void = standingsStore.load()
        _ = await (recent, standings)
    }

    func refreshCurrentGame() async { await recentStore.refresh() }
}
