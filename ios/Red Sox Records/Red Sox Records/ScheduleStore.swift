import Foundation
import Observation

@MainActor
@Observable
final class ScheduleStore {
    private static let endpoint = URL(
        string: "https://red-sox.netlify.app/data/schedule.json"
    )!

    var schedule: Schedule?
    var isLoading = false
    var errorMessage: String?

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var request = URLRequest(url: Self.endpoint)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ScheduleError.badResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            schedule = try decoder.decode(Schedule.self, from: data)
        } catch {
            errorMessage = "We couldn't load the schedule. Check your connection and try again."
        }
    }
}

private enum ScheduleError: Error {
    case badResponse
}
