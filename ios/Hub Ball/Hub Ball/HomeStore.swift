import Foundation
import Observation

nonisolated struct HomeOddsFeed: Decodable, Sendable {
    let generatedAt: String?
    let sportsbook: String
    let games: [HomeGameOdds]
    let available: Bool
}

nonisolated struct HomeGameOdds: Decodable, Sendable {
    let eventId: String
    let gameDate: String
    let homeTeam: String
    let awayTeam: String
    let sportsbook: String
    let moneyline: Int?
    let runLine: Double?
    let runLinePrice: Int?
    let updatedAt: String?
}

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
