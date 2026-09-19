import Foundation
import Observation

@MainActor
@Observable
final class ScheduleStore {
    private let endpoint: URL
    private let session: URLSession
    private let now: () -> Date
    private var lastRefreshAttempt: Date?

    var schedule: Schedule?
    var isLoading = false
    var errorMessage: String?

    init(team: HubTeam = .boston, session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        endpoint = AppBackend.dataURL("schedule.json", team: team)
        self.session = session
        self.now = now
    }

    func load(minimumRefreshInterval: TimeInterval = 0) async {
        guard !isLoading, !Task.isCancelled else { return }
        // Throttle attempts as well as successes so an outage does not cause a
        // schedule request on every live-score tick. Explicit loads still refresh.
        if let lastRefreshAttempt,
           now().timeIntervalSince(lastRefreshAttempt) < minimumRefreshInterval {
            return
        }
        lastRefreshAttempt = now()

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 20

            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ScheduleError.badResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            schedule = try decoder.decode(Schedule.self, from: data)
        } catch {
            if Task.isCancelled {
                lastRefreshAttempt = nil
                return
            }
            errorMessage = "We couldn't load the schedule. Check your connection and try again."
        }
    }
}

private enum ScheduleError: Error {
    case badResponse
}
