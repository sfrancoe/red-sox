import Foundation
import Observation

@MainActor
@Observable
final class ScheduleStore {
    private let endpoint: URL
    private let api: APIClient
    private let now: () -> Date
    private var lastRefreshAttempt: Date?

    var schedule: Schedule?
    var isLoading = false
    var errorMessage: String?

    init(
        team: HubTeam = .boston,
        session: URLSession = APIClient.session, api: APIClient? = nil,
        now: @escaping () -> Date = Date.init,
        backendOrigin: URL? = nil
    ) {
        endpoint = backendOrigin.map {
            $0.appending(path: "data")
                .appending(path: team.dataPathComponent ?? "")
                .appending(path: "schedule.json")
        } ?? AppBackend.dataURL("schedule.json", team: team)
        self.api = api ?? (session === APIClient.session ? .shared : APIClient(session: session))
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

            let data = try await api.data(.url(request.url!), cachePolicy: request.cachePolicy)

            schedule = try await api.decode(Schedule.self, from: data)
        } catch {
            if Task.isCancelled || APIError.isCancellation(error) {
                lastRefreshAttempt = nil
                return
            }
            errorMessage = "We couldn't load the schedule. Check your connection and try again."
        }
    }
}

