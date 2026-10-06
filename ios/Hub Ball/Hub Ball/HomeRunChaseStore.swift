import Foundation
import Observation

@MainActor
@Observable
final class HomeRunChaseStore {
    private let api: APIClient

    init(api: APIClient = .shared) { self.api = api }
    var config = ChaseData.config()
    var isRefreshing = false
    var refreshNote: String?

    func load() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let live = try await fetchJudgeSeason()
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
            if Task.isCancelled || APIError.isCancellation(error) { return }
            refreshNote = "Using verified offline totals"
        }
    }

    private func fetchJudgeSeason() async throws -> LiveJudgeSeason {
        let payload: LiveJudgePayload = try await api.get(.api("hr-chase", team: .newYork), snakeCase: false)
        let formatter = BaseballDateFormat.day
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

nonisolated private struct LiveJudgePayload: Decodable, Sendable {
    let year: Int
    let age: Int
    let homeRuns: Int
    let atBats: Int
    let regularSeasonEndDate: String
}

private enum ChaseStoreError: Error {
    case missingStats
}
