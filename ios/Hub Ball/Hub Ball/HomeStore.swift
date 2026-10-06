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
    private let api: APIClient
    private let team: HubTeam
    var recentGame: RecentGame?
    var schedule: Schedule?
    var standings: StandingsFeed?
    var isLoading = false
    var errorMessage: String?
    private var isRefreshingGame = false

    var favoriteStanding: StandingsTeam? {
        standings?.divisions
            .first(where: { $0.teams.contains(where: \.isFavorite) })?
            .teams.first(where: \.isFavorite)
    }

    init(team: HubTeam = .boston, api: APIClient = .shared) {
        self.api = api
        self.team = team
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let recentData = fetchData("recent-game.json", team: team)
            async let scheduleData = fetchData("schedule.json", team: team)
            async let standingsData = fetchStandings(team: team)
            async let currentGame = fetchCurrentGame(team: team)
            let loaded = try await (recentData, scheduleData, standingsData, currentGame)
            let fallbackGame = try await api.decode(RecentGame.self, from: loaded.0)
            recentGame = loaded.3 ?? fallbackGame
            schedule = try await api.decode(Schedule.self, from: loaded.1)
            standings = try await api.decode(StandingsFeed.self, from: loaded.2)
        } catch {
            errorMessage = "We couldn't load today's \(team.shortName) briefing. Check your connection and try again."
        }
    }

    func refreshCurrentGame() async {
        guard !isLoading, !isRefreshingGame else { return }
        isRefreshingGame = true
        defer { isRefreshingGame = false }
        if let game = await fetchCurrentGame(team: team), !Task.isCancelled {
            recentGame = game
        }
    }

    nonisolated private func fetchData(_ fileName: String, team: HubTeam) async throws -> Data {
        try await api.data(.url(AppBackend.dataURL(fileName, team: team)))
    }

    nonisolated private func fetchStandings(team: HubTeam) async throws -> Data {
        try await api.data(.url(AppBackend.apiURL("mlb/standings", team: team)))
    }

    private func fetchCurrentGame(team: HubTeam) async -> RecentGame? {
        do {
            let client = MLBGameClient(team: team, api: api)
            guard let latest = try await client.gameDescriptors().first else { return nil }
            return try await client.game(
                gamePk: latest.gamePk,
                cachePolicy: latest.isLive ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
            )
        } catch {
            // The published snapshot remains available when the live source is unreachable.
            return nil
        }
    }

}
