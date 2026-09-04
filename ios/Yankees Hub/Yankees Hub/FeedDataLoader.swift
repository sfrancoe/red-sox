import Foundation

enum FeedDataLoader {
    static func data(from endpoint: URL, bundledResource: String) async throws -> Data {
        do {
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw FeedDataError.badResponse
            }
            return data
        } catch {
            return try bundledData(named: bundledResource)
        }
    }

    static func bundledData(named resource: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            throw FeedDataError.missingBundledResource
        }
        return try Data(contentsOf: url)
    }
}

private enum FeedDataError: Error {
    case badResponse
    case missingBundledResource
}
