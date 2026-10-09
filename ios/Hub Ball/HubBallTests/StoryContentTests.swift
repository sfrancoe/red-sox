import Foundation
import Testing
@testable import Hub_Ball

private actor StoryFixtureTransport {
    var content: [String: Data] = [:]
    var failure: URLError?
    var requests: [String] = []
    var policies: [URLRequest.CachePolicy] = []
    func set(_ path: String, _ data: Data) { content[path] = data }
    func fail(_ error: URLError?) { failure = error }
    func get(_ url: URL, policy: URLRequest.CachePolicy) throws -> Data {
        requests.append(url.absoluteString); policies.append(policy)
        if let failure { throw failure }
        guard let data = content[url.path] else { throw URLError(.fileDoesNotExist) }
        return data
    }
}

@Suite(.serialized) @MainActor
struct StoryContentTests {
    private func folder() -> URL { FileManager.default.temporaryDirectory.appending(path: "story-test-\(UUID().uuidString)") }
    private func fixture(id: String = "this-stadium", title: String? = nil) throws -> (StoryEntry, Data) {
        let original = try #require(StorySeed.catalog.stories.first(where: { $0.id == "this-stadium" }))
        let bytes = try #require(StorySeed.payload(original))
        var payload = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        payload["id"] = id
        if let title { payload["title"] = title }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let entry = StoryEntry(id: id, revision: StoryContract.hash(data), title: title ?? original.title, summary: original.summary,
                               fallback: original.fallback, publishedAt: original.publishedAt, teamIDs: original.teamIDs,
                               renderer: "guess-reveal", rendererVersion: 1, minimumRendererVersion: 1)
        return (entry, data)
    }
    private func catalog(_ entries: [StoryEntry], revision: String = "fixture") throws -> Data {
        try JSONEncoder().encode(StoryCatalog(schemaVersion: 1, revision: revision, publishedAt: "2026-10-08T11:00:00Z", stories: entries))
    }
    private func store(_ transport: StoryFixtureTransport, cache: StoryContentCache, root: String = "https://api.autumnlane.io/api/data") -> StoryCatalogStore {
        StoryCatalogStore(root: URL(string: root)!, cache: cache, seed: .empty, seedPayload: { _ in nil }, fetch: { url, policy in try await transport.get(url, policy: policy) })
    }

    @Test func bundledStoryReconcilesAndWorksColdOffline() async throws {
        let entry = try #require(StorySeed.catalog.stories.first(where: { $0.id == "this-stadium" }))
        let bytes = try #require(StorySeed.payload(entry))
        let story = try StoryContract.decodeStory(bytes, entry: entry)
        #expect(story.choices.map(\.value) == ["356", "340"])
        #expect(story.correctChoiceID == "ball-b")
        #expect(story.bars.map(\.value) == [6, 1])
        #expect(story.barMaximum == 30)
        #expect(story.passport?.items.count == 30)
        #expect(story.passport?.items.filter { $0.result == "yes" }.map(\.name) == ["Yankee Stadium"])
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = StoryCatalogStore(cache: StoryContentCache(directory: directory), fetch: { _, _ in throw URLError(.notConnectedToInternet) })
        await store.refresh(); await store.load(entry)
        #expect(store.refreshFailed)
        #expect(store.stories[entry.id]?.title == entry.title)
    }

