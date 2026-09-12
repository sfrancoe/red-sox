import Foundation
import Observation

@MainActor
@Observable
final class HomeRunChaseStore {
    var config = ChaseData.config()
    var isRefreshing = false
    var refreshNote: String?

    func load() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let liveSeason = try await Self.fetchJudgeSeason()
            let seasonEnd = try? await Self.fetchRegularSeasonEnd(year: liveSeason.year)
            var judge = ChaseData.judge
            if let index = judge.seasons.firstIndex(where: { $0.year == liveSeason.year }) {
                judge.seasons[index] = liveSeason
            } else if liveSeason.year > (judge.seasons.last?.year ?? 0) {
                judge.seasons.append(liveSeason)
            }

            let total = judge.seasons.reduce(0) { $0 + $1.hr }
            let projectedTotal = Self.projectionTotal(
                for: judge,
                liveTotal: total,
                regularSeasonEnd: seasonEnd
            )
            config = ChaseData.config(subject: judge, projectionHR: projectedTotal)
            refreshNote = "Updated from MLB"
        } catch {
            refreshNote = "Using verified offline totals"
        }
    }

    private static func fetchJudgeSeason() async throws -> HRSeason {
        let year = Calendar(identifier: .gregorian).component(
            .year,
            from: Date()
        )
        guard let url = URL(string:
            "https://statsapi.mlb.com/api/v1/people/\(ChaseData.judgePlayerID)/stats?stats=season&group=hitting&season=\(year)"
        ) else {
            throw ChaseStoreError.badURL
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw ChaseStoreError.badResponse
        }

        let payload = try JSONDecoder().decode(MLBStatsPayload.self, from: data)
        guard let split = payload.stats.first?.splits.first else {
            throw ChaseStoreError.missingStats
        }
        let age = 34 + (year - ChaseData.projectionYear)
        return HRSeason(year: year, age: age, hr: split.stat.homeRuns, ab: split.stat.atBats)
    }

    private static func fetchRegularSeasonEnd(year: Int) async throws -> Date {
        guard let url = URL(string: "https://statsapi.mlb.com/api/v1/seasons/\(year)?sportId=1") else {
            throw ChaseStoreError.badURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw ChaseStoreError.badResponse
        }
        let payload = try JSONDecoder().decode(MLBSeasonPayload.self, from: data)
        guard let rawDate = payload.seasons.first?.regularSeasonEndDate else {
            throw ChaseStoreError.missingStats
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: rawDate) else {
            throw ChaseStoreError.missingStats
        }
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: date) ?? date
    }

    private static func projectionTotal(
        for player: PlayerHRSeries,
        liveTotal: Int,
        regularSeasonEnd: Date?
    ) -> Int {
        guard let latest = player.seasons.last else { return liveTotal }

        // The projection begins at season's end. During the 2026 regular season,
        // retain the spec's conservative three-homer remainder; the MLB calendar
        // flips the baseline to the real final total when the regular season ends.
        if latest.year == 2026,
           let regularSeasonEnd,
           Date() < regularSeasonEnd {
            return liveTotal + 3
        }
        return liveTotal
    }
}

private struct MLBSeasonPayload: Decodable {
    let seasons: [Season]

    struct Season: Decodable {
        let regularSeasonEndDate: String
    }
}

private struct MLBStatsPayload: Decodable {
    let stats: [StatsBlock]

    struct StatsBlock: Decodable {
        let splits: [Split]
    }

    struct Split: Decodable {
        let stat: Stats
    }

    struct Stats: Decodable {
        let homeRuns: Int
        let atBats: Int
    }
}

private enum ChaseStoreError: Error {
    case badURL
    case badResponse
    case missingStats
}
