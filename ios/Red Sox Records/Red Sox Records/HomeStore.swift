import Foundation
import Observation

struct HomeOddsFeed: Decodable, Sendable {
    let generatedAt: String?
    let sportsbook: String
    let games: [HomeGameOdds]
    let available: Bool
}

struct HomeGameOdds: Decodable, Sendable {
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
    private let team: HubTeam
    var recentGame: RecentGame?
    var schedule: Schedule?
    var standings: StandingsFeed?
    var isLoading = false
    var errorMessage: String?

    var favoriteStanding: StandingsTeam? {
        standings?.divisions
            .first(where: { $0.teams.contains(where: \.isFavorite) })?
            .teams.first(where: \.isFavorite)
    }

    init(team: HubTeam = .boston) {
        self.team = team
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let recentData = Self.fetchData("recent-game.json", team: team)
            async let scheduleData = Self.fetchData("schedule.json", team: team)
            async let standingsData = Self.fetchData("standings.json", team: team)
            async let currentGame = Self.fetchCurrentGame(team: team)
            let loaded = try await (recentData, scheduleData, standingsData, currentGame)
            let fallbackGame = try Self.decode(RecentGame.self, from: loaded.0)
            recentGame = loaded.3 ?? fallbackGame
            schedule = try Self.decode(Schedule.self, from: loaded.1)
            standings = try Self.decode(StandingsFeed.self, from: loaded.2)
        } catch {
            errorMessage = "We couldn't load today's \(team.shortName) briefing. Check your connection and try again."
        }
    }

    nonisolated private static func fetchData(_ fileName: String, team: HubTeam) async throws -> Data {
        var request = URLRequest(url: AppBackend.dataURL(fileName, team: team))
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw HomeStoreError.badResponse
        }
        return data
    }

    private static func fetchCurrentGame(team: HubTeam) async -> RecentGame? {
        do {
            let client = MLBGameClient(team: team)
            guard let latest = try await client.gameDescriptors().first else { return nil }
            return try await client.game(gamePk: latest.gamePk)
        } catch {
            // The published snapshot remains available when the live source is unreachable.
            return nil
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}

private enum HomeStoreError: Error {
    case badResponse
}
