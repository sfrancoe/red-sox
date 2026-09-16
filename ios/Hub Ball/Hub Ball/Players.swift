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

enum PlayerDirectorySort: String, CaseIterable, Identifiable, Sendable {
    case name
    case number
    case position
    case batsThrows
    case age

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Player"
        case .number: "#"
        case .position: "Pos"
        case .batsThrows: "B/T"
        case .age: "Age"
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
    let mlbID: Int?
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

    func formattedShortDate(_ value: String?) -> String? {
        guard let value else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        let formats = ["yyyy-MM-dd", "MMMM d, yyyy", "MMM d, yyyy"]
        guard let date = formats.lazy.compactMap({ format -> Date? in
            parser.dateFormat = format
            return parser.date(from: value)
        }).first else {
            return value
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yy"
        return formatter.string(from: date)
    }
}

struct PlayerCareerStats: Codable, Hashable, Sendable {
    let throughSeason: Int
    let status: String
    let batting: PlayerBattingStats?
    let pitching: PlayerPitchingStats?

    var isAvailable: Bool { status == "available" }
}

/// A detailed record is intentionally separate from the lightweight roster feed.
/// The app can therefore open a directory immediately and fetch/cache the longer
/// career table only when a person is selected.
struct PlayerCareerFeed: Codable, Hashable, Sendable {
    let schemaVersion: Int?
    let playerID: Int?
    let generatedAt: String?
    let dataAsOf: String?
    let status: String?
    let coverage: [PlayerCareerCoverage]?
    let source: PlayerCareerSource?
    let batting: [PlayerBattingSeason]?
    let pitching: [PlayerPitchingSeason]?

    var battingRows: [PlayerBattingSeason] { batting ?? [] }
    var pitchingRows: [PlayerPitchingSeason] { pitching ?? [] }
    var isAvailable: Bool { status == "available" }
}

struct PlayerCareerCoverage: Codable, Hashable, Sendable {
    let league: String?
    let level: String?
    let firstSeason: Int?
    let lastSeason: Int?
    let status: String?
    let note: String?
}

struct PlayerCareerSource: Codable, Hashable, Sendable {
    let name: String?
    let url: String?
    let attribution: String?
}

/// A season can be a team stint or an explicitly-labelled combined subtotal.
/// Counts remain nullable: a blank source value is never turned into a zero.
struct PlayerBattingSeason: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let season: Int
    let team: String
    let league: String?
    let level: String?
    let rowType: String?
    let games: Int?
    let atBats: Int?
    let runs: Int?
    let hits: Int?
    let doubles: Int?
    let triples: Int?
    let homeRuns: Int?
    let runsBattedIn: Int?
    let stolenBases: Int?
    let walks: Int?
    let strikeouts: Int?
    let average: Double?
    let onBasePercentage: Double?
    let sluggingPercentage: Double?
    let ops: Double?
}

struct PlayerPitchingSeason: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let season: Int
    let team: String
    let league: String?
    let level: String?
    let rowType: String?
    let games: Int?
    let gamesStarted: Int?
    let wins: Int?
    let losses: Int?
    let saves: Int?
    let inningsOuts: Int?
    let hits: Int?
    let earnedRuns: Int?
    let homeRuns: Int?
    let walks: Int?
    let strikeouts: Int?
    let era: Double?
    let whip: Double?

    var inningsPitched: String? {
        guard let inningsOuts else { return nil }
        return "\(inningsOuts / 3).\(inningsOuts % 3)"
    }
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
