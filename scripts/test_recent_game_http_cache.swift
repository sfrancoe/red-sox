import Foundation

private struct FixtureStats: Decodable {
    let gameRequests: Int
}

@main
struct HTTPCacheIntegrationTests {
    @MainActor
    static func main() async throws {
        let originString = ProcessInfo.processInfo.environment["HUB_HTTP_CACHE_FIXTURE_ORIGIN"]!
        let origin = URL(string: originString)!
        let configuration = URLSessionConfiguration.default
        let cachePath = "hub-ball-http-cache-test-\(UUID().uuidString)"
        configuration.urlCache = URLCache(
            memoryCapacity: 2 * 1024 * 1024,
            diskCapacity: 2 * 1024 * 1024,
            diskPath: cachePath
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var now = Date(timeIntervalSince1970: 1_000)
        try await control(origin, session: session, live: false, version: 1)
        let gameURL = origin
            .appending(path: "api")
            .appending(path: "mlb/game")
            .appending(queryItems: [
                URLQueryItem(name: "team", value: "redsox"),
                URLQueryItem(name: "gamePk", value: "9010"),
            ])
        var seedRequest = URLRequest(url: gameURL, cachePolicy: .reloadIgnoringLocalCacheData)
        seedRequest.timeoutInterval = 20
        let (seedData, seedResponse) = try await session.data(for: seedRequest)
        precondition((seedResponse as? HTTPURLResponse)?.statusCode == 200)
        session.configuration.urlCache?.storeCachedResponse(
            CachedURLResponse(response: seedResponse, data: seedData, storagePolicy: .allowed),
            for: seedRequest
        )
        precondition(session.configuration.urlCache?.cachedResponse(for: seedRequest) != nil,
                     "fixture response was not stored in URLCache")
        let cacheOnlyClient = MLBGameClient(
            team: .boston,
            session: session,
            backendOrigin: origin
        )
        let cachedGame = try await cacheOnlyClient.game(
            gamePk: 9010,
            cachePolicy: .returnCacheDataDontLoad
        )
        precondition(cachedGame.venue == "Fenway final 1")
        try await assertGameRequests(1, origin: origin, session: session)
        session.configuration.urlCache?.removeAllCachedResponses()

        // Exercise the production request path twice. The store is not
        // involved here, so the unchanged origin count proves URLSession
        // itself reused the fresh response under .useProtocolCachePolicy.
        let normalClient = MLBGameClient(
            team: .boston,
            session: session,
            backendOrigin: origin
        )
        let normalRequest = URLRequest(url: gameURL)
        precondition(normalRequest.cachePolicy == .useProtocolCachePolicy)
        print("HTTP cache normal request policy = .useProtocolCachePolicy")
        let firstNormalGame = try await normalClient.game(gamePk: 9010)
        precondition(firstNormalGame.venue == "Fenway final 1")
        try await assertGameRequests(2, origin: origin, session: session)
        let secondNormalGame = try await normalClient.game(gamePk: 9010)
        precondition(secondNormalGame.venue == "Fenway final 1")
        try await assertGameRequests(2, origin: origin, session: session,
                                     message: "fresh normal-policy request did not reuse URLSession cache")

        let firstDirectory = temporaryDirectory("first")
        defer { try? FileManager.default.removeItem(at: firstDirectory) }
        let firstStore = RecentGameStore(
            team: .boston,
            session: session,
            now: { now },
            cacheDirectory: firstDirectory,
            backendOrigin: origin
        )
        await firstStore.load()
        precondition(firstStore.games.first?.venue == "Fenway final 1")
        try await assertGameRequests(2, origin: origin, session: session)
        // The short HTTP freshness window expires independently of the
        // store's five-minute final window, so this new store must reach origin.
        try await Task.sleep(for: .seconds(2.5))
        now += 301
        try await control(origin, session: session, live: false, version: 2)
        let expiredDirectory = temporaryDirectory("expired")
        defer { try? FileManager.default.removeItem(at: expiredDirectory) }
        let expiredStore = RecentGameStore(
            team: .boston,
            session: session,
            now: { now },
            cacheDirectory: expiredDirectory,
            backendOrigin: origin
        )
        await expiredStore.load()
        precondition(expiredStore.games.first?.venue == "Fenway final 2")
        try await assertGameRequests(3, origin: origin, session: session,
                                     message: "expired HTTP response did not reach origin")

        // Let the corrected final response age out before switching the
        // fixture to a live game, so this is a fresh live-origin request.
        try await Task.sleep(for: .seconds(2.5))
        // Live polling also revalidates after the short HTTP freshness window,
        // and the following live-to-final descriptor transition is fetched.
        now += 1
        try await control(origin, session: session, live: true, version: 1)
        let liveDirectory = temporaryDirectory("live")
        defer { try? FileManager.default.removeItem(at: liveDirectory) }
        let liveStore = RecentGameStore(
            team: .boston,
            session: session,
            now: { now },
            cacheDirectory: liveDirectory,
            backendOrigin: origin
        )
        await liveStore.load()
        precondition(liveStore.games.first?.venue == "Fenway live 1")
        try await assertGameRequests(4, origin: origin, session: session)

        try await Task.sleep(for: .seconds(2.5))
        now += 20
        try await control(origin, session: session, live: true, version: 2)
        await liveStore.refresh()
        precondition(liveStore.games.first?.venue == "Fenway live 2")
        try await assertGameRequests(5, origin: origin, session: session,
                                     message: "live refresh did not pass the expired HTTP response")

        try await Task.sleep(for: .seconds(2.5))
        now += 20
        try await control(origin, session: session, live: false, version: 3)
        await liveStore.refresh()
        precondition(liveStore.games.first?.venue == "Fenway final 3")
        precondition(!liveStore.games.first!.isLive)
        try await assertGameRequests(6, origin: origin, session: session,
                                     message: "live-to-final transition did not revalidate")

        // Discovery failure raises the warning. Retry then bypasses both the
        // five-minute store decision and a still-fresh HTTP cached final.
        try await control(origin, session: session, live: false, version: 3, failDiscovery: true)
        await liveStore.refresh()
        let warnedGame = liveStore.games.first!
        precondition(liveStore.hasRefreshWarning(for: warnedGame))
        try await control(origin, session: session, live: false, version: 4)
        await liveStore.retry(game: warnedGame)
        precondition(liveStore.games.first?.venue == "Fenway final 4")
        precondition(!liveStore.hasRefreshWarning(for: liveStore.games.first!))
        try await assertGameRequests(7, origin: origin, session: session,
                                     message: "Retry did not bypass the fresh HTTP cached final")

        print("HTTP cache integration: observed a fresh cache hit, expiry correction, live refresh, live-to-final transition, and forced Retry revalidation.")
    }

    private static func temporaryDirectory(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-game-http-\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    private static func control(
        _ origin: URL,
        session: URLSession,
        live: Bool,
        version: Int,
        failDiscovery: Bool = false
    ) async throws {
        var components = URLComponents(url: origin.appending(path: "control"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "live", value: live ? "1" : "0"),
            URLQueryItem(name: "version", value: "\(version)"),
            URLQueryItem(name: "failDiscovery", value: failDiscovery ? "1" : "0"),
        ]
        let request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
        let (_, response) = try await session.data(for: request)
        precondition((response as? HTTPURLResponse)?.statusCode == 200)
    }

    private static func stats(_ origin: URL, session: URLSession) async throws -> FixtureStats {
        let request = URLRequest(url: origin.appending(path: "stats"), cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await session.data(for: request)
        precondition((response as? HTTPURLResponse)?.statusCode == 200)
        return try JSONDecoder().decode(FixtureStats.self, from: data)
    }

    private static func assertGameRequests(
        _ expected: Int,
        origin: URL,
        session: URLSession,
        message: String = ""
    ) async throws {
        let actual = try await stats(origin, session: session).gameRequests
        print("HTTP cache origin gameRequests = \(actual), expected = \(expected)")
        precondition(actual == expected, "\(message) actual=\(actual) expected=\(expected)")
    }
}
