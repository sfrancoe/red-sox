import Foundation

struct SeasonLeaders: Codable, Sendable {
    let lastGameDate: String
    let inProgress: Bool
    let record: String
    let battingLeaders: BattingLeaders
    let pitchingLeaders: PitchingLeaders
    let warLeaders: [WARLeader]

    var categories: [LeaderCategory] {
        [
            LeaderCategory(
                title: "WAR",
                leaders: warLeaders.map {
                    RankedLeader(name: $0.name, value: $0.war.formatted(.number.precision(.fractionLength(1))))
                }
            ),
            LeaderCategory(title: "WHIP", leaders: pitchingLeaders.whip.top),
            LeaderCategory(title: "HR", leaders: battingLeaders.hr.top),
            LeaderCategory(title: "AVG", leaders: battingLeaders.avg.top),
            LeaderCategory(title: "OPS", leaders: battingLeaders.ops.top),
            LeaderCategory(title: "RBI", leaders: battingLeaders.rbi.top)
        ]
    }
}

struct WARLeader: Codable, Sendable {
    let name: String
    let war: Double
}

struct BattingLeaders: Codable, Sendable {
    let hr: LeaderGroup
    let avg: LeaderGroup
    let ops: LeaderGroup
    let rbi: LeaderGroup
}

struct PitchingLeaders: Codable, Sendable {
    let whip: LeaderGroup
}

struct LeaderGroup: Codable, Sendable {
    let top: [RankedLeader]
}

struct RankedLeader: Codable, Identifiable, Sendable {
    let name: String
    let value: String

    var id: String { "\(name)-\(value)" }

    private enum CodingKeys: String, CodingKey {
        case name
        case value
    }

    init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)

        if let stringValue = try? container.decode(String.self, forKey: .value) {
            value = stringValue
        } else if let integerValue = try? container.decode(Int.self, forKey: .value) {
            value = String(integerValue)
        } else {
            let doubleValue = try container.decode(Double.self, forKey: .value)
            value = doubleValue.formatted()
        }
    }
}

struct LeaderCategory: Identifiable, Sendable {
    let title: String
    let leaders: [RankedLeader]

    var id: String { title }
}

struct LeadersMetadata: Codable, Sendable {
    let generatedAt: String
    let source: String
    let warSource: String

    var updatedText: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: generatedAt) else {
            return generatedAt
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
