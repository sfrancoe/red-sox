import Foundation

final class RecentGameProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var scheduleIsLive = false
    nonisolated(unsafe) private static var includeFinalGame = false
    nonisolated(unsafe) private static var gameVersion = 1
    nonisolated(unsafe) private static var gameRequests = 0
    nonisolated(unsafe) private static var gameCachePolicies: [URLRequest.CachePolicy] = []
    nonisolated(unsafe) private static var failedGamePk: Int?
    nonisolated(unsafe) private static var failDiscovery = false
    nonisolated(unsafe) private static var stallRequests = false

    static func configure(
        live: Bool = false,
        includeFinal: Bool = false,
        scheduleGamePk: Int = 9001,
        version: Int = 1,
        failGamePk: Int? = nil,
        failDiscovery: Bool = false,
        stall: Bool = false
    ) {
        lock.lock()
        defer { lock.unlock() }
        scheduleIsLive = live
        includeFinalGame = includeFinal
        scheduleGameID = scheduleGamePk
        gameVersion = version
        failedGamePk = failGamePk
        Self.failDiscovery = failDiscovery
        stallRequests = stall
    }

    nonisolated(unsafe) private static var scheduleGameID = 9001

    static var observedGameCachePolicies: [URLRequest.CachePolicy] {
        lock.lock()
        defer { lock.unlock() }
        return gameCachePolicies
    }

    static var gameRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return gameRequests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.lock()
        let live = Self.scheduleIsLive
        let includeFinal = Self.includeFinalGame
        let scheduleGamePk = Self.scheduleGameID
        let version = Self.gameVersion
        let failedGamePk = Self.failedGamePk
        let failDiscovery = Self.failDiscovery
        let stall = Self.stallRequests
        let gamePk = Int(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "gamePk" })?.value ?? "")
        if url.path.contains("/api/mlb/game") {
            Self.gameRequests += 1
            Self.gameCachePolicies.append(request.cachePolicy)
        }
        Self.lock.unlock()

        if stall {
            return
        }
        if url.path.contains("/api/mlb/schedule") && failDiscovery {
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if url.path.contains("/api/mlb/game") && failedGamePk == gamePk {
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let body: Data
        if url.path.contains("/api/mlb/schedule") {
            let status: [String: String] = live
                ? ["abstractGameState": "Live", "codedGameState": "I"]
                : ["abstractGameState": "Final", "codedGameState": "F"]
            var games: [[String: Any]] = [[
                "gamePk": scheduleGamePk,
                "gameDate": "2026-09-18T23:00:00Z",
                "status": status,
            ]]
            if includeFinal {
                games.append([
                    "gamePk": 9002,
                    "gameDate": "2026-09-17T23:00:00Z",
                    "status": [
                        "abstractGameState": "Final",
                        "codedGameState": "F",
                    ],
                ])
            }
            body = try! JSONSerialization.data(withJSONObject: [
                "dates": [["games": games]]
            ])
        } else if url.path.contains("/data/schedule.json") {
            body = Data(#"{"generated_at":"fixture","regular_season_end":"2026-09-27","source":"test","team":"Boston","games":[]}"#.utf8)
        } else {
            body = gamePayload(gamePk: gamePk ?? scheduleGamePk, live: live, version: version)
        }

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func gamePayload(gamePk: Int, live: Bool, version: Int) -> Data {
        let gameIsLive = gamePk == 9001 && live
        let abstract = gameIsLive ? "Live" : "Final"
        let code = gameIsLive ? "I" : "F"
        let venue = gameIsLive
            ? "Fenway live \(version)"
            : gamePk == 9001 ? "Fenway final \(version)" : "Fenway final \(version) game \(gamePk)"
        let team = ["id": 111, "name": "Boston Red Sox", "abbreviation": "BOS", "record": [
            "leagueRecord": ["wins": 80, "losses": 70],
        ]] as [String: Any]
        let opponent = ["id": 147, "name": "New York Yankees", "abbreviation": "NYY", "record": [
            "leagueRecord": ["wins": 75, "losses": 75],
        ]] as [String: Any]
        let lineTeam = ["runs": 3, "hits": 5, "errors": 0, "leftOnBase": 4] as [String: Any]
        let lineOpponent = ["runs": 2, "hits": 4, "errors": 1, "leftOnBase": 5] as [String: Any]
        let emptyBox = ["batters": [], "battingOrder": [], "pitchers": [], "players": [:]] as [String: Any]
        let payload: [String: Any] = [
            "gamePk": gamePk,
            "gameData": [
                "status": ["abstractGameState": abstract, "codedGameState": code],
                "datetime": ["dateTime": "2026-09-18T23:00:00Z"],
                "venue": ["name": venue],
                "gameInfo": ["gameDurationMinutes": 180, "attendance": 30000],
                "teams": ["away": team, "home": opponent],
            ],
            "liveData": [
                "linescore": ["teams": ["away": lineTeam, "home": lineOpponent], "innings": []],
                "boxscore": ["teams": ["away": emptyBox, "home": emptyBox]],
                "plays": ["allPlays": [], "scoringPlays": []],
                "decisions": [:],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}

@main
struct RecentGameStoreTests {
    @MainActor
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecentGameProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var now = Date(timeIntervalSince1970: 1_000)
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-game-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        RecentGameProtocol.configure(live: false, version: 1)
        let store = RecentGameStore(
            team: .boston,
            session: session,
            now: { now },
            cacheDirectory: cacheDirectory
        )

        await store.load()
        precondition(store.games.first?.venue == "Fenway final 1")
        precondition(RecentGameProtocol.gameRequestCount == 1)

        now += 299
        RecentGameProtocol.configure(live: false, version: 2)
        await store.refresh()
        precondition(RecentGameProtocol.gameRequestCount == 1, "unexpired final was re-fetched")
        precondition(store.games.first?.venue == "Fenway final 1")

        now += 1
        await store.refresh()
        precondition(RecentGameProtocol.gameRequestCount == 2, "expired final was not revalidated")
        precondition(store.games.first?.venue == "Fenway final 2")

        now += 300
        RecentGameProtocol.configure(live: false, version: 3, failGamePk: 9001)
        await store.refresh()
        precondition(RecentGameProtocol.gameRequestCount == 3)
        precondition(store.games.first?.venue == "Fenway final 2", "failed final revalidation discarded last good data")

        // The failed attempt did not reset the fetch timestamp: the next refresh
        // retries immediately and accepts the corrected response.
        now += 1
        RecentGameProtocol.configure(live: false, version: 3)
        await store.refresh()
        precondition(RecentGameProtocol.gameRequestCount == 4)
        precondition(store.games.first?.venue == "Fenway final 3")

        var liveNow = now + 1
        RecentGameProtocol.configure(live: true, version: 1)
        let liveStore = RecentGameStore(
            team: .boston,
            session: session,
            now: { liveNow },
            cacheDirectory: cacheDirectory
        )
        await liveStore.load()
        precondition(liveStore.games.first?.isLive == true)
        precondition(liveStore.presentationState(for: liveStore.games.first!, at: liveNow) == .live)
        let beforeLiveRefresh = RecentGameProtocol.gameRequestCount

        liveNow += 20
        RecentGameProtocol.configure(live: true, version: 2)
        await liveStore.refresh()
        precondition(RecentGameProtocol.gameRequestCount == beforeLiveRefresh + 1)
        precondition(liveStore.games.first?.venue == "Fenway live 2")

        // A descriptor that has become final must revalidate a cached-live game.
        liveNow += 20
        RecentGameProtocol.configure(live: false, version: 3)
        await liveStore.refresh()
        precondition(RecentGameProtocol.gameRequestCount == beforeLiveRefresh + 2)
        precondition(liveStore.games.first?.isLive == false)
        precondition(liveStore.games.first?.venue == "Fenway final 3")

        // A failed live request must not inherit the successful final's freshness.
        var mixedNow = liveNow + 300
        let mixedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-game-mixed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: mixedDirectory) }
        RecentGameProtocol.configure(live: true, includeFinal: true, version: 1)
        let mixedStore = RecentGameStore(
            team: .boston,
            session: session,
            now: { mixedNow },
            cacheDirectory: mixedDirectory
        )
        await mixedStore.load()
        let mixedLive = mixedStore.games.first { $0.gamePk == 9001 }!
        let mixedFinal = mixedStore.games.first { $0.gamePk == 9002 }!
        let liveCheckedBeforeFailure = mixedStore.freshness(for: mixedLive)!.lastCheckedAt
        let finalCheckedBeforeRefresh = mixedStore.freshness(for: mixedFinal)!.lastCheckedAt

        mixedNow += 300
        RecentGameProtocol.configure(live: true, includeFinal: true, version: 2, failGamePk: 9001)
        await mixedStore.refresh()
        let failedLive = mixedStore.games.first { $0.gamePk == 9001 }!
        let refreshedFinal = mixedStore.games.first { $0.gamePk == 9002 }!
        precondition(mixedStore.hasRefreshWarning(for: failedLive))
        precondition(mixedStore.freshness(for: failedLive)!.lastCheckedAt == liveCheckedBeforeFailure)
        precondition(mixedStore.freshness(for: refreshedFinal)!.lastCheckedAt > finalCheckedBeforeRefresh)
        precondition(!mixedStore.hasRefreshWarning(for: refreshedFinal))

        mixedNow += 20
        RecentGameProtocol.configure(live: true, includeFinal: true, version: 3)
        await mixedStore.refresh()
        precondition(!mixedStore.hasRefreshWarning(for: mixedStore.games.first { $0.gamePk == 9001 }!))
        precondition(mixedStore.presentationState(
            for: mixedStore.games.first { $0.gamePk == 9001 }!,
            at: mixedNow
        ) == .live)

        // A new store restores promptly, discloses saved data, and reports the
        // failed reconnect without turning the saved score into a fresh check.
        RecentGameProtocol.configure(failDiscovery: true)
        let restoredStore = RecentGameStore(
            team: .boston,
            session: session,
            now: { mixedNow },
            cacheDirectory: mixedDirectory
        )
        await restoredStore.load()
        let restoredLive = restoredStore.games.first { $0.gamePk == 9001 }!
        precondition(restoredStore.freshness(for: restoredLive)!.isSavedSnapshot)
        precondition(restoredStore.hasRefreshWarning(for: restoredLive))
        precondition(restoredStore.freshnessMessage(for: restoredLive, at: mixedNow)?.hasPrefix("Updates unavailable") == true)

        mixedNow += 301
        RecentGameProtocol.configure(live: false, includeFinal: true, version: 4)
        await restoredStore.refresh()
        let recoveredLive = restoredStore.games.first { $0.gamePk == 9001 }!
        precondition(!recoveredLive.isLive)
        precondition(restoredStore.freshness(for: recoveredLive)!.isSavedSnapshot == false)
        precondition(!restoredStore.hasRefreshWarning(for: recoveredLive))

        // A restored live snapshot is qualified before its reconnect finishes,
        // and age-based presentation changes do not alter the historical state.
        let savedLiveDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-game-saved-live-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: savedLiveDirectory) }
        try FileManager.default.createDirectory(at: savedLiveDirectory, withIntermediateDirectories: true)
        let savedLiveNow = Date(timeIntervalSince1970: 20_000)
        let savedLiveRecord = RecentGameCacheRecord(
            game: testGame(gamePk: 9001, teamID: 111, live: true),
            lastCheckedAt: savedLiveNow,
            lastFailureAt: nil
        )
        try writeTestEnvelope(
            directory: savedLiveDirectory,
            teamID: 111,
            schemaVersion: RecentGameSnapshotCache.schemaVersion,
            entries: [savedLiveRecord]
        )
        RecentGameProtocol.configure(stall: true)
        let savedLiveStore = RecentGameStore(
            team: .boston,
            session: session,
            now: { savedLiveNow },
            cacheDirectory: savedLiveDirectory
        )
        let savedLoad = Task { await savedLiveStore.load() }
        for _ in 0..<100 where savedLiveStore.games.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let savedLive = savedLiveStore.games.first { $0.gamePk == 9001 }!
        precondition(savedLiveStore.presentationState(for: savedLive, at: savedLiveNow) == .savedLive)
        savedLoad.cancel()
        await savedLoad.value
        let delayedLive = mixedStore.games.first { $0.gamePk == 9001 }!
        precondition(mixedStore.presentationState(for: delayedLive, at: mixedNow + 301) == .delayedLive)
        RecentGameProtocol.configure(live: false, version: 6)

        // A failed replacement retains the old displayed game and its warning
        // metadata until a replacement succeeds.
        let replacementDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-game-replacement-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: replacementDirectory) }
        try FileManager.default.createDirectory(at: replacementDirectory, withIntermediateDirectories: true)
        let fallbackNow = Date(timeIntervalSince1970: 10_000)
        let oldGame = testGame(gamePk: 9901, teamID: 111)
        try writeTestEnvelope(
            directory: replacementDirectory,
            teamID: 111,
            schemaVersion: RecentGameSnapshotCache.schemaVersion,
            entries: [RecentGameCacheRecord(game: oldGame, lastCheckedAt: fallbackNow, lastFailureAt: nil)]
        )
        RecentGameProtocol.configure(scheduleGamePk: 9001, version: 1, failGamePk: 9001)
        let replacementStore = RecentGameStore(
            team: .boston,
            session: session,
            now: { fallbackNow },
            cacheDirectory: replacementDirectory
        )
        await replacementStore.load()
        let fallbackGame = replacementStore.games.first!
        precondition(fallbackGame.gamePk == 9901)
        precondition(replacementStore.freshness(for: fallbackGame) != nil)
        precondition(replacementStore.hasRefreshWarning(for: fallbackGame))
        precondition(replacementStore.freshnessMessage(for: fallbackGame, at: fallbackNow)?
            .hasPrefix("Updates unavailable") == true)

        RecentGameProtocol.configure(scheduleGamePk: 9001, version: 2)
        await replacementStore.refresh()
        precondition(replacementStore.games.first?.gamePk == 9001)
        precondition(!replacementStore.hasRefreshWarning(for: replacementStore.games.first!))
        precondition(replacementStore.presentationState(
            for: replacementStore.games.first!,
            at: fallbackNow
        ) == .final)

        // Explicit retry bypasses the five-minute store window and the HTTP
        // cache policy, then clears only the recovered game's warning.
        let retryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-game-retry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: retryDirectory) }
        var retryNow = Date(timeIntervalSince1970: 30_000)
        RecentGameProtocol.configure(scheduleGamePk: 9001, version: 1)
        let retryStore = RecentGameStore(
            team: .boston,
            session: session,
            now: { retryNow },
            cacheDirectory: retryDirectory
        )
        await retryStore.load()
        retryNow += 10
        RecentGameProtocol.configure(scheduleGamePk: 9001, failDiscovery: true)
        await retryStore.refresh()
        let warnedGame = retryStore.games.first!
        precondition(retryStore.hasRefreshWarning(for: warnedGame))
        let requestsBeforeRetry = RecentGameProtocol.gameRequestCount
        RecentGameProtocol.configure(scheduleGamePk: 9001, version: 7)
        await retryStore.retry(game: warnedGame)
        precondition(RecentGameProtocol.gameRequestCount == requestsBeforeRetry + 1)
        precondition(retryStore.games.first?.venue == "Fenway final 7")
        precondition(!retryStore.hasRefreshWarning(for: retryStore.games.first!))
        precondition(RecentGameProtocol.observedGameCachePolicies.dropLast()
            .allSatisfy { $0 == .useProtocolCachePolicy })
        precondition(RecentGameProtocol.observedGameCachePolicies.last == .reloadIgnoringLocalCacheData)

        // Snapshot validation rejects corruption, wrong-team envelopes, old
        // entries, and incompatible versions without throwing.
        let validationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-game-validation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: validationDirectory) }
        try FileManager.default.createDirectory(at: validationDirectory, withIntermediateDirectories: true)
        let validationNow = Date(timeIntervalSince1970: 10_000)
        let validationGame = testGame(gamePk: 9901, teamID: 111)
        let validationRecord = RecentGameCacheRecord(
            game: validationGame,
            lastCheckedAt: validationNow,
            lastFailureAt: nil
        )
        let validationCache = RecentGameSnapshotCache(directory: validationDirectory, now: { validationNow })
        try writeTestEnvelope(
            directory: validationDirectory,
            teamID: 111,
            schemaVersion: RecentGameSnapshotCache.schemaVersion,
            entries: [validationRecord]
        )
        let loadedValidation = await validationCache.load(teamID: 111)
        precondition(loadedValidation?.count == 1)

        try Data("corrupt".utf8).write(to: validationDirectory.appendingPathComponent("recent-games-111.json"))
        let corruptValidation = await validationCache.load(teamID: 111)
        precondition(corruptValidation == nil)
        try? FileManager.default.removeItem(at: validationDirectory.appendingPathComponent("recent-games-111.json"))
        try writeTestEnvelope(
            directory: validationDirectory,
            teamID: 111,
            schemaVersion: RecentGameSnapshotCache.schemaVersion,
            entries: [validationRecord],
            envelopeTeamID: 147
        )
        let wrongTeamValidation = await validationCache.load(teamID: 111)
        precondition(wrongTeamValidation == nil)
        try writeTestEnvelope(
            directory: validationDirectory,
            teamID: 111,
            schemaVersion: 999,
            entries: [validationRecord]
        )
        let versionValidation = await validationCache.load(teamID: 111)
        precondition(versionValidation == nil)
        try writeTestEnvelope(
            directory: validationDirectory,
            teamID: 111,
            schemaVersion: RecentGameSnapshotCache.schemaVersion,
            entries: [RecentGameCacheRecord(
                game: validationGame,
                lastCheckedAt: validationNow.addingTimeInterval(-RecentGameSnapshotCache.finalRetention - 1),
                lastFailureAt: nil
            )]
        )
        let expiredValidation = await validationCache.load(teamID: 111)
        precondition(expiredValidation == nil)

        // Team snapshots stay bounded and a failed disk write cannot turn a
        // successful network result into a failed refresh.
        let boundedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-game-bounds-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: boundedDirectory) }
        let boundedCache = RecentGameSnapshotCache(directory: boundedDirectory, now: { validationNow })
        let teamIDs = [111, 147, 121, 139, 110, 141, 145, 114, 116]
        for (index, teamID) in teamIDs.enumerated() {
            _ = await boundedCache.save(
                teamID: teamID,
                records: [RecentGameCacheRecord(
                    game: testGame(gamePk: 10_000 + index, teamID: teamID),
                    lastCheckedAt: validationNow,
                    lastFailureAt: nil
                )]
            )
        }
        let boundedFiles = try FileManager.default.contentsOfDirectory(at: boundedDirectory, includingPropertiesForKeys: nil)
        precondition(boundedFiles.filter { $0.lastPathComponent.hasPrefix("recent-games-") }.count <= RecentGameSnapshotCache.maxTeams)

        // Cancellation while inactive must not create a refresh warning.
        mixedNow += 301
        RecentGameProtocol.configure(stall: true)
        let pendingCancellation = Task { await mixedStore.refresh() }
        for _ in 0..<100 where !mixedStore.isLoading {
            try? await Task.sleep(for: .milliseconds(10))
        }
        precondition(mixedStore.isLoading)
        pendingCancellation.cancel()
        await pendingCancellation.value
        let cancelledGame = mixedStore.games.first { $0.gamePk == 9001 }!
        precondition(!mixedStore.hasRefreshWarning(for: cancelledGame))
        precondition(
            mixedStore.freshnessMessage(for: cancelledGame, at: mixedNow)?
                .hasPrefix("Updates may be delayed") == true
        )

        let writeFailurePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-game-write-failure-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: writeFailurePath)
        defer { try? FileManager.default.removeItem(at: writeFailurePath) }
        let writeFailureNow = Date(timeIntervalSince1970: 20_000)
        RecentGameProtocol.configure(live: false, version: 5)
        let writeFailureStore = RecentGameStore(
            team: .boston,
            session: session,
            now: { writeFailureNow },
            cacheDirectory: writeFailurePath
        )
        await writeFailureStore.load()
        precondition(writeFailureStore.games.first != nil)

        print("RecentGameStore: per-game warnings, snapshot restore/validation, bounds, write failure, partial success, and cancellation coverage passed.")
    }
}

