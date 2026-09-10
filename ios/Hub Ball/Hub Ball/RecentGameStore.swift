import Foundation
import Observation

@MainActor
@Observable
final class RecentGameStore {
    private let client: MLBGameClient
    private var cache: [Int: RecentGame] = [:]

    var games: [RecentGame] = []
    var isLoading = false
    var errorMessage: String?

    init(team: HubTeam = .boston) {
        client = MLBGameClient(team: team)
    }

    var hasLiveGame: Bool {
        games.contains(where: \.isLive)
    }

    func load() async {
        await refresh(showLoadingState: games.isEmpty)
    }

    func refresh() async {
        await refresh(showLoadingState: false)
    }

    private func refresh(showLoadingState: Bool) async {
        guard !isLoading else { return }

        isLoading = true
        if showLoadingState {
            errorMessage = nil
        }
        defer { isLoading = false }

        do {
            let descriptors = try await client.gameDescriptors()

            for (index, descriptor) in descriptors.enumerated() {
                let cachedGame = cache[descriptor.gamePk]
                let newestFinalNeedsRecap = index == 0 && !descriptor.isLive
                    && cachedGame?.officialRecap == nil
                let needsFreshFeed = cachedGame == nil || descriptor.isLive
                    || cachedGame?.isLive == true || newestFinalNeedsRecap
                if needsFreshFeed {
                    cache[descriptor.gamePk] = try await client.game(gamePk: descriptor.gamePk)
                }
            }

            let refreshedGames = descriptors.compactMap { cache[$0.gamePk] }
            guard !refreshedGames.isEmpty else {
                throw RecentGameError.noGames
            }

            games = refreshedGames
            errorMessage = nil
        } catch {
            if games.isEmpty {
                errorMessage = "We couldn't load the Game Center. Check your connection and try again."
            }
        }
    }
}

private enum RecentGameError: Error {
    case noGames
}
