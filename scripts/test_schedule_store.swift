import Foundation

// URLProtocol keeps these tests offline while exercising URLSession, decoding,
// throttling, failure recovery, and cancellation in the real ScheduleStore.
final class ScheduleProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requestCount = 0
    nonisolated(unsafe) private static var statusCode = 200
    nonisolated(unsafe) private static var shouldStall = false

    static var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    static func configure(status: Int = 200, stall: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        statusCode = status
        shouldStall = stall
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requestCount += 1
        let status = Self.statusCode
        let stall = Self.shouldStall
        Self.lock.unlock()
        if stall { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        let payload = #"{"generated_at":"fixture","regular_season_end":"2026-09-27","source":"test","team":"Boston","games":[]}"#
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct ScheduleStoreTests {
    @MainActor
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScheduleProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var now = Date(timeIntervalSince1970: 1_000)
        let store = ScheduleStore(session: session, now: { now })

        await store.load(minimumRefreshInterval: 300)
        precondition(ScheduleProtocol.count == 1 && store.schedule?.generatedAt == "fixture")
        // Fourteen live-score refreshes should not trigger schedule downloads.
        for _ in 0..<14 {
            now += 20
            await store.load(minimumRefreshInterval: 300)
        }
        precondition(ScheduleProtocol.count == 1)
        now += 20
        await store.load(minimumRefreshInterval: 300)
        precondition(ScheduleProtocol.count == 2)

        // Schedule-screen/manual loads retain their existing immediate behavior.
        await store.load()
        precondition(ScheduleProtocol.count == 3)

        // A failed request retains the last good schedule and backs off.
        ScheduleProtocol.configure(status: 503)
        now += 300
        await store.load(minimumRefreshInterval: 300)
        precondition(ScheduleProtocol.count == 4 && store.errorMessage != nil)
        precondition(store.schedule?.generatedAt == "fixture")
        now += 20
        await store.load(minimumRefreshInterval: 300)
        precondition(ScheduleProtocol.count == 4)
        ScheduleProtocol.configure()
        now += 280
        await store.load(minimumRefreshInterval: 300)
        precondition(ScheduleProtocol.count == 5 && store.errorMessage == nil)

        // Background cancellation must not show an error or delay the next
        // foreground attempt by five minutes. Concurrent loads also coalesce.
        ScheduleProtocol.configure(stall: true)
        now += 300
        let pending = Task { await store.load(minimumRefreshInterval: 300) }
        for _ in 0..<100 where ScheduleProtocol.count < 6 {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(ScheduleProtocol.count == 6 && store.isLoading)
        await store.load(minimumRefreshInterval: 300)
        precondition(ScheduleProtocol.count == 6)
        pending.cancel()
        await pending.value
        precondition(!store.isLoading && store.errorMessage == nil)
        ScheduleProtocol.configure()
        await store.load(minimumRefreshInterval: 300)
        precondition(ScheduleProtocol.count == 7)
        print("ScheduleStore: initial load, 5-minute throttle, explicit refresh, outage recovery, coalescing, and cancellation passed.")
    }
}
