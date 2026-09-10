import Foundation

enum HubTeam: String, CaseIterable, Identifiable, Sendable {
    case boston
    case newYork = "new-york"
    case newYorkMets = "new-york-mets"
    case tampaBay = "tampa-bay"

    nonisolated var id: String { rawValue }

    nonisolated var mlbID: Int {
        switch self {
        case .boston: 111
        case .newYork: 147
        case .newYorkMets: 121
        case .tampaBay: 139
        }
    }

    nonisolated var fullName: String {
        switch self {
        case .boston: "Boston Red Sox"
        case .newYork: "New York Yankees"
        case .newYorkMets: "New York Mets"
        case .tampaBay: "Tampa Bay Rays"
        }
    }

    nonisolated var cityName: String {
        switch self {
        case .boston: "Boston"
        case .newYork: "New York"
        case .newYorkMets: "New York"
        case .tampaBay: "Tampa Bay"
        }
    }

    nonisolated var cityAbbreviation: String {
        switch self {
        case .boston: "BOS"
        case .newYork: "NY"
        case .newYorkMets: "NY"
        case .tampaBay: "TB"
        }
    }

    nonisolated var shortName: String {
        switch self {
        case .boston: "Red Sox"
        case .newYork: "Yankees"
        case .newYorkMets: "Mets"
        case .tampaBay: "Rays"
        }
    }

    nonisolated var pickerTitle: String {
        switch self {
        case .boston: "Boston Red Sox"
        case .newYork: "New York Yankees"
        case .newYorkMets: "New York Mets"
        case .tampaBay: "Tampa Bay Rays"
        }
    }

    nonisolated var apiKey: String {
        switch self {
        case .boston: "redsox"
        case .newYork: "yankees"
        case .newYorkMets: "mets"
        case .tampaBay: "rays"
        }
    }

    nonisolated var dataPathComponent: String? {
        switch self {
        case .boston: nil
        case .newYork: "yankees"
        case .newYorkMets: "mets"
        case .tampaBay: "rays"
        }
    }

    var newsSources: [NewsSource] {
        switch self {
        case .boston: [.globe, .herald, .athletic, .massLive]
        case .newYork: [.dailyNews, .nyPost, .athletic, .nyTimes]
        case .newYorkMets: [.dailyNews, .nyPost, .athletic, .nyTimes]
        case .tampaBay: [.tampaBayTimes, .athletic]
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
