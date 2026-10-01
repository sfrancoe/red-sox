import Foundation
import Observation

struct PostseasonHistoryPayload: Codable, Sendable {
    let schemaVersion: Int
    let season: Int
    let status: String
    let generatedAt: String
    let rosterRefreshedAt: String
    let statsRefreshedAt: String
    let source: String
    let sourceURL: String
    let rosterType: String
    let teams: [PostseasonHistoryTeam]
    let playerCount: Int
    let categories: PostseasonHistoryCategories

    var generatedDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: generatedAt) ?? ISO8601DateFormatter().date(from: generatedAt)
    }
}

struct PostseasonHistoryTeam: Codable, Identifiable, Sendable {
    let teamId: Int
    let name: String
    let abbreviation: String
    let league: String

    var id: Int { teamId }
}

struct PostseasonHistoryCategories: Codable, Sendable {
    let hitting: [PostseasonHistoryCategory]
    let pitching: [PostseasonHistoryCategory]
}

struct PostseasonHistoryCategory: Codable, Identifiable, Sendable {
    let key: String
    let label: String
    let higherIsBetter: Bool
    let entries: [PostseasonHistoryEntry]

    var id: String { key }
}

struct PostseasonHistoryEntry: Codable, Identifiable, Sendable {
    let playerId: Int
    let name: String
    let teamId: Int
    let teamAbbreviation: String
    let league: String?
    let season: PostseasonHistoryStat?
    let career: PostseasonHistoryStat?

    var id: Int { playerId }
}

struct PostseasonHistoryStat: Codable, Sendable {
    let value: Double
    let games: Int
    let plateAppearances: Int?
    let inningsPitched: String?
}

@MainActor
@Observable
final class PostseasonHistoryStore {
    private(set) var snapshot: PostseasonHistoryPayload?
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
        snapshotURL = directory.appending(path: "history-\(season).json")
        snapshot = Self.readSnapshot(from: snapshotURL)
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var request = URLRequest(
                url: AppBackend.sharedDataURL("postseason-history/\(season)-v2.json")
            )
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let incoming = try JSONDecoder().decode(PostseasonHistoryPayload.self, from: data)
            guard incoming.schemaVersion == 2, incoming.season == season else {
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

    private static func readSnapshot(from url: URL) -> PostseasonHistoryPayload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(PostseasonHistoryPayload.self, from: data),
              snapshot.schemaVersion == 2 else { return nil }
        return snapshot
    }
}
