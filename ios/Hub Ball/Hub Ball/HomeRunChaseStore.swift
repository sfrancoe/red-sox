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
            let live = try await Self.fetchJudgeSeason()
            let liveSeason = live.season
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
                regularSeasonEnd: live.regularSeasonEnd
            )
            config = ChaseData.config(subject: judge, projectionHR: projectedTotal)
            refreshNote = "Updated from MLB"
        } catch {
            refreshNote = "Using verified offline totals"
        }
    }

    private static func fetchJudgeSeason() async throws -> LiveJudgeSeason {
        var request = URLRequest(url: AppBackend.apiURL("hr-chase", team: .newYork))
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw ChaseStoreError.badResponse
        }

        let payload = try JSONDecoder().decode(LiveJudgePayload.self, from: data)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: payload.regularSeasonEndDate) else {
            throw ChaseStoreError.missingStats
        }
        let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: date) ?? date
        return LiveJudgeSeason(
            season: HRSeason(
                year: payload.year,
                age: payload.age,
                hr: payload.homeRuns,
                ab: payload.atBats
            ),
            regularSeasonEnd: end
        )
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

private struct LiveJudgeSeason {
    let season: HRSeason
    let regularSeasonEnd: Date
}

private struct LiveJudgePayload: Decodable {
    let year: Int
    let age: Int
    let homeRuns: Int
    let atBats: Int
    let regularSeasonEndDate: String
}

private enum ChaseStoreError: Error {
    case badResponse
    case missingStats
}
