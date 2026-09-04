import Foundation

enum PitcherFilter: String, CaseIterable, Identifiable, Sendable {
    case both
    case starters
    case relievers

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var reportsTitle: String {
        switch self {
        case .both: "Pitcher Reports"
        case .starters: "Starter Reports"
        case .relievers: "Reliever Reports"
        }
    }
}

enum PitcherSort: String, CaseIterable, Identifiable, Sendable {
    case impact
    case surprise
    case workload

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct PitchingFeed: Codable, Sendable {
    let generatedAt: String
    let season: Int
    let team: String
    let gamesPlayed: Int
    let seasonFraction: Double
    let method: String
    let sources: PitchingSources
    let teamSummary: PitchingTeamSummary
    let pitchers: [PitcherReport]

    var updatedText: String {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractionalFormatter.date(from: generatedAt)
            ?? ISO8601DateFormatter().date(from: generatedAt)
        guard let date else { return generatedAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct PitchingSources: Codable, Sendable {
    let actual: String
    let forecast: String
    let gamesPlayed: String
    let actualUrl: String
    let forecastUrl: String
}

struct PitchingTeamSummary: Codable, Sendable {
    let actualWar: Double
    let forecastWarToDate: Double
    let warGap: Double
    let innings: Double
    let era: Double
}

struct PitcherReport: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let `throws`: String
    let role: String
    let games: Int
    let starts: Int
    let saves: Int
    let holds: Int
    let actual: PitcherActual
    let forecast: PitcherForecast?
    let forecastToDate: PitcherForecastToDate
    let warGap: Double
    let inningsSharePct: Double

    var isStarter: Bool {
        role == "Starter" || role == "Swingman" || starts >= 5
    }

    var handedness: String {
        `throws` == "L" ? "Left-handed" : "Right-handed"
    }

    var story: String {
        if warGap >= 1.5 {
            return "A season-changing surprise: \(warGap.signed(places: 1)) fWAR beyond the forecast, with \(actual.ip) innings instead of the \(forecastToDate.ip.formatted(.number.precision(.fractionLength(1)))) expected by now."
        }
        if warGap >= 0.5 {
            return "\(warGap.signed(places: 1)) fWAR ahead of forecast while covering \(inningsSharePct.formatted(.number.precision(.fractionLength(1))))% of Boston’s innings."
        }
        if warGap >= 0.15 {
            return "Quietly ahead of plan: \(warGap.signed(places: 1)) fWAR, plus \(actual.ip) innings that helped hold the staff together."
        }
        if warGap > -0.15 {
            return "Almost exactly on the value forecast so far, accounting for \(inningsSharePct.formatted(.number.precision(.fractionLength(1))))% of Boston’s innings."
        }
        return "\(abs(warGap).formatted(.number.precision(.fractionLength(1)))) fWAR behind forecast, while still covering \(actual.ip) innings."
    }
}

struct PitcherActual: Codable, Sendable {
    let ip: String
    let ipValue: Double
    let war: Double
    let era: Double
    let fip: Double
    let kMinusBbPct: Double
}

struct PitcherForecast: Codable, Sendable {
    let ip: Double
    let war: Double
    let era: Double
    let fip: Double
    let kMinusBbPct: Double
    let teamAtFetch: String?
}

struct PitcherForecastToDate: Codable, Sendable {
    let ip: Double
    let war: Double
}

private extension Double {
    func signed(places: Int) -> String {
        let value = formatted(.number.precision(.fractionLength(places)))
        return self >= 0 ? "+\(value)" : value
    }
}
