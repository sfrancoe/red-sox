import Foundation
import Observation

@MainActor
@Observable
final class XPostsStore {
    private static let endpoint = TeamConfig.apiURL(
        "x-discovery",
        queryItems: [URLQueryItem(name: "team", value: "yankees")]
    )

    var feed: XFeed?
    var selectedMode: XFeedMode = .liked
    var isLoading = false
    var errorMessage: String?

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedFeed = try await fetchFeed(from: Self.endpoint)
            guard loadedFeed.sourceUrl.localizedCaseInsensitiveContains("Yankees") else {
                throw XPostsError.wrongTeam
            }
            feed = loadedFeed
        } catch {
            errorMessage = "We couldn't load the X posts. Check your connection and try again."
        }
    }

    private func fetchFeed(from endpoint: URL) async throws -> XFeed {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw XPostsError.badResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(XFeed.self, from: data)
    }

}

private enum XPostsError: Error {
    case badResponse
    case wrongTeam
}
