import Foundation
import Observation

@MainActor
@Observable
final class RecentGameStore {
    private let client: MLBGameClient
    private let scheduleStore: ScheduleStore
    private var cache: [Int: RecentGame] = [:]

    var games: [RecentGame] = []
    var isLoading = false
    var errorMessage: String?

    init(team: HubTeam = .boston) {
        client = MLBGameClient(team: team)
        scheduleStore = ScheduleStore(team: team)
    }

    var hasLiveGame: Bool {
        games.contains(where: \.isLive)
    }

    func watchSummary(for game: RecentGame) -> String? {
        let scheduledGame = scheduleStore.schedule?.games.first { $0.gamePk == game.gamePk }
        return scheduledGame?.watchSummary ?? (game.isLive ? "TV TBD" : nil)
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

        async let scheduleRefresh: Void = scheduleStore.load()

        do {
            let descriptors = try await client.gameDescriptors()

            for descriptor in descriptors {
                let cachedGame = cache[descriptor.gamePk]
                let needsFreshFeed = cachedGame == nil || descriptor.isLive || cachedGame?.isLive == true
                if needsFreshFeed {
                    cache[descriptor.gamePk] = try await client.game(gamePk: descriptor.gamePk)
                }
            }

            let refreshedGames = descriptors.compactMap { cache[$0.gamePk] }
            guard !refreshedGames.isEmpty else {
                throw RecentGameError.noGames
            }

            await scheduleRefresh
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
