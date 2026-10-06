import Foundation
import Observation

@MainActor
@Observable
final class PostseasonScorecardStore {
    private(set) var snapshot: RecentGame?
    private(set) var isLoading = false
    private(set) var refreshFailed = false
    private(set) var checkedAt: Date?
    private let selectedGame: PostseasonGame
    private let session: URLSession

    init(game: PostseasonGame, session: URLSession = APIClient.session) {
        selectedGame = game
        self.session = session
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let team = HubTeam.allCases.first(where: { $0.mlbID == selectedGame.away.teamId }) else {
                throw URLError(.unsupportedURL)
            }
            let incoming = try await MLBGameClient(team: team, session: session)
                .game(gamePk: selectedGame.gamePk, cachePolicy: .reloadIgnoringLocalCacheData)
            try Task.checkCancellation()
            guard incoming.gamePk == selectedGame.gamePk,
                  incoming.away.id == selectedGame.away.teamId,
                  incoming.home.id == selectedGame.home.teamId else {
                throw URLError(.badServerResponse)
            }
            snapshot = incoming
            checkedAt = Date()
            refreshFailed = false
        } catch {
            if Task.isCancelled || APIError.isCancellation(error) { return }
            if Task.isCancelled || APIError.isCancellation(error) { return }
            refreshFailed = true
        }
    }
}
