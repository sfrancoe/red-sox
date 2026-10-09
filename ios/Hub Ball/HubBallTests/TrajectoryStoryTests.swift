import Foundation
import Testing
@testable import Hub_Ball

@Suite(.serialized) @MainActor
struct TrajectoryStoryTests {
    private func fixture() throws -> (StoryEntry, Data, TrajectoryStory) {
        let entry = try #require(StorySeed.catalog.stories.first { $0.renderer == "chart-trajectory" })
        let data = try #require(StorySeed.payload(entry))
        guard case .trajectory(let story) = try StoryContract.decodeDocument(data, entry: entry) else { throw StoryContentError.invalid }
        return (entry, data, story)
    }
    @Test func verifiedCumulativeResultsAndFairAxes() throws {
        let (_, _, story) = try fixture(), chart = story.chart
        #expect(chart.kind == "step" && chart.durationSeconds == 8)
        #expect(chart.xAxis.minimum == 0 && chart.xAxis.maximum == 162)
        #expect(chart.yAxis.minimum == 0 && chart.yAxis.maximum == 90)
        #expect(chart.series.map { $0.points.last!.y } == [41, 60, 84])
        #expect(chart.series.allSatisfy { $0.points.count == 163 && $0.points[0].y == 0 })
        for row in chart.series {
            for i in 1..<row.points.count {
                #expect(row.points[i].x == Double(i))
                #expect([0.0, 1.0].contains(row.points[i].y - row.points[i - 1].y))
            }
        }
        let current = chart.series[2]
        #expect(current.points[77].y == 40 && current.points[78].y == 41)
        #expect(current.points[79].y == 41 && current.points[80].y == 42)
        #expect(current.points[116].y == 60 && current.points[117].y == 61)
        let holdStart = 4 + 78.0 / 162 * 2
        #expect(chart.frame(at: holdStart + 0.01).progress == 78 && chart.frame(at: holdStart + 1.99).progress == 78)
        #expect(chart.frame(at: 8).progress == 162)
        #expect(chart.value(in: current, at: 77.99) == 40)
    }
    @Test func rendererCapabilityAndOld118Fallback() throws {
        let (entry, _, _) = try fixture()
        #expect(entry.isSupported && entry.isSupported(by: 3))
        #expect(!entry.isSupported(by: 1) && entry.minimumRendererVersion == 3)
        #expect(!entry.fallback.isEmpty && entry.fallback.contains("84"))
        #expect(entry.actionLabel == "WATCH THE CHART")
        let previous = try #require(StorySeed.catalog.stories.first { $0.renderer == "guess-reveal" })
        #expect(previous.isSupported(by: 1))
    }
    @Test func playbackPauseForegroundReplayAndReducedMotion() throws {
        let (_, _, story) = try fixture(); let duration = story.chart.durationSeconds
        var playback = TrajectoryPlayback()
        playback.start(now: 10, reducedMotion: false, duration: duration)
        #expect(playback.time(now: 12, duration: duration) == 2)
        playback.pause(now: 12, duration: duration)
        #expect(playback.time(now: 100, duration: duration) == 2)
        playback.resume(now: 100, duration: duration)
        #expect(playback.time(now: 102, duration: duration) == 4)
        playback.start(now: 105, reducedMotion: false, duration: duration)
        #expect(playback.time(now: 105, duration: duration) == 0)
        playback.start(now: 110, reducedMotion: true, duration: duration)
        #expect(playback.time(now: 110, duration: duration) == duration)
    }
    @Test func malformedChartRejectedBeforeCacheAndAllKindsSupported() throws {
        let (entry, data, _) = try fixture()
        let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        func validate(_ json: [String: Any]) throws {
            let bytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            let updated = StoryEntry(id: entry.id, revision: StoryContract.hash(bytes), title: entry.title, summary: entry.summary, fallback: entry.fallback, publishedAt: entry.publishedAt, teamIDs: entry.teamIDs, renderer: entry.renderer, rendererVersion: 1, minimumRendererVersion: 3)
            _ = try StoryContract.decodeDocument(bytes, entry: updated)
        }
        for field in ["durationSeconds", "kind", "series", "xAxis", "emphasis"] {
            var bad = original; var chart = try #require(bad["chart"] as? [String: Any])
            switch field {
            case "durationSeconds": chart[field] = 100
            case "kind": chart[field] = "javascript"
            case "series": chart[field] = []
            case "xAxis": chart[field] = ["label": "Games", "minimum": 162, "maximum": 0, "ticks": [0, 162]]
            default: chart[field] = [["id": "bad", "x": 400, "y": 41, "holdSeconds": 0.9, "title": "Bad", "detail": "Outside axis"]]
            }
            bad["chart"] = chart
            #expect(throws: (any Error).self) { try validate(bad) }
        }
        for kind in ["line", "step", "bar"] {
            var valid = original; var chart = try #require(valid["chart"] as? [String: Any]); chart["kind"] = kind
            if kind == "bar" {
                var beats = try #require(chart["emphasis"] as? [[String: Any]])
                for i in beats.indices { beats[i].removeValue(forKey: "comparison") }; chart["emphasis"] = beats
                var rows = try #require(chart["series"] as? [[String: Any]])
                for i in rows.indices { rows[i]["points"] = [["x": 0, "y": 0], ["x": 162, "y": 40]] }
                chart["series"] = rows
            }
            valid["chart"] = chart; try validate(valid)
        }
    }
    @Test func realHTTPDiscoveryWithoutSeedThenOfflineCache() async throws {
        let origin = try #require(ProcessInfo.processInfo.environment["HUB_HTTP_CACHE_FIXTURE_ORIGIN"])
        func control(_ mode: String) async throws { _ = try await URLSession.shared.data(from: URL(string: origin + "/trajectory-fixture-control?mode=" + mode)!) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "trajectory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = StoryContentCache(directory: directory)
        let store = StoryCatalogStore(root: URL(string: origin + "/trajectory-fixture")!, cache: cache, seed: .empty, seedPayload: { _ in nil })
        try await control("reset"); await store.refresh()
        #expect(store.catalog.stories.allSatisfy { $0.renderer != "chart-trajectory" })
        try await control("next"); await store.refresh(force: true)
        let entry = try #require(store.catalog.stories.first { $0.renderer == "chart-trajectory" })
        await store.load(entry)
        #expect(store.notes[entry.id] == nil)
        guard case .trajectory(let story) = store.stories[entry.id] else { Issue.record("Remote chart not loaded"); return }
        #expect(story.chart.series[2].points.last?.y == 84)
        #expect(await cache.story(id: entry.id)?.entry.revision == entry.revision)
        try await control("offline")
        let offline = StoryCatalogStore(root: URL(string: origin + "/trajectory-fixture")!, cache: cache, seed: .empty, seedPayload: { _ in nil })
        await offline.refresh(); await offline.load(entry)
        #expect(offline.refreshFailed && offline.stories[entry.id]?.title == entry.title)
        try await control("next")
    }
    @Test func chartBundledForFreshOfflineInstall() async throws {
        let (entry, _, _) = try fixture()
        let directory = FileManager.default.temporaryDirectory.appending(path: "trajectory-cold-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StoryCatalogStore(cache: StoryContentCache(directory: directory), fetch: { _, _ in throw URLError(.notConnectedToInternet) })
        await store.refresh(); await store.load(entry)
        #expect(store.stories[entry.id]?.title == entry.title)
    }
}
