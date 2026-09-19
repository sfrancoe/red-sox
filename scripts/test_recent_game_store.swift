import Foundation

final class RecentGameProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var scheduleIsLive = false
    nonisolated(unsafe) private static var gameVersion = 1
    nonisolated(unsafe) private static var gameRequests = 0
    nonisolated(unsafe) private static var failGame = false

    static func configure(live: Bool = false, version: Int = 1, fail: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        scheduleIsLive = live
        gameVersion = version
        failGame = fail
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
        let version = Self.gameVersion
        let shouldFail = Self.failGame
        if url.path.contains("/api/mlb/game") {
            Self.gameRequests += 1
        }
        Self.lock.unlock()

        if url.path.contains("/api/mlb/game") && shouldFail {
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
            let game: [String: Any] = [
                "gamePk": 9001,
                "gameDate": "2026-09-18T23:00:00Z",
                "status": status,
            ]
            body = try! JSONSerialization.data(withJSONObject: [
                "dates": [["games": [game]]]
            ])
        } else if url.path.contains("/data/schedule.json") {
            body = Data(#"{"generated_at":"fixture","regular_season_end":"2026-09-27","source":"test","team":"Boston","games":[]}"#.utf8)
        } else {
            body = gamePayload(live: live, version: version)
        }

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func gamePayload(live: Bool, version: Int) -> Data {
        let abstract = live ? "Live" : "Final"
        let code = live ? "I" : "F"
        let venue = live ? "Fenway live \(version)" : "Fenway final \(version)"
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
            "gamePk": 9001,
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
        RecentGameProtocol.configure(live: false, version: 1)
        let store = RecentGameStore(team: .boston, session: session, now: { now })

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
        RecentGameProtocol.configure(live: false, version: 3, fail: true)
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
        let liveStore = RecentGameStore(team: .boston, session: session, now: { liveNow })
        await liveStore.load()
        precondition(liveStore.games.first?.isLive == true)
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

        print("RecentGameStore: final reuse, expiry, failed revalidation retention, live refresh, and live-to-final transition passed.")
    }
}
