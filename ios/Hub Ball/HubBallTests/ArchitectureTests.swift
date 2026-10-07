import Foundation
import Testing
@testable import Hub_Ball

private final class ArchitectureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var mode = "normal"
    nonisolated(unsafe) private static var requests: [String] = []
    static func reset(_ mode: String) { lock.withLock { Self.mode = mode; requests = [] } }
    static var gameRequests: Int { lock.withLock { requests.filter { $0.contains("/mlb/game") }.count } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        let mode = Self.lock.withLock { Self.requests.append(url.absoluteString); return Self.mode }
        if mode == "cancelled" {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled)); return
        }
        var status = 200
        let payload: String
        if url.path.contains("/mlb/game") {
            payload = #"{"gamePk":42,"gameData":{"teams":{"away":{"id":111,"name":"Boston Red Sox"},"home":{"id":147,"name":"New York Yankees"}},"status":{"abstractGameState":"Final","codedGameState":"F"},"datetime":{"dateTime":"2026-10-06T19:00:00Z"}},"liveData":{"linescore":{"teams":{"away":{"runs":4},"home":{"runs":2}},"innings":[{"num":1,"away":{"runs":4},"home":{"runs":2}}]}}}"#
        } else if url.path.contains("/mlb/schedule") {
            payload = #"{"dates":[{"games":[{"gamePk":42,"gameDate":"2026-10-06T19:00:00Z","status":{"abstractGameState":"Final","codedGameState":"F"}}]}]}"#
        } else if url.path.contains("standings") {
            if mode == "noStandings" || (mode == "oneLeague" && url.query?.contains("mets") == true) { status = 503 }
            payload = #"{"generated_at":"2026-10-06T19:00:00Z","source":"test","season":2026,"league":"American League","divisions":[],"wild_card":[]}"#
        } else {
            payload = #"{"generated_at":"fixture","regular_season_end":"2026-09-27","source":"test","team":"Boston","games":[]}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized)
struct ArchitectureTests {
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        var started = false
        func wait() async {
            await withCheckedContinuation { continuation = $0; started = true }
        }
        func release() { continuation?.resume(); continuation = nil }
    }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArchitectureProtocol.self]
        return URLSession(configuration: config)
    }

    @Test(arguments: ["/sports/x.html", "mailto:a@b.c", "", "example.com", "javascript:alert(1)", "tel:123", "https://"])
    func rejectUnsafeURLs(_ value: String) { #expect(URL.safeWeb(value) == nil) }

    @Test func validURL() {
        #expect(URL.safeWeb(" \nhttps://example.com/story?q=1 ")?.host == "example.com")
    }

    @Test func feedToleranceAndIdentity() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let article = #"{"title":"A","url":"https://example.com/a","published":"2026-10-06T19:00:00Z"}"#
        let feed = try decoder.decode(NewsFeed.self, from: Data("{\"generated_at\":\"now\",\"source\":\"test\",\"source_url\":\"https://example.com\",\"articles\":[\(article),\(article)]}".utf8))
        #expect(feed.articles.count == 1)
        #expect(feed.articles[0].description.isEmpty && feed.articles[0].category.isEmpty)
        let post = try decoder.decode(XPost.self, from: Data(#"{"id":"1","text":"post","url":"https://x.com/a/status/1","published":"now","likes":0,"author":"A","handle":"a"}"#.utf8))
        #expect(post.avatar.isEmpty && post.media.isEmpty && post.quotedText.isEmpty)
    }

    @Test @MainActor func cancellationNeverMarksStoresFailed() async {
        ArchitectureProtocol.reset("cancelled")
        let session = session(); defer { session.invalidateAndCancel() }
        let api = APIClient(session: session)
        let schedule = ScheduleStore(team: .boston, api: api)
        let headlines = HeadlinesStore(team: .boston, api: api)
        let postseason = PostseasonStore(api: api)
        await schedule.load(); await headlines.load(); await postseason.refresh()
        #expect(schedule.errorMessage == nil)
        #expect(headlines.errorMessage == nil)
        #expect(!postseason.refreshFailed)
        do {
            let _: Data = try await api.data(.url(URL(string: "https://example.test/cancel")!))
            Issue.record("Cancellation should throw")
        } catch { #expect(APIError.isCancellation(error)) }
    }

    @Test @MainActor func partialHomeAndStandings() async {
        ArchitectureProtocol.reset("noStandings")
        let session = session(); defer { session.invalidateAndCancel() }
        let api = APIClient(session: session)
        let team = TeamSession(team: .boston, api: api)
        await team.home.load()
        #expect(team.home.recentGame?.gamePk == 42)
        #expect(team.home.schedule != nil)
        #expect(team.home.standings == nil)
        #expect(team.home.sectionErrors == ["Standings unavailable"])
        ArchitectureProtocol.reset("oneLeague")
        await team.standings.load()
        #expect(team.standings.feeds[.american] != nil)
        #expect(team.standings.errors[.national] != nil)
    }

    @Test func overlappingGamesSharePayloadButKeepTeamPerspective() async throws {
        ArchitectureProtocol.reset("normal")
        let session = session(); defer { session.invalidateAndCancel() }
        let api = APIClient(session: session, cachesGameFeeds: true)
        async let boston = MLBGameClient(team: .boston, api: api).game(gamePk: 42)
        async let newYork = MLBGameClient(team: .newYork, api: api).game(gamePk: 42)
        let games = try await (boston, newYork)
        #expect(ArchitectureProtocol.gameRequests == 1)
        #expect(games.0.result == "Win" && games.1.result == "Loss")
        #expect(games.0.summary.contains("Red Sox") && games.1.summary.contains("Yankees"))
        _ = try await MLBGameClient(team: .boston, api: api).game(gamePk: 42, cachePolicy: .reloadIgnoringLocalCacheData)
        #expect(ArchitectureProtocol.gameRequests == 2)
    }

    @Test func forcedRetrySupersedesAnOrdinaryRequest() async throws {
        let feeds = MLBGameFeeds()
        let gate = Gate()
        let old = MLBGamePayload(gamePk: 42, narratives: ["111": .init(summary: "old", facts: [])])
        let fresh = MLBGamePayload(gamePk: 42, narratives: ["111": .init(summary: "fresh", facts: [])])
        let first = Task { try await feeds.get(42, force: false) { await gate.wait(); return old } }
        while !(await gate.started) { await Task.yield() }
        let retry = try await feeds.get(42, force: true) { fresh }
        #expect(retry.narratives?["111"]?.summary == "fresh")
        await gate.release()
        _ = try await first.value
        let cached = try await feeds.get(42, force: false) { Issue.record("Expected cached retry"); return old }
        #expect(cached.narratives?["111"]?.summary == "fresh")
    }

    @Test @MainActor func schedulerVisibilityAndResume() async throws {
        var now = Date(timeIntervalSince1970: 1000)
        var requests = 0
        let scheduler = RefreshScheduler(now: { now })
        defer { scheduler.stop() }
        scheduler.register("standings") { requests += 1; return true }
        scheduler.setVisible(true, observer: "home", jobs: ["standings"])
        try await Task.sleep(for: .milliseconds(30))
        #expect(requests == 1)
        scheduler.setVisible(false, observer: "home", jobs: ["standings"])
        scheduler.setVisible(true, observer: "standings", jobs: ["standings"])
        scheduler.setVisible(true, observer: "home", jobs: ["standings"])
        try await Task.sleep(for: .milliseconds(30))
        #expect(requests == 1, "Tab switches share the successful load")
        scheduler.setBackground(true)
        now += 20
        scheduler.setBackground(false)
        try await Task.sleep(for: .milliseconds(30))
        #expect(requests == 1, "Brief background transitions do not reload")
        scheduler.setBackground(true)
        now += 20
        scheduler.setBackground(false)
        try await Task.sleep(for: .milliseconds(30))
        #expect(requests == 2, "A stale resume refreshes exactly once")
    }

    @Test @MainActor func schedulerRetriesARefreshCancelledByLeaving() async throws {
        var now = Date(timeIntervalSince1970: 1000)
        var isLoading = false
        var started = 0
        var completed = 0
        let scheduler = RefreshScheduler(now: { now })
        defer { scheduler.stop() }
        // Like the stores: ignore a load while one is in flight, and return
        // quietly (no error message) when cancelled.
        scheduler.register("standings") {
            guard !isLoading else { return true }
            isLoading = true
            defer { isLoading = false }
            started += 1
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return true }
            completed += 1
            return true
        }
        scheduler.setVisible(true, observer: "standings", jobs: ["standings"])
        try await Task.sleep(for: .milliseconds(30))
        // Swipe away before the first load finishes, then return five seconds later.
        scheduler.setVisible(false, observer: "standings", jobs: ["standings"])
        now += 5
        scheduler.setVisible(true, observer: "standings", jobs: ["standings"])
        try await Task.sleep(for: .milliseconds(400))
        #expect(started == 2, "Returning retries the cancelled load instead of waiting out the interval")
        #expect(completed == 1)
    }

    @Test func sharedDateParsing() {
        #expect(FeedDate.date(from: "2026-10-06T19:00:00Z") == FeedDate.date(from: "2026-10-06T15:00:00.000-04:00"))
        #expect(FeedDate.date(from: "not a date") == nil)
    }

    @Test func diskCacheBounds() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SnapshotFileCache(name: "fixture.json", directory: directory)
        #expect(await cache.write(Data("{}".utf8)))
        #expect(await cache.read() == Data("{}".utf8))
        #expect(await cache.write(Data(repeating: 0, count: 3 * 1024 * 1024)) == false)
        #expect(await cache.read() == Data("{}".utf8))
    }
}
