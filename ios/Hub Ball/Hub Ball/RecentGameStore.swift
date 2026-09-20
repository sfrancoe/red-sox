import Foundation
import Observation

@MainActor
@Observable
final class RecentGameStore {
    private let client: MLBGameClient
    private let scheduleStore: ScheduleStore
    private let teamID: Int
    private let snapshotCache: RecentGameSnapshotCache
    private let now: () -> Date
    private let finalCacheLifetime: TimeInterval = 5 * 60
    private var cache: [Int: CachedGame] = [:]
    private var didRestoreSnapshot = false
    private var refreshID = 0

    var games: [RecentGame] = []
    var isLoading = false
    var errorMessage: String?

    init(
        team: HubTeam = .boston,
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init,
        cacheDirectory: URL? = nil
    ) {
        client = MLBGameClient(team: team, session: session)
        scheduleStore = ScheduleStore(team: team, session: session, now: now)
        teamID = team.mlbID
        snapshotCache = RecentGameSnapshotCache(directory: cacheDirectory, now: now)
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
        await restoreSnapshotIfNeeded()
        await refresh(showLoadingState: games.isEmpty)
    }

    func refresh() async {
        await restoreSnapshotIfNeeded()
        await refresh(showLoadingState: false)
    }

    func freshness(for game: RecentGame) -> RecentGameFreshness? {
        guard let cached = cache[game.gamePk] else { return nil }
        return RecentGameFreshness(
            lastCheckedAt: cached.fetchedAt,
            lastFailureAt: cached.failureAt,
            isSavedSnapshot: cached.isRestored
        )
    }

    func freshnessMessage(for game: RecentGame, at date: Date) -> String? {
        guard let status = freshness(for: game) else { return nil }
        let checked = BaseballTime.format(
            status.lastCheckedAt,
            .dateTime.month(.abbreviated).day().hour().minute()
        )
        if status.lastFailureAt != nil {
            return "Updates unavailable · Last checked \(checked)"
        }
        if status.isSavedSnapshot {
            return "Saved data · Last checked \(checked)"
        }
        if game.isLive && date.timeIntervalSince(status.lastCheckedAt) > 60 {
            return "Updates may be delayed · Last checked \(checked)"
        }
        return "Last checked \(checked)"
    }

    func hasRefreshWarning(for game: RecentGame) -> Bool {
        freshness(for: game)?.lastFailureAt != nil
    }

    private func refresh(showLoadingState: Bool) async {
        guard !isLoading, !Task.isCancelled else { return }

        refreshID += 1
        let requestID = refreshID
        isLoading = true
        if showLoadingState {
            errorMessage = nil
        }
        defer { isLoading = false }

        async let scheduleRefresh: Void = scheduleStore.load(minimumRefreshInterval: 5 * 60)

        do {
            let descriptors = try await client.gameDescriptors()
            guard requestID == refreshID, !Task.isCancelled else { return }

            for descriptor in descriptors {
                let cachedGame = cache[descriptor.gamePk]
                let needsFreshFeed = cachedGame == nil
                    || descriptor.isLive
                    || cachedGame?.game.isLive == true
                    || cachedGame.map { now().timeIntervalSince($0.fetchedAt) >= finalCacheLifetime } == true
                if needsFreshFeed {
                    do {
                        let game = try await client.game(gamePk: descriptor.gamePk)
                        guard requestID == refreshID, !Task.isCancelled else { return }
                        cache[descriptor.gamePk] = CachedGame(
                            game: game,
                            fetchedAt: now(),
                            failureAt: nil,
                            isRestored: false
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        if var cachedGame = cache[descriptor.gamePk] {
                            cachedGame.failureAt = now()
                            cache[descriptor.gamePk] = cachedGame
                        }
                    }
                }
            }

            guard requestID == refreshID, !Task.isCancelled else { return }
            if !descriptors.isEmpty {
                let descriptorIDs = Set(descriptors.map(\.gamePk))
                cache = cache.filter { descriptorIDs.contains($0.key) }
            }
            let refreshedGames = descriptors.compactMap { cache[$0.gamePk]?.game }
            guard !refreshedGames.isEmpty else {
                throw RecentGameError.noGames
            }

            await scheduleRefresh
            try Task.checkCancellation()
            games = refreshedGames
            errorMessage = nil
            await saveSnapshot()
        } catch {
            guard !Task.isCancelled else { return }
            if case RecentGameError.noGames = error {
                if games.isEmpty {
                    errorMessage = "We couldn't load Game Recaps. Check your connection and try again."
                }
                return
            }
            let failureAt = now()
            for key in cache.keys {
                cache[key]?.failureAt = failureAt
            }
            if games.isEmpty {
                games = orderedCachedGames()
            }
            await saveSnapshot()
            if games.isEmpty {
                errorMessage = "We couldn't load Game Recaps. Check your connection and try again."
            }
        }
    }

    private func restoreSnapshotIfNeeded() async {
        guard !didRestoreSnapshot, !Task.isCancelled else { return }
        didRestoreSnapshot = true
        guard let records = await snapshotCache.load(teamID: teamID), !Task.isCancelled else { return }
        cache = Dictionary(uniqueKeysWithValues: records.map { record in
            (
                record.game.gamePk,
                CachedGame(
                    game: record.game,
                    fetchedAt: record.lastCheckedAt,
                    failureAt: record.lastFailureAt,
                    isRestored: true
                )
            )
        })
        games = records.map(\.game)
    }

    private func orderedCachedGames() -> [RecentGame] {
        let displayedIDs = games.map(\.gamePk)
        let displayed = displayedIDs.compactMap { cache[$0]?.game }
        let remaining = cache.values
            .filter { !displayedIDs.contains($0.game.gamePk) }
            .sorted { $0.fetchedAt > $1.fetchedAt }
            .map(\.game)
        return displayed + remaining
    }

    private func saveSnapshot() async {
        guard !cache.isEmpty else { return }
        let displayedIDs = games.map(\.gamePk)
        let displayed = displayedIDs.compactMap { cache[$0] }
        let remaining = cache.values.filter { !displayedIDs.contains($0.game.gamePk) }
        let records = (displayed + remaining).map {
            RecentGameCacheRecord(
                game: $0.game,
                lastCheckedAt: $0.fetchedAt,
                lastFailureAt: $0.failureAt
            )
        }
        _ = await snapshotCache.save(teamID: teamID, records: records)
    }
}

private enum RecentGameError: Error {
    case noGames
}

private struct CachedGame {
    let game: RecentGame
    let fetchedAt: Date
    var failureAt: Date?
    var isRestored: Bool
}
