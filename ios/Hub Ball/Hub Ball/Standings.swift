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
    let isFavorite: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, shortName, abbreviation, rank, wins, losses, pct
        case gamesBack, wildCardGamesBack, lastTen, streak
        case isFavorite, isRedSox
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        shortName = try values.decode(String.self, forKey: .shortName)
        abbreviation = try values.decode(String.self, forKey: .abbreviation)
        rank = try values.decode(String.self, forKey: .rank)
        wins = try values.decode(Int.self, forKey: .wins)
        losses = try values.decode(Int.self, forKey: .losses)
        pct = try values.decode(String.self, forKey: .pct)
        gamesBack = try values.decode(String.self, forKey: .gamesBack)
        wildCardGamesBack = try values.decode(String.self, forKey: .wildCardGamesBack)
        lastTen = try values.decode(String.self, forKey: .lastTen)
        streak = try values.decode(String.self, forKey: .streak)
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite)
            ?? values.decodeIfPresent(Bool.self, forKey: .isRedSox)
            ?? false
    }

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

enum StandingsLeague: String, CaseIterable, Identifiable {
    case american
    case national

    var id: Self { self }

    var shortName: String {
        switch self {
        case .american: "AL"
        case .national: "NL"
        }
    }

    var fullName: String {
        switch self {
        case .american: "American League"
        case .national: "National League"
        }
    }

    var divisionsMode: StandingsMode {
        switch self {
        case .american: .americanDivisions
        case .national: .nationalDivisions
        }
    }
}

enum StandingsMode: String, CaseIterable, Identifiable {
    case americanDivisions
    case nationalDivisions
    case wildCard

    var id: Self { self }

    var title: String {
        switch self {
        case .americanDivisions: "AL Divisions"
        case .nationalDivisions: "NL Divisions"
        case .wildCard: "Wild Card"
        }
    }

    var league: StandingsLeague? {
        switch self {
        case .americanDivisions: .american
        case .nationalDivisions: .national
        case .wildCard: nil
        }
    }
}
