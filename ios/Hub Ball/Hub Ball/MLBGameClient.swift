import Foundation

nonisolated struct MLBGameDescriptor: Sendable {
    let gamePk: Int
    let gameDate: String
    let isLive: Bool
}

nonisolated struct MLBGameClient: Sendable {
    private let team: HubTeam
    private let api: APIClient
    private let backendOrigin: URL?

    init(
        team: HubTeam = .boston,
        session: URLSession = APIClient.session,
        api: APIClient? = nil,
        backendOrigin: URL? = nil
    ) {
        self.team = team
        self.api = api ?? (session === APIClient.session ? .shared : APIClient(session: session))
        self.backendOrigin = backendOrigin
    }

    @concurrent func gameDescriptors(now: Date = Date()) async throws -> [MLBGameDescriptor] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let formatter = BaseballDateFormat.day

        var components = URLComponents(url: apiURL("mlb/schedule"), resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "sportId", value: "1"),
            URLQueryItem(name: "startDate", value: formatter.string(from: start)),
            URLQueryItem(name: "endDate", value: formatter.string(from: now)),
            URLQueryItem(name: "gameTypes", value: "R,F,D,L,W")
        ]

        let payload: MLBSchedulePayload = try await api.get(.url(components.url!), cachePolicy: .useProtocolCachePolicy, snakeCase: false)
        let descriptors = (payload.dates ?? []).flatMap { $0.games ?? [] }.compactMap { game -> MLBGameDescriptor? in
            guard let gamePk = game.gamePk, let gameDate = game.gameDate else { return nil }
            let status = game.status ?? MLBStatus()
            let isLive = status.abstractGameState == "Live" || status.codedGameState == "I"
            let isFinal = status.abstractGameState == "Final" && ["F", "O"].contains(status.codedGameState ?? "")
            guard isLive || isFinal else { return nil }
            return MLBGameDescriptor(gamePk: gamePk, gameDate: gameDate, isLive: isLive)
        }
        .sorted { ($0.gameDate, $0.gamePk) < ($1.gameDate, $1.gamePk) }

        let live = descriptors.filter(\.isLive).last
        let finals = descriptors.filter { !$0.isLive }.suffix(live == nil ? 4 : 3).reversed()
        return (live.map { [$0] } ?? []) + finals
    }

    @concurrent func game(
        gamePk: Int,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> RecentGame {
        let url = apiURL("mlb/game")
            .appending(queryItems: [URLQueryItem(name: "gamePk", value: "\(gamePk)")])
        let api = self.api
        if !api.cachesGameFeeds {
            let payload: MLBGamePayload = try await api.get(.url(url), cachePolicy: cachePolicy, snakeCase: false)
            return try buildGame(from: payload)
        }
        let payload = try await api.gameFeeds.get(gamePk, force: cachePolicy == .reloadIgnoringLocalCacheData) {
            try await api.get(.url(url), cachePolicy: cachePolicy, snakeCase: false)
        }
        try Task.checkCancellation()
        return try buildGame(from: payload)
    }

    private func apiURL(_ endpoint: String) -> URL {
        if let backendOrigin {
            return backendOrigin
                .appending(path: "api")
                .appending(path: endpoint)
                .appending(queryItems: [URLQueryItem(name: "team", value: team.apiKey)])
        }
        return AppBackend.apiURL(endpoint, team: team)
    }

    private func buildGame(from payload: MLBGamePayload) throws -> RecentGame {
        let gameData = payload.gameData ?? MLBGameData()
        let liveData = payload.liveData ?? MLBLiveData()
        let linescore = liveData.linescore ?? MLBLineScore()
        let away = boxScore(side: "away", gameData: gameData, liveData: liveData)
        let home = boxScore(side: "home", gameData: gameData, liveData: liveData)
        guard away.id == team.mlbID || home.id == team.mlbID else { throw MLBGameError.notFavoriteTeam }
        let favorite = away.id == team.mlbID ? away : home
        let opponent = away.id == team.mlbID ? home : away
        let isLive = gameData.status?.abstractGameState == "Live"
        let innings = buildInnings(linescore, minimumCount: isLive ? 9 : 0)
        let narrativePlays = buildScoringPlays(liveData)
        let venue = gameData.venue?.name ?? "the ballpark"
        let fallbackSummary = isLive
            ? liveSummary(favorite: favorite, opponent: opponent, venue: venue, linescore: linescore)
            : finalSummary(favorite: favorite, opponent: opponent, venue: venue, plays: narrativePlays)
        let fallbackFacts = interestingFacts(favorite: favorite, opponent: opponent, inningsCount: innings.count, isLive: isLive)
        return RecentGame(
            generatedAt: Date().ISO8601Format(), source: "MLB Stats API",
            gamePk: payload.gamePk ?? 0, gameDate: gameData.datetime?.dateTime ?? "",
            venue: venue, gameDurationMinutes: gameData.gameInfo?.gameDurationMinutes,
            attendance: gameData.gameInfo?.attendance, inningsCount: innings.count,
            result: isLive ? "Live" : favorite.runs > opponent.runs ? "Win" : "Loss",
            gameState: isLive ? "Live" : "Final",
            liveStatus: isLive ? liveStatus(linescore) : nil,
            liveMatchup: isLive ? liveMatchup(linescore, players: gameData.players ?? [:]) : nil,
            summary: payload.narratives?[String(team.mlbID)]?.summary ?? fallbackSummary,
            facts: payload.narratives?[String(team.mlbID)]?.facts ?? fallbackFacts,
            decisions: Decisions(winner: liveData.decisions?.winner?.fullName ?? "",
                                 loser: liveData.decisions?.loser?.fullName ?? "",
                                 save: liveData.decisions?.save?.fullName ?? ""),
            away: away, home: home, innings: innings, scoringPlays: narrativePlays.map(\.display),
            officialRecap: payload.officialRecap,
            gamedayUrl: "https://www.mlb.com/gameday/\(payload.gamePk ?? 0)"
        )
    }

    private func liveMatchup(_ linescore: MLBLineScore, players: [String: MLBPerson]) -> LiveGameMatchup {
        let state = (linescore.inningState ?? "").lowercased()
        let outs = linescore.outs.flatMap { (0...3).contains($0) ? $0 : nil }
        let betweenInnings = ["middle", "end"].contains(state) || outs == 3
        let pitcher = linescore.defense?.pitcher
        let batter = linescore.offense?.batter
        func name(_ person: MLBPerson?, last: Bool = false) -> String? {
            let value = last ? person?.id.flatMap { players["ID\($0)"]?.lastName } : person?.fullName
            guard !betweenInnings, let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return LiveGameMatchup(
            pitcher: name(pitcher), batter: name(batter), outs: outs,
            balls: betweenInnings ? nil : linescore.balls.flatMap { (0...4).contains($0) ? $0 : nil },
            strikes: betweenInnings ? nil : linescore.strikes.flatMap { (0...3).contains($0) ? $0 : nil },
            pitcherLastName: name(pitcher, last: true), batterLastName: name(batter, last: true)
        )
    }

    private func boxScore(side: String, gameData: MLBGameData, liveData: MLBLiveData) -> TeamBoxScore {
        let teamInfo = gameData.teams?[side] ?? MLBTeam()
        let box = liveData.boxscore?.teams?[side] ?? MLBBox()
        let totals = liveData.linescore?.teams?[side] ?? MLBInningSide()
        let record = teamInfo.record?.leagueRecord
        return TeamBoxScore(
            side: side, id: teamInfo.id ?? 0, name: teamInfo.name ?? "Team",
            abbreviation: teamInfo.abbreviation ?? "",
            record: record?.wins.flatMap { win in record?.losses.map { "\(win)-\($0)" } } ?? "—",
            runs: totals.runs ?? 0, hits: totals.hits ?? 0, errors: totals.errors ?? 0,
            leftOnBase: totals.leftOnBase ?? 0, batting: battingRows(box), pitching: pitchingRows(box)
        )
    }

    private func battingRows(_ box: MLBBox) -> [Batter] {
        var seen = Set<Int>()
        let ids = ((box.battingOrder ?? []) + (box.batters ?? [])).filter { seen.insert($0).inserted }
        return ids.enumerated().map { order, id in
            let player = box.players?["ID\(id)"] ?? MLBBoxPlayer()
            let stats = player.stats?.batting ?? MLBStats()
            let season = player.seasonStats?.batting
            return Batter(
                mlbId: id, name: player.person?.fullName ?? "", position: player.position?.abbreviation ?? "",
                note: stats.note ?? "", order: order, atBats: stats.atBats ?? 0,
                runs: stats.runs ?? 0, hits: stats.hits ?? 0, rbi: stats.rbi ?? 0,
                baseOnBalls: stats.baseOnBalls ?? 0, strikeOuts: stats.strikeOuts ?? 0,
                leftOnBase: stats.leftOnBase ?? 0, homeRuns: stats.homeRuns ?? 0,
                stolenBases: stats.stolenBases, average: season?.avg, seasonHomeRuns: season?.homeRuns
            )
        }
    }

    private func pitchingRows(_ box: MLBBox) -> [Pitcher] {
        (box.pitchers ?? []).enumerated().map { order, id in
            let player = box.players?["ID\(id)"] ?? MLBBoxPlayer()
            let stats = player.stats?.pitching ?? MLBStats()
            return Pitcher(
                mlbId: id, name: player.person?.fullName ?? "", position: player.position?.abbreviation ?? "",
                note: stats.note ?? "", order: order, inningsPitched: stats.inningsPitched ?? "0.0",
                hits: stats.hits ?? 0, runs: stats.runs ?? 0, earnedRuns: stats.earnedRuns ?? 0,
                baseOnBalls: stats.baseOnBalls ?? 0, strikeOuts: stats.strikeOuts ?? 0,
                homeRuns: stats.homeRuns ?? 0, numberOfPitches: stats.numberOfPitches ?? 0
            )
        }
    }

    private func buildInnings(_ linescore: MLBLineScore, minimumCount: Int) -> [Inning] {
        var innings: [Int: Inning] = [:]
        for inning in linescore.innings ?? [] {
            guard let number = inning.num, number > 0 else { continue }
            innings[number] = Inning(num: number, ordinalNum: inning.ordinalNum ?? ordinal(number),
                                     home: inningSide(inning.home), away: inningSide(inning.away))
        }
        let count = max(minimumCount, innings.keys.max() ?? 0)
        guard count > 0 else { return [] }
        return (1...count).map { number in
            innings[number] ?? Inning(num: number, ordinalNum: ordinal(number), home: inningSide(nil), away: inningSide(nil))
        }
    }

    private func inningSide(_ side: MLBInningSide?) -> InningSide {
        InningSide(runs: side?.runs, hits: side?.hits ?? 0, errors: side?.errors ?? 0, leftOnBase: side?.leftOnBase ?? 0)
    }

    private func buildScoringPlays(_ liveData: MLBLiveData) -> [NarrativePlay] {
        let plays = liveData.plays?.allPlays ?? []
        return (liveData.plays?.scoringPlays ?? []).compactMap { index in
            guard plays.indices.contains(index) else { return nil }
            let play = plays[index]
            return NarrativePlay(inningNum: play.about?.inning ?? 0, half: play.about?.halfInning ?? "",
                                 batter: play.matchup?.batter?.fullName ?? "", event: play.result?.event ?? "",
                                 rbi: play.result?.rbi ?? 0,
                                 description: play.result?.description ?? play.result?.event ?? "Scoring play",
                                 awayScore: play.result?.awayScore ?? 0, homeScore: play.result?.homeScore ?? 0)
        }
    }

    private func liveSummary(
        favorite: TeamBoxScore,
        opponent: TeamBoxScore,
        venue: String,
        linescore: MLBLineScore
    ) -> String {
        let situation = liveSituation(linescore)
        if favorite.runs > opponent.runs {
            return "The \(team.shortName) lead the \(clubName(opponent)), \(favorite.runs)–\(opponent.runs), \(situation) at \(venue)."
        }
        if favorite.runs < opponent.runs {
            return "The \(team.shortName) trail the \(clubName(opponent)), \(opponent.runs)–\(favorite.runs), \(situation) at \(venue)."
        }
        return "The \(team.shortName) and \(clubName(opponent)) are tied, \(favorite.runs)–\(opponent.runs), \(situation) at \(venue)."
    }

    private func liveSituation(_ linescore: MLBLineScore) -> String {
        let ordinalInning = linescore.currentInningOrdinal
            ?? ordinal(linescore.currentInning ?? 1)
        let half = (linescore.inningHalf ?? "").lowercased()
        let state = (linescore.inningState ?? "").lowercased()
        if state == "middle" { return "after the top of the \(ordinalInning)" }
        if state == "end" { return "after the \(ordinalInning)" }
        return "in the \(half) of the \(ordinalInning)"
    }

    private func liveStatus(_ linescore: MLBLineScore) -> String {
        let ordinalInning = linescore.currentInningOrdinal
            ?? ordinal(linescore.currentInning ?? 1)
        let half = (linescore.inningHalf ?? "").lowercased()
        let state = (linescore.inningState ?? "").lowercased()

        if state == "middle" { return "Middle of the \(ordinalInning)" }
        if state == "end" { return "End of the \(ordinalInning)" }
        if half == "top" { return "Top of the \(ordinalInning)" }
        if half == "bottom" { return "Bottom of the \(ordinalInning)" }
        return "In progress"
    }

    private func finalSummary(
        favorite: TeamBoxScore,
        opponent: TeamBoxScore,
        venue: String,
        plays: [NarrativePlay]
    ) -> String {
        let annotated = annotate(plays, favoriteAway: favorite.side == "away")
        if favorite.runs > opponent.runs {
            let largestDeficit = annotated.map { $0.afterOpponent - $0.afterFavorite }.max() ?? 0
            let deficitIndex = annotated.lastIndex {
                $0.afterOpponent - $0.afterFavorite == largestDeficit
            } ?? 0
            let goAhead = annotated.filter {
                $0.afterFavorite > $0.beforeFavorite
                    && $0.beforeFavorite <= $0.beforeOpponent
                    && $0.afterFavorite > $0.afterOpponent
            }
            let winningPlay = goAhead.last
            let walkoff = winningPlay != nil && favorite.side == "home"
                && (winningPlay?.play.inningNum ?? 0) >= 9
                && winningPlay?.play.id == annotated.last?.play.id
            var sentences: [String] = []
            if walkoff, let winningPlay {
                sentences.append(
                    "\(winningPlay.play.batter) delivered a walk-off \(winningPlay.play.event.lowercased()) "
                        + "in the \(ordinal(winningPlay.play.inningNum)) inning as the \(team.shortName) rallied past "
                        + "the \(clubName(opponent)), \(favorite.runs)–\(opponent.runs), at \(venue)."
                )
            } else if largestDeficit >= 2 {
                sentences.append(
                    "The \(team.shortName) erased a \(largestDeficit)-run deficit to beat the \(clubName(opponent)), "
                        + "\(favorite.runs)–\(opponent.runs), at \(venue)."
                )
            } else if opponent.runs == 0 {
                sentences.append("The \(team.shortName) shut out the \(clubName(opponent)), \(favorite.runs)–\(opponent.runs), at \(venue).")
            } else {
                sentences.append("The \(team.shortName) beat the \(clubName(opponent)), \(favorite.runs)–\(opponent.runs), at \(venue).")
            }
            if largestDeficit >= 2, annotated.indices.contains(deficitIndex) {
                let lowPoint = annotated[deficitIndex]
                if let rally = annotated.dropFirst(deficitIndex + 1).first(where: {
                    $0.afterFavorite > $0.beforeFavorite
                }) {
                    let remaining = rally.afterOpponent - rally.afterFavorite
                    let effect = remaining == 0 ? "tied the game"
                        : remaining < 0 ? "put \(team.cityName) ahead"
                        : "cut the deficit to \(remaining == 1 ? "one" : "\(remaining)")"
                    sentences.append(
                        "\(team.cityName) trailed \(lowPoint.afterOpponent)–\(lowPoint.afterFavorite) before "
                            + "\(scoringAction(rally.play)) in the \(ordinal(rally.play.inningNum)) \(effect)."
                    )
                }
            }
            if walkoff, let winningPlay,
               let tying = annotated.dropFirst(deficitIndex + 1).first(where: {
                   $0.afterFavorite > $0.beforeFavorite && $0.beforeFavorite < $0.beforeOpponent
                       && $0.afterFavorite == $0.afterOpponent
               }), tying.play.id != winningPlay.play.id {
                let timing = winningPlay.play.inningNum - tying.play.inningNum == 1 ? "one inning later" : "later"
                sentences.append(
                    "\(scoringAction(tying.play)) tied it in the \(ordinal(tying.play.inningNum)), and "
                        + "\(winningPlay.play.batter) completed the comeback \(timing)."
                )
            } else if largestDeficit < 2, let winningPlay {
                sentences.append(
                    "\(scoringAction(winningPlay.play)) in the \(ordinal(winningPlay.play.inningNum)) "
                        + "put \(team.cityName) ahead for good."
                )
            }
            return sentences.joined(separator: " ")
        }

        let largestLead = annotated.map { $0.afterFavorite - $0.afterOpponent }.max() ?? 0
        let opponentGoAhead = annotated.last(where: {
            $0.afterOpponent > $0.afterFavorite
                && $0.beforeOpponent <= $0.beforeFavorite
                && $0.afterOpponent > $0.beforeOpponent
        })
        let favoriteHighlight = annotated
            .filter { $0.afterFavorite > $0.beforeFavorite }
            .max {
                let leftRuns = $0.afterFavorite - $0.beforeFavorite
                let rightRuns = $1.afterFavorite - $1.beforeFavorite
                return (leftRuns, $0.play.inningNum) < (rightRuns, $1.play.inningNum)
            }
        var sentences: [String] = []
        if favorite.runs == 0 {
            return "The \(team.shortName) were shut out by the \(clubName(opponent)), \(opponent.runs)–\(favorite.runs), at \(venue)."
        }
        if largestLead >= 2 {
            sentences.append(
                "The \(team.shortName) couldn’t hold a \(largestLead)-run lead and fell to the \(clubName(opponent)), "
                    + "\(opponent.runs)–\(favorite.runs), at \(venue)."
            )
        } else {
            sentences.append(
                "The \(team.shortName) fell to the \(clubName(opponent)), \(opponent.runs)–\(favorite.runs), at \(venue)."
            )
        }
        if let opponentGoAhead {
            sentences.append(
                "\(scoringAction(opponentGoAhead.play)) in the \(ordinal(opponentGoAhead.play.inningNum)) "
                    + "put the \(clubName(opponent)) ahead for good."
            )
        }
        if let favoriteHighlight,
           favoriteHighlight.play.id != opponentGoAhead?.play.id {
            sentences.append(
                "\(team.cityName)’s biggest swing came on \(scoringAction(favoriteHighlight.play)) "
                    + "in the \(ordinal(favoriteHighlight.play.inningNum))."
            )
        }
        return sentences.joined(separator: " ")
    }

    private func interestingFacts(
        favorite: TeamBoxScore,
        opponent: TeamBoxScore,
        inningsCount: Int,
        isLive: Bool
    ) -> [String] {
        var facts: [String] = []
        if !isLive && inningsCount > 9 {
            facts.append("The game went \(inningsCount) innings.")
        }
        if let top = favorite.batting.max(by: { $0.hits < $1.hits }), top.hits >= 2 {
            facts.append("\(top.name) has \(top.hits) of the \(team.shortName)’ \(favorite.hits) hits\(isLive ? " so far" : "").")
        }
        let homers = favorite.batting.filter { $0.homeRuns > 0 }
        if !homers.isEmpty {
            let total = homers.reduce(0) { $0 + $1.homeRuns }
            let names = homers.map { "\($0.name) (\($0.seasonHomeRuns ?? 0))" }.joined(separator: ", ")
            facts.append("The \(team.shortName) have hit \(total) home run\(total == 1 ? "" : "s"): \(names).")
        }
        if !isLive, let starter = favorite.pitching.first {
            facts.append(
                "\(starter.name) worked \(starter.inningsPitched) innings, allowed "
                    + "\(starter.earnedRuns) earned run\(starter.earnedRuns == 1 ? "" : "s"), "
                    + "and struck out \(starter.strikeOuts)."
            )
        }
        return Array(facts.prefix(5))
    }

    private func annotate(_ plays: [NarrativePlay], favoriteAway: Bool) -> [AnnotatedPlay] {
        var away = 0
        var home = 0
        return plays.map { play in
            let beforeFavorite = favoriteAway ? away : home
            let beforeOpponent = favoriteAway ? home : away
            away = play.awayScore
            home = play.homeScore
            return AnnotatedPlay(
                play: play,
                beforeFavorite: beforeFavorite,
                beforeOpponent: beforeOpponent,
                afterFavorite: favoriteAway ? away : home,
                afterOpponent: favoriteAway ? home : away
            )
        }
    }

    private func scoringAction(_ play: NarrativePlay) -> String {
        let possessive = play.batter.hasSuffix("s") ? "\(play.batter)’" : "\(play.batter)’s"
        var event = play.event.lowercased()
        if event == "sac fly" { event = "sacrifice fly" }
        let runs = [2: "two-run ", 3: "three-run ", 4: "grand slam "][play.rbi] ?? ""
        if play.rbi == 4 && event == "home run" { event = "" }
        return "\(possessive) \(runs)\(event)".trimmingCharacters(in: .whitespaces)
    }

    private func clubName(_ team: TeamBoxScore) -> String {
        HubTeam.allCases.first(where: { $0.mlbID == team.id })?.shortName ?? team.name
    }

    private func ordinal(_ value: Int) -> String {
        let remainder = value % 100
        let suffix = (11...13).contains(remainder) ? "th" : [1: "st", 2: "nd", 3: "rd"][value % 10] ?? "th"
        return "\(value)\(suffix)"
    }

}

nonisolated private struct NarrativePlay: Identifiable, Sendable {
    let inningNum: Int
    let half: String
    let batter: String
    let event: String
    let rbi: Int
    let description: String
    let awayScore: Int
    let homeScore: Int

    var id: String { "\(inningNum)-\(half)-\(awayScore)-\(homeScore)-\(description)" }
    var display: ScoringPlay {
        ScoringPlay(
            inning: "\(half.capitalized) \(inningNum)",
            description: description,
            awayScore: awayScore,
            homeScore: homeScore
        )
    }
}

nonisolated private struct AnnotatedPlay: Sendable {
    let play: NarrativePlay
    let beforeFavorite: Int
    let beforeOpponent: Int
    let afterFavorite: Int
    let afterOpponent: Int
}

private enum MLBGameError: Error {
    case notFavoriteTeam
}
