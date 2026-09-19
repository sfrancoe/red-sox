import Foundation
import Observation

@MainActor
@Observable
final class WatchStore {
    var teamVideos: [WatchVideo] = []
    var leagueVideos: [WatchVideo] = []
    var saved: [WatchVideo] = []
    var isLoading = false
    var notice: String?
    var updatedAt: Date?
    private let team: HubTeam
    private let session: URLSession
    private let preferences: UserDefaults
    private let savedKey = "hubWatchSavedVideos.v1"
    private static let fallbackAgent = "OpenAI File Downloader, XaiImageApiFetch/1.0"

    init(team: HubTeam, preferences: UserDefaults = .standard, session: URLSession = .shared) {
        self.team = team
        self.session = session
        self.preferences = preferences
        if let data = preferences.data(forKey: savedKey),
           let values = try? JSONDecoder().decode([WatchVideo].self, from: data) {
            saved = values.filter { WatchVideo.validID($0.id) }
        }
    }

    func isSaved(_ video: WatchVideo) -> Bool { saved.contains { $0.id == video.id } }

    func toggleSaved(_ video: WatchVideo) {
        if isSaved(video) { saved.removeAll { $0.id == video.id } }
        else { saved.insert(video, at: 0) }
        if let data = try? JSONEncoder().encode(saved) { preferences.set(data, forKey: savedKey) }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        notice = nil
        defer { isLoading = false }
        let channel = WatchSources.channelID(for: team)
        async let teamResult = fetch(channel)
        async let leagueResult = fetch(WatchSources.mlb)
        let (local, league) = await (teamResult, leagueResult)
        guard !Task.isCancelled else { return }
        teamVideos = local.videos
        leagueVideos = league.videos
        updatedAt = [local.date, league.date].compactMap { $0 }.min()
        if local.cached || league.cached {
            notice = "Some videos couldn’t refresh. Showing saved listings where available. Pull to refresh."
        }
    }

    private func fetch(_ channel: String) async -> (videos: [WatchVideo], date: Date?, cached: Bool) {
        let key = "hubWatchFeed.\(channel)"
        for fallback in [false, true] {
            do {
                try Task.checkCancellation()
                var request = URLRequest(url: URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channel)")!)
                request.timeoutInterval = 12
                request.cachePolicy = .reloadRevalidatingCacheData
                if fallback { request.setValue(Self.fallbackAgent, forHTTPHeaderField: "User-Agent") }
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      data.count < 2_000_000 else { throw WatchFeedError.badResponse }
                let videos = try WatchFeedParser(channelID: channel).parse(data)
                let cache = CachedFeed(videos: videos, date: Date())
                if let encoded = try? JSONEncoder().encode(cache) { preferences.set(encoded, forKey: key) }
                return (videos, cache.date, false)
            } catch {
                if Task.isCancelled { return ([], nil, true) }
            }
        }
        if let data = preferences.data(forKey: key),
           let cache = try? JSONDecoder().decode(CachedFeed.self, from: data),
           Date().timeIntervalSince(cache.date) < 7 * 24 * 60 * 60 {
            return (cache.videos, cache.date, true)
        }
        return ([], nil, true)
    }

    private struct CachedFeed: Codable { let videos: [WatchVideo]; let date: Date }
}
