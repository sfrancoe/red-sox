import Foundation
import OSLog

nonisolated enum Endpoint: Sendable {
    case data(String, team: HubTeam)
    case sharedData(String)
    case api(String, team: HubTeam)
    case sharedAPI(String)
    case url(URL)

    var url: URL {
        switch self {
        case let .data(path, team): AppBackend.dataURL(path, team: team)
        case let .sharedData(path): AppBackend.sharedDataURL(path)
        case let .api(path, team): AppBackend.apiURL(path, team: team)
        case let .sharedAPI(path): AppBackend.sharedAPIURL(path)
        case let .url(url): url
        }
    }
}

nonisolated enum APIError: Error {
    case http(status: Int)
    case decoding(underlying: any Error)
    case transport(URLError)
    case cancelled

    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if case .cancelled = error as? APIError { return true }
        return (error as? URLError)?.code == .cancelled
    }
}

/// Stores publish on MainActor; requests and decoding execute outside it.
nonisolated struct APIClient: Sendable {
    static let shared = APIClient()
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1_024 * 1_024,
                                          diskCapacity: 64 * 1_024 * 1_024)
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()
    private let session: URLSession
    private let decoder = APIDecoder()
    let gameFeeds = MLBGameFeeds()
    let cachesGameFeeds: Bool

    init(session: URLSession = APIClient.session, cachesGameFeeds: Bool? = nil) {
        self.session = session
        self.cachesGameFeeds = cachesGameFeeds ?? (session === APIClient.session)
    }

    @concurrent func get<T: Decodable & Sendable>(
        _ endpoint: Endpoint,
        cachePolicy: URLRequest.CachePolicy = .reloadRevalidatingCacheData,
        snakeCase: Bool = true
    ) async throws -> T {
        let data = try await data(endpoint, cachePolicy: cachePolicy)
        do {
            let value: T = try await decoder.decode(data, snakeCase: snakeCase)
            try Task.checkCancellation()
            return value
        } catch {
            if APIError.isCancellation(error) { throw APIError.cancelled }
            log(error, endpoint: endpoint)
            throw APIError.decoding(underlying: error)
        }
    }

    @concurrent func data(
        _ endpoint: Endpoint,
        cachePolicy: URLRequest.CachePolicy = .reloadRevalidatingCacheData
    ) async throws -> Data {
        do {
            try Task.checkCancellation()
            var request = URLRequest(url: endpoint.url)
            request.cachePolicy = cachePolicy
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(response.statusCode) else {
                throw APIError.http(status: response.statusCode)
            }
            return data
        } catch {
            if APIError.isCancellation(error) { throw APIError.cancelled }
            log(error, endpoint: endpoint)
            if let error = error as? URLError { throw APIError.transport(error) }
            throw error
        }
    }

    func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data,
                                         snakeCase: Bool = true) async throws -> T {
        do { return try await decoder.decode(data, snakeCase: snakeCase) }
        catch { throw APIError.decoding(underlying: error) }
    }

    private func log(_ error: any Error, endpoint: Endpoint) {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "HubBall", category: endpoint.url.path)
            .error("Request failed: \(String(describing: error), privacy: .public)")
    }
}

/// Isolate the shared decoders rather than sharing mutable decoder state across tasks.
private actor APIDecoder {
    private let snake: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    private let plain = JSONDecoder()

    func decode<T: Decodable & Sendable>(_ data: Data, snakeCase: Bool) throws -> T {
        try (snakeCase ? snake : plain).decode(T.self, from: data)
    }
}
