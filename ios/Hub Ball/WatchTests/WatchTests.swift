import Foundation

@main
struct WatchTests {
    @MainActor
    static func main() async throws {
        let channel = "UCtestChannel"
        func entry(_ id: String, title: String = "A &amp; B", date: String = "2026-09-14T10:00:00+00:00", source: String = "UCtestChannel") -> String {
            """
            <entry><yt:videoId>\(id)</yt:videoId><yt:channelId>\(source)</yt:channelId>
            <title>\(title)</title><author><name>Team</name></author><published>\(date)</published>
            <media:group><media:title>Wrong title</media:title><media:description>Ignore me</media:description></media:group></entry>
            """
        }
        func feed(_ content: String) -> Data {
            Data("<feed xmlns:yt='http://www.youtube.com/xml/schemas/2015' xmlns:media='http://search.yahoo.com/mrss/'>\(content)</feed>".utf8)
        }
        let parser = WatchFeedParser(channelID: channel)
        let values = try parser.parse(feed(entry("abcdefghijk") + entry("abcdefghijk") + entry("12345678901", date: "2026-09-15T10:00:00+00:00")))
        precondition(values.count == 2, "Duplicate uploads must be removed")
        precondition(values[0].id == "12345678901", "Newest upload must lead")
        precondition(values[1].title == "A & B", "Decode XML text without replacing titles with media metadata")
        precondition(values[0].url.host == "www.youtube.com")
        precondition(values[0].shareText.contains("Hub Ball"))
        for invalid in ["<html>blocked</html>", "<feed>", String(data: feed(entry("../bad") + entry("abcdefghijk", source: "impostor") + entry("12345678901", date: "not-a-date")), encoding: .utf8)!] {
            do {
                _ = try parser.parse(Data(invalid.utf8))
                fatalError("Invalid content must fail without clearing cached results")
            } catch {}
        }
        precondition(WatchVideo.validID("ab_C-d12345"))
        precondition(!WatchVideo.validID("abc<script>"))
        if CommandLine.arguments.count > 1 {
            let videos = try WatchFeedParser(channelID: "UCoLrcjPV5PbUrUyXq5mjc_A")
                .parse(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            precondition(videos.count == 15)
            print("Live MLB Atom fixture: \(videos.count) videos parsed")
        }
        precondition(WatchSources.channels.count == HubTeam.allCases.count)
        for team in HubTeam.allCases {
            precondition(WatchSources.channels[team.apiKey]?.hasPrefix("UC") == true)
        }
        let suite = "HubWatchTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WatchTestProtocol.self]
        let session = URLSession(configuration: config)
        let store = WatchStore(team: .boston, preferences: preferences, session: session)
        await store.load()
        precondition(store.teamVideos.count == 1 && store.leagueVideos.count == 1)
        precondition(store.notice == nil && !store.isLoading)
        let video = store.teamVideos[0]
        store.toggleSaved(video)
        precondition(store.isSaved(video))
        let restored = WatchStore(team: .boston, preferences: preferences, session: session)
        precondition(restored.saved == [video], "Bookmarks must survive recreating the screen")
        WatchTestProtocol.blocked = true
        await store.load()
        precondition(store.teamVideos == [video] && store.notice != nil, "Failed refresh must retain cached results and disclose staleness")
        store.toggleSaved(video)
        precondition(!store.isSaved(video))
        let empty = WatchStore(team: .newYork, preferences: preferences, session: session)
        await empty.load()
        precondition(empty.teamVideos.isEmpty && empty.notice != nil, "Never show another team's videos as this team's feed")
        print("Watch parsing, all 30 sources, bookmarks, refresh and offline fallback checks passed")
    }
}


final class WatchTestProtocol: URLProtocol {
    nonisolated(unsafe) static var blocked = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.blocked {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let channel = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            .queryItems!.first(where: { $0.name == "channel_id" })!.value!
        let xml = """
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"><entry>
        <yt:videoId>abcdefghijk</yt:videoId><yt:channelId>\(channel)</yt:channelId>
        <title>Team highlights</title><author><name>Team</name></author>
        <published>2026-09-14T10:00:00+00:00</published></entry></feed>
        """
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(xml.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
