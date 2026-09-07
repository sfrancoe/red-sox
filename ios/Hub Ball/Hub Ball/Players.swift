import Foundation

enum PlayerPositionFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case pitcher
    case catcher
    case infielder
    case outfielder
    case hitter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .pitcher: "Pitchers"
        case .catcher: "Catchers"
        case .infielder: "Infielders"
        case .outfielder: "Outfielders"
        case .hitter: "DH / Utility"
        }
    }
}

struct PlayersFeed: Codable, Sendable {
    let generatedAt: String
    let rosterAsOf: String?
    let team: PlayersTeam
    let rosterType: String
    let playerCount: Int
    let activeCount: Int
    let source: PlayersSource
    let players: [RedSoxPlayer]

    var updatedText: String {
        rosterAsOf ?? generatedAt
    }
}

struct PlayersSource: Codable, Sendable {
    let name: String
    let attribution: String
    let license: String
    let wikidataUrl: String
    let rosterUrl: String
    let rosterRevision: Int?
    let statsUrl: String?
    let statsThrough: Int?
    let statsAttribution: String?
}

struct PlayersTeam: Codable, Sendable {
    let id: Int
    let name: String
}

struct RedSoxPlayer: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let wikidataId: String?
    let slug: String
    let name: String
    let fullName: String?
    let number: String?
    let position: PlayerPosition
    let rosterStatus: String
    let isActiveRoster: Bool
    let birthDate: String?
    let age: Int?
    let birthplace: String
    let height: String?
    let weight: Int?
    let bats: String?
    let `throws`: String?
    let debutDate: String?
    let debutTeam: String?
    let education: PlayerEducation
    let teams: [String]
    let sourceUrl: String?
    let wikipediaUrl: String?
    let retrosheetId: String?
    let careerStats: PlayerCareerStats?

    var positionFilter: PlayerPositionFilter {
        PlayerPositionFilter(rawValue: position.group.lowercased()) ?? .hitter
    }

    var sourceURL: URL? {
        guard let sourceUrl else { return nil }
        return URL(string: sourceUrl)
    }

    var articleURL: URL? {
        guard let wikipediaUrl else { return nil }
        return URL(string: wikipediaUrl)
    }

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    var statusKind: PlayerStatusKind {
        if rosterStatus.localizedCaseInsensitiveContains("injured") { return .injured }
        if !isActiveRoster { return .inactive }
        return .active
    }

    var biography: String {
        var details: [String] = []
        if let age { details.append("age \(age)") }
        if !birthplace.isEmpty { details.append("from \(birthplace)") }
        let role = position.name.lowercased()
        let article = role.first.map { "aeiou".contains($0) } == true ? "an" : "a"
        var sentence = "\(name) is \(article) \(role)"
        if !details.isEmpty { sentence += ", " + details.joined(separator: " and ") }
        sentence += "."

        let measurements = [height, weight.map { "\($0) pounds" }].compactMap { $0 }
        if !measurements.isEmpty {
            sentence += " Listed at " + measurements.joined(separator: " and ") + "."
        }
        return sentence
    }

    func formattedDate(_ value: String?) -> String? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        return date.formatted(.dateTime.month(.wide).day().year())
    }
}

struct PlayerCareerStats: Codable, Hashable, Sendable {
    let throughSeason: Int
    let status: String
    let batting: PlayerBattingStats?
    let pitching: PlayerPitchingStats?

    var isAvailable: Bool { status == "available" }
}

struct PlayerBattingStats: Codable, Hashable, Sendable {
    let games: Int
    let plateAppearances: Int
    let atBats: Int
    let runs: Int
    let hits: Int
    let doubles: Int
    let triples: Int
    let homeRuns: Int
    let runsBattedIn: Int
    let walks: Int
    let strikeouts: Int
    let stolenBases: Int
    let caughtStealing: Int
    let average: Double?
    let onBasePercentage: Double?
    let sluggingPercentage: Double?
    let ops: Double?
}

struct PlayerPitchingStats: Codable, Hashable, Sendable {
    let games: Int
    let gamesStarted: Int
    let wins: Int
    let losses: Int
    let saves: Int
    let inningsOuts: Int
    let hits: Int
    let runs: Int
    let earnedRuns: Int
    let homeRuns: Int
    let walks: Int
    let strikeouts: Int
    let hitBatters: Int
    let wildPitches: Int
    let balks: Int
    let completeGames: Int
    let era: Double?
    let whip: Double?

    var inningsPitched: String {
        "\(inningsOuts / 3).\(inningsOuts % 3)"
    }
}

enum PlayerStatusKind: Equatable, Sendable {
    case active
    case injured
    case inactive
}

struct PlayerPosition: Codable, Hashable, Sendable {
    let name: String
    let group: String
    let abbreviation: String
}

struct PlayerEducation: Codable, Hashable, Sendable {
    let highSchools: [PlayerSchool]
    let colleges: [PlayerSchool]

    var entries: [String] {
        let highSchoolRows = highSchools.map { school in
            let place = [school.city, school.state].compactMap { $0 }.joined(separator: ", ")
            return place.isEmpty ? school.name : "\(school.name) · \(place)"
        }
        let collegeRows = colleges.map { school in
            let place = [school.city, school.state].compactMap { $0 }.joined(separator: ", ")
            return place.isEmpty ? school.name : "\(school.name) · \(place)"
        }
        return highSchoolRows + collegeRows
    }
}

struct PlayerSchool: Codable, Hashable, Sendable {
    let name: String
    let city: String?
    let state: String?
}
