import Foundation
import Testing
@testable import Hub_Ball

@Suite(.serialized) @MainActor
struct TrajectoryRefinementTests {
    private func story() throws -> TrajectoryStory {
        let entry = try #require(StorySeed.catalog.stories.first { $0.id == "whole-season-by-june" })
        guard case .trajectory(let story) = try StoryContract.decodeDocument(try #require(StorySeed.payload(entry)), entry: entry) else { throw StoryContentError.invalid }
        return story
    }
    @Test func seasonsCompleteIndependentlyAndStayVisible() throws {
        let chart = try story().chart
        #expect(chart.frame(at: 0).progresses == [0, nil, nil])
        #expect(chart.frame(at: 1).progresses == [81, nil, nil])
        #expect(chart.frame(at: 2).progresses == [162, 0, nil])
        #expect(chart.frame(at: 3).progresses == [162, 81, nil])
        #expect(chart.frame(at: 4).progresses == [162, 162, 0])
        #expect(chart.frame(at: 8).progresses == [162, 162, 162])
    }
    @Test func pauseJoinsEqualValuesAndPulsesExactlyTwice() throws {
        let chart = try story().chart
        let start = 4 + 2 * 78.0 / 162
        #expect(chart.frame(at: start - 0.01).beat == nil)
        for offset in [0.01, 0.7, 1.5, 1.99] {
            let frame = chart.frame(at: start + offset)
            #expect(frame.progresses == [162, 162, 78])
            #expect(frame.beat?.comparison?.targetSeriesID == "season-2024")
        }
        #expect(chart.frame(at: start + 0.15).comparisonDraw > 0.49 && chart.frame(at: start + 0.15).comparisonDraw < 0.51)
        for offset in [0.7, 1.5] { #expect(abs(chart.frame(at: start + offset).comparisonStrength - 0.65) < 0.001) }
        for offset in [0.3, 1.1, 1.9] { #expect(abs(chart.frame(at: start + offset).comparisonStrength - 1) < 0.001) }
        #expect(chart.frame(at: start + 2.01).progress > 78)
        #expect(chart.frame(at: 8).comparisonStrength == 1 && chart.frame(at: 8).comparisonDraw == 1)
    }
    @Test func legacyRemoteChartsKeepTheirOriginalPlayback() throws {
        let story = try story()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(story)) as? [String: Any])
        var chart = try #require(json["chart"] as? [String: Any]); chart.removeValue(forKey: "sequence")
        var beats = try #require(chart["emphasis"] as? [[String: Any]]); beats[0].removeValue(forKey: "comparison"); beats[0]["holdSeconds"] = 0.9
        chart["emphasis"] = beats; json["chart"] = chart
        let legacy = try JSONDecoder().decode(TrajectoryStory.self, from: JSONSerialization.data(withJSONObject: json))
        try legacy.validate()
        #expect(legacy.chart.minimumCapability == 2)
        #expect(legacy.chart.frame(at: 2).progresses.allSatisfy { $0 == legacy.chart.x(at: 2) })
        #expect(legacy.chart.frame(at: 8).progresses == [162, 162, 162])
    }
    @Test func launchOfferWaitsForOnboardingAndNeverRepeatsWithinSession() throws {
        let entry = try #require(StorySeed.catalog.stories.first { $0.id == "whole-season-by-june" })
        var launch = FeaturedStoryLaunch()
        #expect(launch.offer(completedOnboarding: false, busy: false, entry: entry) == nil && !launch.consumed)
        #expect(launch.offer(completedOnboarding: true, busy: true, entry: entry) == nil && !launch.consumed)
        #expect(launch.offer(completedOnboarding: true, busy: false, entry: entry) == entry && launch.consumed)
        #expect(launch.offer(completedOnboarding: true, busy: false, entry: entry) == nil)
        var coldLaunch = FeaturedStoryLaunch()
        #expect(coldLaunch.offer(completedOnboarding: true, busy: false, entry: entry) == entry)
    }
}
