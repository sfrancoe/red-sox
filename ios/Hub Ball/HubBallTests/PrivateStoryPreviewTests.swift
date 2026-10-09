import Foundation
import Testing
@testable import Hub_Ball

@Suite(.serialized) @MainActor
struct PrivateStoryPreviewTests {
    @Test func isolatedCandidatesRemainAvailableThroughRefreshAndOffline() async throws {
        let items = PrivateStoryPreviews.items
        #expect(items.count == 3)
        #expect(items.map(\.id) == ["preview-oct09-sixth", "preview-oct09-brewers", "preview-oct09-baker"])
        #expect(!StorySeed.catalog.stories.contains { $0.id.hasPrefix("preview-") })
        let directory = FileManager.default.temporaryDirectory.appending(path: "private-preview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try JSONEncoder().encode(StorySeed.catalog)
        let store = StoryCatalogStore(cache: StoryContentCache(directory: directory), fetch: { _, _ in bytes })
        await store.refresh(force: true)
        #expect(!store.refreshFailed && !store.catalog.stories.contains { $0.id.hasPrefix("preview-") })
        #expect(PrivateStoryPreviews.items.map(\.id) == items.map(\.id))
        let offline = StoryCatalogStore(cache: StoryContentCache(directory: directory), fetch: { _, _ in throw URLError(.notConnectedToInternet) })
        await offline.refresh(force: true)
        #expect(offline.refreshFailed && PrivateStoryPreviews.items.count == 3)
    }
    @Test func halfInningScoresAndSixthInningHoldAreExact() throws {
        let chart = try #require(PrivateStoryPreviews.items.first).story.chart
        #expect(chart.kind == "step" && chart.durationSeconds == 7)
        #expect(chart.xAxis.minimum == 0 && chart.xAxis.maximum == 9 && chart.yAxis.maximum == 10)
        #expect(chart.series[0].points.map(\.y) == [0,0,0,0,0,0,0,0,0,3,3,9,9,9,9,9,9,9,9])
        #expect(chart.series[1].points.map(\.y) == [0,0,0,0,0,0,2,2,2,2,4,4,4,4,4,4,4,4,5])
        #expect(chart.value(in: chart.series[0], at: 5.499) == 3 && chart.value(in: chart.series[0], at: 5.5) == 9)
        #expect(chart.displayedProgress(5.5) == 5.5 && chart.displayedProgress(5.999) == 5.5)
        let time = 5.5 / 9 * chart.sweepSeconds
        #expect(chart.frame(at: time + 0.3).progresses == [5.5, 5.5])
        #expect(chart.frame(at: 7).progresses == [9,9])
    }
    @Test func allFourMarginGamesUseTheSameSequentialScale() throws {
        let chart = try #require(PrivateStoryPreviews.items.first { $0.id == "preview-oct09-brewers" }).story.chart
        #expect(chart.yAxis.minimum == -3 && chart.yAxis.maximum == 3 && chart.yAxis.ticks == [-2,0,2])
        #expect(chart.sequence?.secondsPerSeries == 2 && chart.emphasis.isEmpty)
        #expect(chart.series.map { $0.points.last!.y } == [1,1,-1,2])
        #expect(chart.series.allSatisfy { $0.points.allSatisfy { abs($0.y) <= 2 } })
        #expect(chart.frame(at: 2).progresses == [9,0,nil,nil])
        #expect(chart.frame(at: 4).progresses == [9,9,0,nil])
        #expect(chart.frame(at: 6).progresses == [9,9,9,0])
        #expect(chart.frame(at: 8).progresses == [9,9,9,9])
        #expect(chart.series[0].points[17].y == chart.series[0].points[18].y)
        #expect(chart.series[2].points[17].y == chart.series[2].points[18].y)
    }
    @Test func barsKeepRegularAndPostseasonSavesSeparate() throws {
        let story = try #require(PrivateStoryPreviews.items.last).story
        #expect(story.chart.kind == "bar" && story.chart.durationSeconds == 6)
        #expect(story.chart.series[0].points.map(\.x) == [2021,2022,2023,2024,2025,2026])
        #expect(story.chart.series[0].points.map(\.y) == [0,1,0,0,3,41])
        #expect(story.chart.yAxis.minimum == 0 && story.chart.yAxis.maximum == 45)
        #expect(story.conclusion == "Then he closed all three ALDS wins.")
        #expect(story.chart.frame(at: 6).progress == 2026)
        for item in PrivateStoryPreviews.items { try item.story.validate() }
    }
}
