import Foundation

@main
struct PostseasonHistoryMinimumTests {
    static func main() {
        func stat(pa: Int? = nil, innings: String? = nil) -> PostseasonHistoryStat {
            PostseasonHistoryStat(value: 0, games: 1, plateAppearances: pa, inningsPitched: innings)
        }

        func entry(
            season: PostseasonHistoryStat? = nil,
            career: PostseasonHistoryStat? = nil
        ) -> PostseasonHistoryEntry {
            PostseasonHistoryEntry(
                playerId: 1, name: "Test player", teamId: 111, teamAbbreviation: "BOS",
                league: "AL", season: season, career: career
            )
        }

        let batter = entry(season: stat(pa: 4), career: stat(pa: 20))
        precondition(batter.meetsMinimum(3, group: .hitting, column: .season))
        precondition(!batter.meetsMinimum(5, group: .hitting, column: .season))
        precondition(batter.meetsMinimum(20, group: .hitting, column: .career), "The threshold is inclusive")
        precondition(!batter.meetsMinimum(20, group: .hitting, column: .season), "Career PA cannot qualify a season")
        precondition(entry(career: stat(pa: 21)).meetsMinimum(20, group: .hitting, column: .career), "20 has no upper bound")
        precondition(!entry(career: stat(pa: 19)).meetsMinimum(20, group: .hitting, column: .career))

        let missingSeason = entry(career: stat(pa: 100))
        precondition(missingSeason.meetsMinimum(0, group: .hitting, column: .season), "Zero preserves rows with no season stats")
        precondition(!missingSeason.meetsMinimum(3, group: .hitting, column: .season))
        precondition(!entry(season: stat(pa: 10)).meetsMinimum(3, group: .hitting, column: .career))
        precondition(!entry(career: stat()).meetsMinimum(3, group: .hitting, column: .career))

        for (innings, minimum, expected) in [
            ("2.2", 3, false), ("3.0", 3, true), ("3.1", 3, true),
            ("4.2", 5, false), ("5.0", 5, true),
            ("9.2", 10, false), ("10.0", 10, true),
            ("14.2", 15, false), ("15.0", 15, true),
            ("19.2", 20, false), ("20.0", 20, true), ("20.2", 20, true),
            ("21", 20, true), ("100.0", 20, true),
            ("0.0", 3, false), ("3.3", 3, false), ("3.10", 3, false),
            ("", 3, false), ("bad", 3, false), ("-3.0", 3, false),
            ("3.0.0", 3, false), ("3.", 3, false),
        ] {
            let pitcher = entry(career: stat(innings: innings))
            precondition(
                pitcher.meetsMinimum(minimum, group: .pitching, column: .career) == expected,
                "Incorrect qualification for \(innings) IP at minimum \(minimum)"
            )
        }
        let pitcher = entry(season: stat(innings: "2.2"), career: stat(innings: "20.0"))
        precondition(!pitcher.meetsMinimum(3, group: .pitching, column: .season))
        precondition(pitcher.meetsMinimum(20, group: .pitching, column: .career))
        precondition(!entry(career: stat(pa: 100)).meetsMinimum(3, group: .pitching, column: .career))
        precondition(!entry(career: stat(innings: "100.0")).meetsMinimum(3, group: .hitting, column: .career))
        precondition(entry().meetsMinimum(0, group: .pitching, column: .career))

        print("Playoff minimum filters passed: inclusive PA/IP thresholds, fractional innings, independent season/career samples, missing data, and no minimum")
    }
}