private struct TestEnvelope: Codable {
    let schemaVersion: Int
    let teamID: Int
    let savedAt: Date
    let entries: [RecentGameCacheRecord]
}

private func writeTestEnvelope(
    directory: URL,
    teamID: Int,
    schemaVersion: Int,
    entries: [RecentGameCacheRecord],
    envelopeTeamID: Int? = nil
) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let envelope = TestEnvelope(
        schemaVersion: schemaVersion,
        teamID: envelopeTeamID ?? teamID,
        savedAt: Date(timeIntervalSince1970: 10_000),
        entries: entries
    )
    try encoder.encode(envelope).write(
        to: directory.appendingPathComponent("recent-games-\(teamID).json")
    )
}

private func testGame(gamePk: Int, teamID: Int, live: Bool = false) -> RecentGame {
    let away = TeamBoxScore(
        side: "away",
        id: teamID,
        name: "Test Team",
        abbreviation: "TST",
        record: "0-0",
        runs: 1,
        hits: 2,
        errors: 0,
        leftOnBase: 1,
        batting: [],
        pitching: []
    )
    let home = TeamBoxScore(
        side: "home",
        id: 999,
        name: "Opponent",
        abbreviation: "OPP",
        record: "0-0",
        runs: 0,
        hits: 1,
        errors: 0,
        leftOnBase: 1,
        batting: [],
        pitching: []
    )
    return RecentGame(
        generatedAt: "fixture",
        source: "fixture",
        gamePk: gamePk,
        gameDate: "2026-09-18T23:00:00Z",
        venue: "Fixture Park",
        gameDurationMinutes: nil,
        attendance: nil,
        inningsCount: 0,
        result: live ? "Live" : "Win",
        gameState: live ? "Live" : "Final",
        liveStatus: live ? "Bottom 7" : nil,
        summary: "Fixture recap",
        facts: [],
        decisions: Decisions(winner: "", loser: "", save: ""),
        away: away,
        home: home,
        innings: [],
        scoringPlays: [],
        officialRecap: nil,
        gamedayUrl: "https://www.mlb.com/gameday/\(gamePk)"
    )
}
