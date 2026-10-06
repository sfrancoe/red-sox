import Foundation
import Testing
@testable import Hub_Ball

struct PostseasonNewsDateTests {
    @Test @MainActor static func scenarios() {
        let originalZone = NSTimeZone.default
        defer { NSTimeZone.default = originalZone }
        NSTimeZone.default = TimeZone(identifier: "Asia/Tokyo")!

        func display(_ timestamp: String) -> String {
            PostseasonNewsArticle(
                title: "Headline", description: "", url: "https://example.com/story",
                published: timestamp, source: "Publisher", teamId: 111,
                teamName: "Boston Red Sox", teamAbbreviation: "BOS", league: "AL", publishedSource: "publisher"
            ).publishedText
        }

        #expect(display("2026-09-30T11:56:00Z") == "09/30 7:56 AM")
        #expect(display("2026-09-30T16:00:00Z") == "09/30 12:00 PM")
        #expect(display("2026-09-30T11:05:00Z") == "09/30 7:05 AM")
        #expect(display("2026-09-30T11:05:00.123456+00:00") == "09/30 7:05 AM")
        #expect(display("2026-09-30T07:05:00-04:00") == "09/30 7:05 AM")
        #expect(display("2026-09-30T02:00:00Z") == "09/29 10:00 PM", "UTC midnight must roll back to the Eastern date")
        #expect(display("2026-01-02T01:09:00Z") == "01/01 8:09 PM", "Winter uses standard time")
        #expect(display("2026-03-08T06:59:00Z") == "03/08 1:59 AM")
        #expect(display("2026-03-08T07:00:00Z") == "03/08 3:00 AM", "Honor the daylight-saving transition")
        #expect(display("bad timestamp") == "—", "Never display raw malformed timestamps")
        #expect(display("2026-09-30T04:14:46+00:00") == "09/30 12:14 AM", "Use the publisher's original publication, not Bing's earlier index time")
        let oldArticle = try! JSONDecoder().decode(PostseasonNewsArticle.self, from: Data("""
            {"title":"Old cached story","description":"","url":"https://example.com",
             "published":"2026-09-29T22:55:00+00:00","source":"Publisher","teamId":111,
             "teamName":"Red Sox","teamAbbreviation":"BOS","league":"AL"}
            """.utf8))
        #expect(oldArticle.publishedText == "Time unavailable", "Old unverified feed times must not be displayed")

        let payload = PostseasonNewsPayload(
            schemaVersion: 1, season: 2026, generatedAt: "2026-09-30T11:05:00.123456+00:00",
            windowHours: 12, source: "Publisher", sourceURL: "https://example.com",
            teamCount: 12, coveredTeamCount: 1, articles: []
        )
        #expect(payload.generatedText == "09/30 7:05 AM", "The checked timestamp uses the same convention")
        print("Postseason news dates passed: Eastern Time, 12-hour AM/PM format, offsets, fractional seconds, day rollover, and DST")
    }
}
