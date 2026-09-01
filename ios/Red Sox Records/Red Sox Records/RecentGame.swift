import Foundation

struct RecentGame: Codable, Sendable {
    let generatedAt: String
    let source: String
    let gamePk: Int
    let gameDate: String
    let venue: String
    let inningsCount: Int
    let result: String
    let summary: String
    let facts: [String]
    let decisions: Decisions
    let away: TeamBoxScore
    let home: TeamBoxScore
    let innings: [Inning]
    let scoringPlays: [ScoringPlay]
    let officialRecap: OfficialRecap?
    let gamedayUrl: String

    var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: gameDate) else { return gameDate }

        return date.formatted(
            .dateTime
                .month(.wide)
                .day()
                .year()
        )
    }
}

struct Decisions: Codable, Sendable {
    let winner: String
    let loser: String
    let save: String
}

struct TeamBoxScore: Codable, Sendable {
    let side: String
    let id: Int
    let name: String
    let abbreviation: String
    let record: String
    let runs: Int
    let hits: Int
    let errors: Int
    let leftOnBase: Int
    let batting: [Batter]
    let pitching: [Pitcher]

    var cityName: String {
        let citiesByTeamID = [
            108: "Los Angeles", 109: "Arizona", 110: "Baltimore", 111: "Boston",
            112: "Chicago", 113: "Cincinnati", 114: "Cleveland", 115: "Colorado",
            116: "Detroit", 117: "Houston", 118: "Kansas City", 119: "Los Angeles",
            120: "Washington", 121: "New York", 133: "Athletics", 134: "Pittsburgh",
            135: "San Diego", 136: "Seattle", 137: "San Francisco", 138: "St. Louis",
            139: "Tampa Bay", 140: "Texas", 141: "Toronto", 142: "Minnesota",
            143: "Philadelphia", 144: "Atlanta", 145: "Chicago", 146: "Miami",
            147: "New York", 158: "Milwaukee"
        ]
        return citiesByTeamID[id] ?? abbreviation
    }
}

struct Batter: Codable, Identifiable, Sendable {
    let name: String
    let position: String
    let note: String
    let order: Int
    let atBats: Int
    let runs: Int
    let hits: Int
    let rbi: Int
    let baseOnBalls: Int
    let strikeOuts: Int
    let leftOnBase: Int
    let homeRuns: Int

    var id: String { "\(order)-\(name)" }
}

struct Pitcher: Codable, Identifiable, Sendable {
    let name: String
    let position: String
    let note: String
    let order: Int
    let inningsPitched: String
    let hits: Int
    let runs: Int
    let earnedRuns: Int
    let baseOnBalls: Int
    let strikeOuts: Int
    let homeRuns: Int
    let numberOfPitches: Int

    var id: String { "\(order)-\(name)" }
}

struct Inning: Codable, Identifiable, Sendable {
    let num: Int
    let ordinalNum: String
    let home: InningSide
    let away: InningSide

    var id: Int { num }
}

struct InningSide: Codable, Sendable {
    let runs: Int?
    let hits: Int
    let errors: Int
    let leftOnBase: Int
}

struct ScoringPlay: Codable, Identifiable, Sendable {
    let inning: String
    let description: String
    let awayScore: Int
    let homeScore: Int

    var id: String { "\(inning)-\(awayScore)-\(homeScore)-\(description)" }
}

struct OfficialRecap: Codable, Sendable {
    let headline: String
    let url: String
}
