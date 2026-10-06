import Foundation
import Observation

/// One owner per selected club. Tab view lifetime never owns network state.
@MainActor @Observable
final class TeamSession {
    let team: HubTeam
    let home: HomeStore
    let recent: RecentGameStore
    let schedule: ScheduleStore
    let standings: StandingsStore
    let headlines: HeadlinesStore
    let xPosts: XPostsStore
    let players: PlayersStore
    let pitching: PitchingStore
    let leaders: SeasonLeadersStore

    init(team: HubTeam, api: APIClient = .shared) {
        self.team = team
        let schedule = ScheduleStore(team: team, api: api)
        let recent = RecentGameStore(team: team, api: api, scheduleStore: schedule)
        let standings = StandingsStore(team: team, api: api)
        self.schedule = schedule
        self.recent = recent
        self.standings = standings
        home = HomeStore(team: team, recent: recent, schedule: schedule, standings: standings)
        headlines = HeadlinesStore(team: team, api: api)
        xPosts = XPostsStore(team: team, api: api)
        players = PlayersStore(team: team, api: api)
        pitching = PitchingStore(team: team, api: api)
        leaders = SeasonLeadersStore(team: team, api: api)
    }
}

/// League-wide state survives opening and closing covers, and team changes.
@MainActor @Observable
final class AppModel {
    let postseason = PostseasonStore(season: OctoberFeature.season)
    let history = PostseasonHistoryStore(season: OctoberFeature.season)
    let news = PostseasonNewsStore(season: OctoberFeature.season)
    let game108 = Game108GraphStore()
    let homeRunChase = HomeRunChaseStore()
    // Lazy construction avoids AVAudioEngine allocation during SwiftUI redraws.
    @ObservationIgnored lazy var graphMusic = GraphMusicPlayer()
    private var playerStores: [HubTeam: PlayersStore] = [:]
    private var scorecards: [Int: PostseasonScorecardStore] = [:]

    func players(for team: HubTeam) -> PlayersStore {
        if let store = playerStores[team] { return store }
        let store = PlayersStore(team: team)
        playerStores[team] = store
        return store
    }

    func scorecard(for game: PostseasonGame) -> PostseasonScorecardStore {
        if let store = scorecards[game.gamePk] { return store }
        let store = PostseasonScorecardStore(game: game)
        scorecards[game.gamePk] = store
        return store
    }
}
