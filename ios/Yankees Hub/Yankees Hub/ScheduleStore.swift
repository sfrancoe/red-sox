import Foundation
import Observation

@MainActor
@Observable
final class ScheduleStore {
    private static let endpoint = TeamConfig.dataURL("schedule.json")

    var schedule: Schedule?
    var isLoading = false
    var errorMessage: String?

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await FeedDataLoader.data(
                from: Self.endpoint,
                bundledResource: "yankees-schedule"
            )
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            schedule = try decoder.decode(Schedule.self, from: data)
        } catch {
            errorMessage = "We couldn't load the schedule. Check your connection and try again."
        }
    }
}
