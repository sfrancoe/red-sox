import Foundation
import Observation

@MainActor
@Observable
final class RecentGameStore {
    private static let endpoint = URL(
        string: "https://red-sox.netlify.app/data/recent-game.json"
    )!

    var game: RecentGame?
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
                throw RecentGameError.badResponse
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            game = try decoder.decode(RecentGame.self, from: data)
        } catch {
            errorMessage = "We couldn't load the latest game. Check your connection and try again."
        }
    }
}

private enum RecentGameError: Error {
    case badResponse
}