    @Test func sameBinaryDiscoversTwoStoriesAndRollsBack() async throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = StoryContentCache(directory: directory), transport = StoryFixtureTransport()
        let (a, aData) = try fixture(), (b, bData) = try fixture(id: "new-story", title: "Another story")
        await transport.set("/api/data/stories/catalog-v1.json", try catalog([a]))
        await transport.set("/api/data/\(a.payloadPath)", aData)
        let model = store(transport, cache: cache)
        await model.refresh(); await model.load(a)
        #expect(model.stories[a.id] != nil)
        await transport.set("/api/data/stories/catalog-v1.json", try catalog([b, a], revision: "new"))
        await transport.set("/api/data/\(b.payloadPath)", bData)
        await model.refresh(force: true); await model.load(b)
        #expect(model.catalog.stories.count == 2 && model.stories[b.id]?.title == "Another story")
        await transport.set("/api/data/stories/catalog-v1.json", try catalog([a], revision: "rollback"))
        await model.refresh(force: true)
        #expect(model.catalog.revision == "rollback" && model.catalog.stories.count == 1)
        #expect(model.stories[b.id] == nil)
        #expect(await transport.policies.contains(.reloadIgnoringLocalCacheData))
    }

    @Test func offlineRelaunchAndPartialFailureKeepLastVerifiedRevision() async throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = StoryContentCache(directory: directory), transport = StoryFixtureTransport()
        let (a, bytes) = try fixture(), (revised, _) = try fixture(title: "A corrected title")
        await transport.set("/api/data/stories/catalog-v1.json", try catalog([a]))
        await transport.set("/api/data/\(a.payloadPath)", bytes)
        let online = store(transport, cache: cache)
        await online.refresh(); await online.load(a)
        await transport.fail(URLError(.notConnectedToInternet))
        let offline = store(transport, cache: cache)
        await offline.refresh(); await offline.load(a)
        #expect(offline.refreshFailed && offline.stories[a.id]?.title == a.title)
        await transport.fail(nil)
        await transport.set("/api/data/stories/catalog-v1.json", try catalog([revised]))
        await offline.refresh(); await offline.load(revised)
        #expect(!offline.refreshFailed && offline.stories[a.id]?.title == a.title)
        #expect(offline.notes[a.id]?.contains("last verified") == true)
        #expect(await cache.story(id: a.id)?.entry.revision == a.revision)
    }

    @Test func malformedAndUnsupportedContentCannotPoisonCache() async throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = StoryContentCache(directory: directory), transport = StoryFixtureTransport()
        let (a, bytes) = try fixture()
        await transport.set("/api/data/stories/catalog-v1.json", try catalog([a]))
        await transport.set("/api/data/\(a.payloadPath)", bytes)
        let model = store(transport, cache: cache)
        await model.refresh(); await model.load(a)
        for invalid in [Data("{".utf8), Data(#"{"schemaVersion":2,"revision":"bad","publishedAt":"2026-10-08T11:00:00Z","stories":[]}"#.utf8), Data(repeating: 32, count: StoryContract.catalogLimit + 1)] {
            await transport.set("/api/data/stories/catalog-v1.json", invalid)
            await model.refresh(force: true)
            #expect(model.catalog.stories.count == 1 && model.refreshFailed)
        }
        await transport.set("/api/data/\(a.payloadPath)", Data("{}".utf8))
        await model.load(a, force: true)
        #expect(model.stories[a.id]?.title == a.title)
        #expect(await cache.story(id: a.id)?.entry.revision == a.revision)
        let unsupported = StoryEntry(id: "future", revision: String(repeating: "a", count: 64), title: "Future", summary: "Summary",
                                     fallback: "Read this summary", publishedAt: a.publishedAt, teamIDs: [], renderer: "future-renderer", rendererVersion: 2, minimumRendererVersion: 2)
        await transport.set("/api/data/stories/catalog-v1.json", try catalog([unsupported, a]))
        await model.refresh(); await model.load(unsupported)
        #expect(model.catalog.stories.count == 2 && !unsupported.isSupported && model.stories[unsupported.id] == nil)
    }

    @Test func boundsIdentityAndSafeLoading() throws {
        let (entry, bytes) = try fixture()
        var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        json["correctChoiceID"] = "missing"
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RemoteStory.self, from: JSONSerialization.data(withJSONObject: json)).validate() }
        #expect(throws: StoryContentError.self) { try StoryContract.decodeStory(Data("{}".utf8), entry: entry) }
        #expect(throws: StoryContentError.self) { try StoryContract.decodeStory(Data(repeating: 32, count: StoryContract.payloadLimit + 1), entry: entry) }
        #expect(!StoryContract.slug("../escape") && !StoryContract.slug("story\n"))
        #expect(StoryContract.sourceURL("javascript:alert(1)") == nil)
        #expect(StoryContract.sourceURL("https://user:pass@mlb.com/") == nil)
        #expect(StoryContentOrigin.approved(URL(string: "https://api.autumnlane.io/api/data")!))
        #expect(StoryContentOrigin.approved(URL(string: "https://red-sox.netlify.app/api/data")!))
        #expect(!StoryContentOrigin.approved(URL(string: "https://api.autumnlane.io.evil.test/api/data")!))
        #expect(!StoryContentOrigin.approved(URL(string: "http://api.autumnlane.io/api/data")!))
        #expect(!StoryContentOrigin.approved(URL(string: "file:///tmp/catalog.json")!, debug: true))
    }

    @Test func cancellationIsQuietAndBothHostsUseTheSameNamespace() async throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let transport = StoryFixtureTransport(), cache = StoryContentCache(directory: directory)
        await transport.fail(URLError(.cancelled))
        for host in ["api.autumnlane.io", "red-sox.netlify.app"] {
            let model = store(transport, cache: cache, root: "https://\(host)/api/data")
            await model.refresh()
            #expect(!model.refreshFailed && !model.isRefreshing)
        }
        #expect(await transport.requests == ["https://api.autumnlane.io/api/data/stories/catalog-v1.json", "https://red-sox.netlify.app/api/data/stories/catalog-v1.json"])
    }

    @Test func boundedCacheEvictsAndRejectsCorruption() async throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = StoryContentCache(directory: directory, maximumStories: 1)
        let (a, aData) = try fixture(), (b, bData) = try fixture(id: "new-story", title: "New")
        await cache.saveStory(CachedStory(entry: a, data: aData)); await cache.saveStory(CachedStory(entry: b, data: bData))
        #expect(await cache.story(id: a.id) == nil)
        #expect(await cache.story(id: b.id) != nil)
        try Data("corrupt".utf8).write(to: directory.appending(path: "\(b.id).json"))
        #expect(await cache.story(id: b.id) == nil)
        #expect(await cache.story(id: "../../outside") == nil)
    }

    @Test func realHTTPClientReadsCatalogAndRefusesRedirects() async throws {
        let origin = try #require(ProcessInfo.processInfo.environment["HUB_HTTP_CACHE_FIXTURE_ORIGIN"])
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let normal = StoryCatalogStore(root: URL(string: origin + "/story-fixture-good")!, cache: StoryContentCache(directory: directory), seed: .empty, seedPayload: { _ in nil })
        await normal.refresh()
        #expect(!normal.refreshFailed && normal.catalog.stories.contains { $0.id == "this-stadium" })
        let blocked = StoryCatalogStore(root: URL(string: origin + "/story-fixture")!, cache: StoryContentCache(directory: directory.appending(path: "blocked")), seed: .empty, seedPayload: { _ in nil })
        await blocked.refresh()
        #expect(blocked.refreshFailed && blocked.catalog.stories.isEmpty)
        let (data, _) = try await URLSession.shared.data(from: URL(string: origin + "/story-fixture/stats")!)
        let stats = try JSONDecoder().decode([String: Int].self, from: data)
        #expect(stats["redirectHits"] == 0)
    }
}
