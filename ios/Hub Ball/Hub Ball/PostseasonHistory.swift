import Foundation
import Observation

enum PostseasonHistoryGroup: String, CaseIterable {
    case hitting = "Batting"
    case pitching = "Pitching"

    var sampleUnit: String {
        self == .hitting ? "plate appearances" : "innings"
    }
}

struct PostseasonPlayerSelection: Identifiable {
    let playerID: Int
    let teamID: Int

    var id: String { "\(teamID)-\(playerID)" }
}

enum PostseasonHistorySortColumn {
    case season
    case career
}

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

    func meetsMinimum(_ minimum: Int, group: PostseasonHistoryGroup, column: PostseasonHistorySortColumn) -> Bool {
        guard minimum > 0 else { return true }
        let stat = column == .season ? season : career
        guard let stat else { return false }
        switch group {
        case .hitting:
            return (stat.plateAppearances ?? 0) >= minimum
        case .pitching:
            guard let innings = stat.inningsPitched else { return false }
            let parts = innings.split(separator: ".", omittingEmptySubsequences: false)
            guard (1...2).contains(parts.count), let whole = Int(parts[0]), whole >= 0,
                  let outs = parts.count == 2 ? Int(parts[1]) : 0,
                  (0...2).contains(outs) else { return false }
            // Thresholds are whole innings: 2.2 means two innings and two outs,
            // so it remains below a three-inning minimum.
            return whole >= minimum
        }
    }
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
