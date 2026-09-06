import Foundation

enum HubTeam: String, CaseIterable, Identifiable, Sendable {
    case boston
    case newYork = "new-york"
    case newYorkMets = "new-york-mets"

    nonisolated var id: String { rawValue }

    nonisolated var mlbID: Int {
        switch self {
        case .boston: 111
        case .newYork: 147
        case .newYorkMets: 121
        }
    }

    nonisolated var fullName: String {
        switch self {
        case .boston: "Boston Red Sox"
        case .newYork: "New York Yankees"
        case .newYorkMets: "New York Mets"
        }
    }

    nonisolated var cityName: String {
        switch self {
        case .boston: "Boston"
        case .newYork: "New York"
        case .newYorkMets: "New York"
        }
    }

    nonisolated var cityAbbreviation: String {
        switch self {
        case .boston: "BOS"
        case .newYork: "NY"
        case .newYorkMets: "NY"
        }
    }

    nonisolated var shortName: String {
        switch self {
        case .boston: "Red Sox"
        case .newYork: "Yankees"
        case .newYorkMets: "Mets"
        }
    }

    nonisolated var pickerTitle: String {
        switch self {
        case .boston: "Boston Red Sox"
        case .newYork: "New York Yankees"
        case .newYorkMets: "New York Mets"
        }
    }

    nonisolated var apiKey: String {
        switch self {
        case .boston: "redsox"
        case .newYork: "yankees"
        case .newYorkMets: "mets"
        }
    }

    nonisolated var dataPathComponent: String? {
        switch self {
        case .boston: nil
        case .newYork: "yankees"
        case .newYorkMets: "mets"
        }
    }

    var newsSources: [NewsSource] {
        switch self {
        case .boston: [.globe, .herald, .athletic, .massLive]
        case .newYork: [.nyTimes, .nyPost, .dailyNews, .athletic]
        case .newYorkMets: [.nyTimes, .nyPost, .dailyNews, .athletic]
        }
    }

    var supportsHome: Bool { true }
    var supportsPlayers: Bool { self == .boston }
    var hasPublishedStories: Bool { self == .boston }
}

enum HubPreferences {
    static let selectedTeamKey = "hubSelectedTeam"
    static let completedTeamOnboardingKey = "hubCompletedTeamOnboarding"
}
