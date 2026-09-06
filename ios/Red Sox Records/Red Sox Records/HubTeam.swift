import Foundation

enum HubTeam: String, CaseIterable, Identifiable, Sendable {
    case boston
    case newYork = "new-york"

    nonisolated var id: String { rawValue }

    nonisolated var mlbID: Int {
        switch self {
        case .boston: 111
        case .newYork: 147
        }
    }

    nonisolated var fullName: String {
        switch self {
        case .boston: "Boston Red Sox"
        case .newYork: "New York Yankees"
        }
    }

    nonisolated var cityName: String {
        switch self {
        case .boston: "Boston"
        case .newYork: "New York"
        }
    }

    nonisolated var shortName: String {
        switch self {
        case .boston: "Red Sox"
        case .newYork: "Yankees"
        }
    }

    nonisolated var pickerTitle: String {
        switch self {
        case .boston: "Boston Red Sox"
        case .newYork: "New York Yankees"
        }
    }

    nonisolated var apiKey: String {
        switch self {
        case .boston: "redsox"
        case .newYork: "yankees"
        }
    }

    nonisolated var dataPathComponent: String? {
        switch self {
        case .boston: nil
        case .newYork: "yankees"
        }
    }

    var newsSources: [NewsSource] {
        switch self {
        case .boston: [.globe, .herald, .athletic, .massLive]
        case .newYork: [.nyTimes, .nyPost, .dailyNews, .athletic]
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
