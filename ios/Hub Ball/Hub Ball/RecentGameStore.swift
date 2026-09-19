import Foundation
import Observation

@MainActor
@Observable
final class RecentGameStore {
    private let client: MLBGameClient
    private let scheduleStore: ScheduleStore
    private let now: () -> Date
    private let finalCacheLifetime: TimeInterval = 5 * 60
    private var cache: [Int: CachedGame] = [:]

    var games: [RecentGame] = []
    var isLoading = false
    var errorMessage: String?

    init(
        team: HubTeam = .boston,
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        client = MLBGameClient(team: team, session: session)
        scheduleStore = ScheduleStore(team: team, session: session, now: now)
        self.now = now
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
        guard !isLoading, !Task.isCancelled else { return }

        isLoading = true
        if showLoadingState {
            errorMessage = nil
        }
        defer { isLoading = false }

        async let scheduleRefresh: Void = scheduleStore.load(minimumRefreshInterval: 5 * 60)

        do {
            let descriptors = try await client.gameDescriptors()

            for descriptor in descriptors {
                let cachedGame = cache[descriptor.gamePk]
                let needsFreshFeed = cachedGame == nil
                    || descriptor.isLive
                    || cachedGame?.game.isLive == true
                    || cachedGame.map { now().timeIntervalSince($0.fetchedAt) >= finalCacheLifetime } == true
                if needsFreshFeed {
                    do {
                        let game = try await client.game(gamePk: descriptor.gamePk)
                        cache[descriptor.gamePk] = CachedGame(game: game, fetchedAt: now())
                    } catch {
                        // Keep the last good game and its original fetch time. A failed
                        // final revalidation must not make stale data look freshly checked.
                    }
                }
            }

            let refreshedGames = descriptors.compactMap { cache[$0.gamePk]?.game }
            guard !refreshedGames.isEmpty else {
                throw RecentGameError.noGames
            }

            await scheduleRefresh
            try Task.checkCancellation()
            games = refreshedGames
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            if games.isEmpty {
                errorMessage = "We couldn't load Game Recaps. Check your connection and try again."
            }
        }
    }
}

private enum RecentGameError: Error {
    case noGames
}

private struct CachedGame {
    let game: RecentGame
    let fetchedAt: Date
}
