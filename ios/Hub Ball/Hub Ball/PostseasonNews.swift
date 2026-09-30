import Foundation
import Observation

struct PostseasonNewsPayload: Codable, Sendable {
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

struct PostseasonNewsArticle: Codable, Identifiable, Sendable {
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

private enum PostseasonNewsDate {
    static func text(from value: String) -> String {
        guard let date = date(from: value) else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = BaseballTime.calendar
        formatter.timeZone = BaseballTime.timeZone
        formatter.dateFormat = "MM/dd h:mm a"
        return formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

@MainActor
@Observable
final class PostseasonNewsStore {
    private(set) var snapshot: PostseasonNewsPayload?
    private(set) var isLoading = false
    private(set) var refreshFailed = false

    let season: Int
    private let session: URLSession
    private let snapshotURL: URL

    init(season: Int, session: URLSession = .shared) {
        self.season = season
        self.session = session
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
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let incoming = try JSONDecoder().decode(PostseasonNewsPayload.self, from: data)
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
            refreshFailed = true
        }
    }

    private static func readSnapshot(from url: URL) -> PostseasonNewsPayload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PostseasonNewsPayload.self, from: data)
    }
}
