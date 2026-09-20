import Foundation

final class HTTPCacheProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var live = false
    nonisolated(unsafe) private static var version = 1
    nonisolated(unsafe) private static var gameRequests = 0
    nonisolated(unsafe) private static var cachePolicies: [URLRequest.CachePolicy] = []
    nonisolated(unsafe) private static var gameCachePolicies: [URLRequest.CachePolicy] = []

    static func configure(live: Bool, version: Int) {
        lock.lock()
        defer { lock.unlock() }
        Self.live = live
        Self.version = version
    }

    static var gameRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return gameRequests
    }

    static var observedCachePolicies: [URLRequest.CachePolicy] {
        lock.lock()
        defer { lock.unlock() }
        return cachePolicies
    }

    static var observedGameCachePolicies: [URLRequest.CachePolicy] {
        lock.lock()
        defer { lock.unlock() }
        return gameCachePolicies
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.lock()
        let isLive = Self.live
        let currentVersion = Self.version
        Self.cachePolicies.append(request.cachePolicy)
        if url.path.contains("/api/mlb/game") {
            Self.gameRequests += 1
            Self.gameCachePolicies.append(request.cachePolicy)
        }
        Self.lock.unlock()

        let body: Data
        let cacheControl: String
        if url.path.contains("/api/mlb/schedule") {
            let status: [String: String] = isLive
                ? ["abstractGameState": "Live", "codedGameState": "I"]
                : ["abstractGameState": "Final", "codedGameState": "F"]
            body = try! JSONSerialization.data(withJSONObject: [
                "dates": [[
                    "games": [[
                        "gamePk": 9010,
                        "gameDate": "2026-09-18T23:00:00Z",
                        "status": status,
                    ]],
                ]],
            ])
            cacheControl = "no-store"
        } else if url.path.contains("/data/schedule.json") {
            body = Data(#"{"generated_at":"fixture","regular_season_end":"2026-09-27","source":"test","team":"Boston","games":[]}"#.utf8)
            cacheControl = "no-store"
        } else {
            body = gamePayload(live: isLive, version: currentVersion)
            // Deliberately arrive expired. The store clock also advances past
            // its five-minute final revalidation window.
            cacheControl = isLive ? "public, max-age=0" : "public, max-age=300"
        }

        let headers = [
            "Cache-Control": cacheControl,
            "Date": HTTPDateFormatter.string(from: Date(timeIntervalSinceNow: -600)),
            "Content-Type": "application/json",
        ]
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
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
            "gamePk": 9010,
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

private enum HTTPDateFormatter {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}

@main
struct HTTPCacheIntegrationTests {
    @MainActor
    static func main() async throws {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [HTTPCacheProtocol.self]
        configuration.urlCache = URLCache(
            memoryCapacity: 2 * 1024 * 1024,
            diskCapacity: 2 * 1024 * 1024,
            diskPath: "hub-ball-http-cache-test"
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-game-http-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        var now = Date(timeIntervalSince1970: 1_000)
        HTTPCacheProtocol.configure(live: false, version: 1)
        let finalStore = RecentGameStore(
            team: .boston,
            session: session,
            now: { now },
            cacheDirectory: cacheDirectory
        )
        await finalStore.load()
        precondition(finalStore.games.first?.venue == "Fenway final 1")
        precondition(HTTPCacheProtocol.gameRequestCount == 1)

        now += 301
        HTTPCacheProtocol.configure(live: false, version: 2)
        await finalStore.refresh()
        precondition(HTTPCacheProtocol.gameRequestCount == 2, "expired final did not reach the network")
        precondition(finalStore.games.first?.venue == "Fenway final 2", "expired final did not pick up correction")

        let liveDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-game-http-cache-live-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: liveDirectory) }
        var liveNow = now
        HTTPCacheProtocol.configure(live: true, version: 1)
        let liveStore = RecentGameStore(
            team: .boston,
            session: session,
            now: { liveNow },
            cacheDirectory: liveDirectory
        )
        await liveStore.load()
        precondition(liveStore.games.first?.venue == "Fenway live 1")
        let beforeLiveRefresh = HTTPCacheProtocol.gameRequestCount

        liveNow += 20
        HTTPCacheProtocol.configure(live: true, version: 2)
        await liveStore.refresh()
        precondition(HTTPCacheProtocol.gameRequestCount == beforeLiveRefresh + 1, "live game stopped refreshing")
        precondition(liveStore.games.first?.venue == "Fenway live 2")
        precondition(HTTPCacheProtocol.observedGameCachePolicies.allSatisfy { $0 == .useProtocolCachePolicy })

        print("HTTP cache integration: expired finals picked up corrections and live games continued refreshing.")
    }
}
