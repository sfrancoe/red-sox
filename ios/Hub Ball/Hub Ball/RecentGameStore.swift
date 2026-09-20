import Foundation
import Observation

nonisolated enum RecentGamePresentationState: Equatable, Sendable {
    case live
    case savedLive
    case interruptedLive
    case delayedLive
    case final

    nonisolated var label: String {
        switch self {
        case .live: return "Live"
        case .savedLive: return "Saved score"
        case .interruptedLive: return "Updates interrupted"
        case .delayedLive: return "Updates delayed"
        case .final: return "Final"
        }
    }

    nonisolated var accessibilityLabel: String {
        switch self {
        case .live: return "Live game"
        case .savedLive: return "Saved score; live status is not currently verified"
        case .interruptedLive: return "Updates interrupted; live status may be out of date"
        case .delayedLive: return "Updates delayed; live status may be out of date"
        case .final: return "Final game"
        }
    }
}

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
        cacheDirectory: URL? = nil,
        backendOrigin: URL? = nil
    ) {
        client = MLBGameClient(team: team, session: session, backendOrigin: backendOrigin)
        scheduleStore = ScheduleStore(
            team: team,
            session: session,
            now: now,
            backendOrigin: backendOrigin
        )
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
        await refresh(showLoadingState: games.isEmpty, forceGameIDs: [])
    }

    func refresh() async {
        await restoreSnapshotIfNeeded()
        await refresh(showLoadingState: false, forceGameIDs: [])
    }

    func retry(game: RecentGame) async {
        await restoreSnapshotIfNeeded()
        await refresh(showLoadingState: false, forceGameIDs: [game.gamePk])
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

    func presentationState(
        for game: RecentGame,
        at date: Date
    ) -> RecentGamePresentationState {
        guard game.isLive else { return .final }
        guard let status = freshness(for: game) else { return .delayedLive }
        if status.isSavedSnapshot { return .savedLive }
        if status.lastFailureAt != nil { return .interruptedLive }
        if date.timeIntervalSince(status.lastCheckedAt) > 60 { return .delayedLive }
        return .live
    }

    func hasRefreshWarning(for game: RecentGame) -> Bool {
        freshness(for: game)?.lastFailureAt != nil
    }

    private func refresh(showLoadingState: Bool, forceGameIDs: Set<Int>) async {
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
            var descriptors: [MLBGameDescriptor]
            var discoverySucceeded = true
            var discoveredIDs = Set<Int>()
            do {
                descriptors = try await client.gameDescriptors()
                discoveredIDs = Set(descriptors.map(\.gamePk))
            } catch {
                discoverySucceeded = false
                guard !forceGameIDs.isEmpty else { throw error }
                descriptors = forceGameIDs.compactMap { gameID in
                    guard let cachedGame = cache[gameID] else { return nil }
                    return MLBGameDescriptor(
                        gamePk: gameID,
                        gameDate: cachedGame.game.gameDate,
                        isLive: cachedGame.game.isLive
                    )
                }
                guard !descriptors.isEmpty else { throw error }
            }

            // An explicit retry is also allowed to revalidate a known game
            // that a successful discovery response omits (including an empty
            // response). Keep it distinct from normal discovery so that this
            // forced descriptor cannot make the rest of the displayed cache
            // look obsolete.
            let descriptorIDs = Set(descriptors.map(\.gamePk))
            for gameID in forceGameIDs where !descriptorIDs.contains(gameID) {
                guard let cachedGame = cache[gameID] else { continue }
                descriptors.append(
                    MLBGameDescriptor(
                        gamePk: gameID,
                        gameDate: cachedGame.game.gameDate,
                        isLive: cachedGame.game.isLive
                    )
                )
            }
            guard requestID == refreshID, !Task.isCancelled else { return }

            var failedFetch = false
            for descriptor in descriptors {
                let cachedGame = cache[descriptor.gamePk]
                let needsFreshFeed = forceGameIDs.contains(descriptor.gamePk)
                    || cachedGame == nil
                    || descriptor.isLive
                    || cachedGame?.game.isLive == true
                    || cachedGame.map { now().timeIntervalSince($0.fetchedAt) >= finalCacheLifetime } == true
                if needsFreshFeed {
                    do {
                        let cachePolicy: URLRequest.CachePolicy = forceGameIDs.contains(descriptor.gamePk)
                            ? .reloadIgnoringLocalCacheData
                            : .useProtocolCachePolicy
                        let game = try await client.game(
                            gamePk: descriptor.gamePk,
                            cachePolicy: cachePolicy
                        )
                        guard requestID == refreshID, !Task.isCancelled else { return }
                        cache[descriptor.gamePk] = CachedGame(
                            game: game,
                            fetchedAt: now(),
                            failureAt: nil,
                            isRestored: false
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        failedFetch = true
                        if var cachedGame = cache[descriptor.gamePk] {
                            cachedGame.failureAt = now()
                            cache[descriptor.gamePk] = cachedGame
                        }
                    }
                }
            }

            guard requestID == refreshID, !Task.isCancelled else { return }
            let refreshedGames = descriptors.compactMap { cache[$0.gamePk]?.game }
            let previousGames = games
            guard !refreshedGames.isEmpty else {
                if failedFetch, !previousGames.isEmpty {
                    let failureAt = now()
                    for game in previousGames {
                        cache[game.gamePk]?.failureAt = failureAt
                    }
                    games = orderedCachedGames()
                    await scheduleRefresh
                    try Task.checkCancellation()
                    errorMessage = nil
                    await saveSnapshot()
                    return
                }
                if descriptors.isEmpty, !previousGames.isEmpty {
                    await scheduleRefresh
                    try Task.checkCancellation()
                    return
                }
                throw RecentGameError.noGames
            }

            let replacementIDs = Set(refreshedGames.map(\.gamePk))
            let forcedRetryWasOmittedFromDiscovery = !forceGameIDs.isEmpty
                && !forceGameIDs.isSubset(of: discoveredIDs)
            let fallbackGames = (!discoverySucceeded || failedFetch || forcedRetryWasOmittedFromDiscovery)
                ? previousGames.filter { !replacementIDs.contains($0.gamePk) }
                : []
            let visibleGames = Array((refreshedGames + fallbackGames).prefix(RecentGameSnapshotCache.maxGamesPerTeam))
            let visibleIDs = Set(visibleGames.map(\.gamePk))
            cache = cache.filter { visibleIDs.contains($0.key) }
            await scheduleRefresh
            try Task.checkCancellation()
            games = visibleGames
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
