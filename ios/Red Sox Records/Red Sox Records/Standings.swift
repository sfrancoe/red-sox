import Foundation

struct StandingsFeed: Decodable {
    let generatedAt: String
    let source: String
    let season: Int
    let league: String
    let divisions: [StandingsDivision]
    let wildCard: [StandingsTeam]

    var updatedText: String {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractionalFormatter.date(from: generatedAt)
            ?? ISO8601DateFormatter().date(from: generatedAt)
        guard let date else { return generatedAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct StandingsDivision: Decodable, Identifiable {
    let id: Int
    let name: String
    let teams: [StandingsTeam]
}

struct StandingsTeam: Decodable, Identifiable {
    let id: Int
    let name: String
    let shortName: String
    let abbreviation: String
    let rank: String
    let wins: Int
    let losses: Int
    let pct: String
    let gamesBack: String
    let wildCardGamesBack: String
    let lastTen: String
    let streak: String
    let isRedSox: Bool

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
        return citiesByTeamID[id] ?? shortName
    }
}

enum StandingsMode: String, CaseIterable, Identifiable {
    case divisions
    case wildCard

    var id: Self { self }

    var title: String {
        switch self {
        case .divisions: "AL Divisions"
        case .wildCard: "Wild Card"
        }
    }
}
