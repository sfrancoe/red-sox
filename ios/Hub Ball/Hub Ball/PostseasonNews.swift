import Foundation
import Observation

nonisolated struct PostseasonNewsPayload: Codable, Sendable {
    let schemaVersion: Int
    let season: Int
    let generatedAt: String
    let windowHours: Int
    let source: String
    let sourceURL: String
    let teamCount: Int
    let coveredTeamCount: Int
    let articles: [PostseasonNewsArticle]

    var generatedText: String {
        PostseasonNewsDate.text(from: generatedAt)
    }
}

nonisolated struct PostseasonNewsArticle: Codable, Identifiable, Sendable {
    let title: String
    let description: String
    let url: String
    let published: String
    let source: String
    let teamId: Int
    let teamName: String
    let teamAbbreviation: String
    let league: String
    let publishedSource: String?

    var id: String { url }

    var publishedText: String {
        guard publishedSource == "publisher" else { return "Time unavailable" }
        return PostseasonNewsDate.text(from: published)
    }
}

private nonisolated enum PostseasonNewsDate {
    static func text(from value: String) -> String {
        guard let date = date(from: value) else { return "—" }
        let formatter = BaseballDateFormat.news
        return formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        return FeedDate.date(from: value)
    }
}

@MainActor
@Observable
final class PostseasonNewsStore {
    private(set) var snapshot: PostseasonNewsPayload?
    private(set) var isLoading = false
    private(set) var refreshFailed = false

    let season: Int
    private let api: APIClient
    private let snapshotURL: URL

    init(season: Int, session: URLSession = APIClient.session, api: APIClient? = nil) {
        self.season = season
        self.api = api ?? (session === APIClient.session ? .shared : APIClient(session: session))
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appending(path: "October", directoryHint: .isDirectory)
        snapshotURL = directory.appending(path: "news-\(season).json")
        snapshot = Self.readSnapshot(from: snapshotURL)
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var request = URLRequest(
                url: AppBackend.sharedDataURL("postseason-news/\(season).json")
            )
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            let data = try await api.data(.url(request.url!), cachePolicy: request.cachePolicy)
            let incoming = try await api.decode(PostseasonNewsPayload.self, from: data, snakeCase: false)
            guard incoming.schemaVersion == 1, incoming.season == season else {
                throw URLError(.cannotDecodeContentData)
            }
            snapshot = incoming
            refreshFailed = false
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: snapshotURL, options: .atomic)
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled || APIError.isCancellation(error) { return }
            refreshFailed = true
        }
    }

    private static func readSnapshot(from url: URL) -> PostseasonNewsPayload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PostseasonNewsPayload.self, from: data)
    }
}
