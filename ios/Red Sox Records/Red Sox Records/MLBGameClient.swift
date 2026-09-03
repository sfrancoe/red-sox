import Foundation

struct MLBGameDescriptor: Sendable {
    let gamePk: Int
    let gameDate: String
    let isLive: Bool
}

struct MLBGameClient: Sendable {
    private static let redSoxID = 111
    private static let baseURL = "https://statsapi.mlb.com"

    func gameDescriptors(now: Date = Date()) async throws -> [MLBGameDescriptor] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents(string: "\(Self.baseURL)/api/v1/schedule")!
        components.queryItems = [
            URLQueryItem(name: "sportId", value: "1"),
            URLQueryItem(name: "teamId", value: "\(Self.redSoxID)"),
            URLQueryItem(name: "startDate", value: formatter.string(from: start)),
            URLQueryItem(name: "endDate", value: formatter.string(from: now)),
            URLQueryItem(name: "gameType", value: "R")
        ]

        let payload = try await json(from: components.url!)
        let dates = payload["dates"] as? [JSON] ?? []
        let games = dates.flatMap { $0["games"] as? [JSON] ?? [] }
        let descriptors = games.compactMap { game -> MLBGameDescriptor? in
            guard let gamePk = integer(game["gamePk"]),
                  let gameDate = game["gameDate"] as? String else {
                return nil
            }
            let status = game["status"] as? JSON ?? [:]
            let abstract = status["abstractGameState"] as? String ?? ""
            let code = status["codedGameState"] as? String ?? ""
            let isLive = abstract == "Live" || code == "I"
            let isFinal = abstract == "Final" && ["F", "O"].contains(code)
            guard isLive || isFinal else { return nil }
            return MLBGameDescriptor(gamePk: gamePk, gameDate: gameDate, isLive: isLive)
        }
        .sorted { ($0.gameDate, $0.gamePk) < ($1.gameDate, $1.gamePk) }

        let live = descriptors.filter(\.isLive).last
        let finals = descriptors.filter { !$0.isLive }.suffix(live == nil ? 4 : 3).reversed()
        return (live.map { [$0] } ?? []) + finals
    }

    func game(gamePk: Int) async throws -> RecentGame {
        let url = URL(string: "\(Self.baseURL)/api/v1.1/game/\(gamePk)/feed/live")!
        return try buildGame(from: await json(from: url))
    }

    private func json(from url: URL) async throws -> JSON {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let payload = try JSONSerialization.jsonObject(with: data) as? JSON else {
            throw MLBGameError.badResponse
        }
        return payload
    }

    private func buildGame(from payload: JSON) throws -> RecentGame {
        let gameData = dictionary(payload["gameData"])
        let liveData = dictionary(payload["liveData"])
        let linescore = dictionary(liveData["linescore"])
        let gameInfo = dictionary(gameData["gameInfo"])
        let away = team(side: "away", gameData: gameData, liveData: liveData)
        let home = team(side: "home", gameData: gameData, liveData: liveData)
        guard away.id == Self.redSoxID || home.id == Self.redSoxID else {
            throw MLBGameError.notRedSox
        }
        let boston = away.id == Self.redSoxID ? away : home
        let opponent = away.id == Self.redSoxID ? home : away
        let status = dictionary(gameData["status"])
        let isLive = (status["abstractGameState"] as? String) == "Live"
        let innings = buildInnings(linescore, minimumCount: isLive ? 9 : 0)
        let narrativePlays = buildScoringPlays(liveData)
        let venue = dictionary(gameData["venue"])["name"] as? String ?? "the ballpark"
        let summary = isLive
            ? liveSummary(boston: boston, opponent: opponent, venue: venue, linescore: linescore)
            : finalSummary(boston: boston, opponent: opponent, venue: venue, plays: narrativePlays)
        let facts = interestingFacts(
            boston: boston,
            opponent: opponent,
            inningsCount: innings.count,
            isLive: isLive
        )
        let decisions = dictionary(liveData["decisions"])

        return RecentGame(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            source: "MLB Stats API",
            gamePk: integer(payload["gamePk"]) ?? 0,
            gameDate: dictionary(gameData["datetime"])["dateTime"] as? String ?? "",
            venue: venue,
            gameDurationMinutes: integer(gameInfo["gameDurationMinutes"]),
            attendance: integer(gameInfo["attendance"]),
            inningsCount: innings.count,
            result: isLive ? "Live" : boston.runs > opponent.runs ? "Win" : "Loss",
            gameState: isLive ? "Live" : "Final",
            liveStatus: isLive ? liveStatus(linescore) : nil,
            summary: summary,
            facts: facts,
            decisions: Decisions(
                winner: personName(decisions["winner"]),
                loser: personName(decisions["loser"]),
                save: personName(decisions["save"])
            ),
            away: away,
            home: home,
            innings: innings,
            scoringPlays: narrativePlays.map(\.display),
            officialRecap: nil,
            gamedayUrl: "https://www.mlb.com/gameday/\(integer(payload["gamePk"]) ?? 0)"
        )
    }

    private func team(side: String, gameData: JSON, liveData: JSON) -> TeamBoxScore {
        let gameTeam = dictionary(dictionary(gameData["teams"])[side])
        let box = dictionary(dictionary(dictionary(liveData["boxscore"])["teams"])[side])
        let totals = dictionary(dictionary(dictionary(liveData["linescore"])["teams"])[side])
        let teamInfo = gameTeam
        let leagueRecord = dictionary(dictionary(gameTeam["record"])["leagueRecord"])
        let wins = integer(leagueRecord["wins"])
        let losses = integer(leagueRecord["losses"])
        let record = wins.flatMap { win in losses.map { "\(win)-\($0)" } } ?? "—"
        let teamID = integer(teamInfo["id"]) ?? 0

        return TeamBoxScore(
            side: side,
            id: teamID,
            name: teamInfo["name"] as? String ?? "Team",
            abbreviation: teamInfo["abbreviation"] as? String ?? "",
            record: record,
            runs: integer(totals["runs"]) ?? 0,
            hits: integer(totals["hits"]) ?? 0,
            errors: integer(totals["errors"]) ?? 0,
            leftOnBase: integer(totals["leftOnBase"]) ?? 0,
            batting: battingRows(box),
            pitching: pitchingRows(box)
        )
    }

    private func battingRows(_ box: JSON) -> [Batter] {
        let players = dictionary(box["players"])
        let lineup = integerArray(box["battingOrder"])
        let participants = integerArray(box["batters"])
        var playerIDs: [Int] = []
        for playerID in lineup + participants where !playerIDs.contains(playerID) {
            playerIDs.append(playerID)
        }

        return playerIDs.enumerated().compactMap { order, playerID in
            let player = dictionary(players["ID\(playerID)"])
            let stats = dictionary(dictionary(player["stats"])["batting"])
            let season = dictionary(dictionary(player["seasonStats"])["batting"])
            return Batter(
                name: personName(player["person"]),
                position: dictionary(player["position"])["abbreviation"] as? String ?? "",
                note: stats["note"] as? String ?? "",
                order: order,
                atBats: integer(stats["atBats"]) ?? 0,
                runs: integer(stats["runs"]) ?? 0,
                hits: integer(stats["hits"]) ?? 0,
                rbi: integer(stats["rbi"]) ?? 0,
                baseOnBalls: integer(stats["baseOnBalls"]) ?? 0,
                strikeOuts: integer(stats["strikeOuts"]) ?? 0,
                leftOnBase: integer(stats["leftOnBase"]) ?? 0,
                homeRuns: integer(stats["homeRuns"]) ?? 0,
                average: season["avg"] as? String,
                seasonHomeRuns: integer(season["homeRuns"])
            )
        }
    }

    private func pitchingRows(_ box: JSON) -> [Pitcher] {
        let players = dictionary(box["players"])
        return integerArray(box["pitchers"]).enumerated().compactMap { order, playerID in
            let player = dictionary(players["ID\(playerID)"])
            let stats = dictionary(dictionary(player["stats"])["pitching"])
            return Pitcher(
                name: personName(player["person"]),
                position: dictionary(player["position"])["abbreviation"] as? String ?? "",
                note: stats["note"] as? String ?? "",
                order: order,
                inningsPitched: string(stats["inningsPitched"]),
                hits: integer(stats["hits"]) ?? 0,
                runs: integer(stats["runs"]) ?? 0,
                earnedRuns: integer(stats["earnedRuns"]) ?? 0,
                baseOnBalls: integer(stats["baseOnBalls"]) ?? 0,
                strikeOuts: integer(stats["strikeOuts"]) ?? 0,
                homeRuns: integer(stats["homeRuns"]) ?? 0,
                numberOfPitches: integer(stats["numberOfPitches"]) ?? 0
            )
        }
    }

    private func buildInnings(_ linescore: JSON, minimumCount: Int) -> [Inning] {
        let reported = (linescore["innings"] as? [JSON] ?? []).compactMap { inning -> Inning? in
            guard let number = integer(inning["num"]) else { return nil }
            return Inning(
                num: number,
                ordinalNum: inning["ordinalNum"] as? String ?? ordinal(number),
                home: inningSide(dictionary(inning["home"])),
                away: inningSide(dictionary(inning["away"]))
            )
        }

        let inningsByNumber = Dictionary(uniqueKeysWithValues: reported.map { ($0.num, $0) })
        let lastInning = max(minimumCount, reported.map(\.num).max() ?? 0)
        guard lastInning > 0 else { return [] }

        return (1...lastInning).map { number in
            inningsByNumber[number] ?? Inning(
                num: number,
                ordinalNum: ordinal(number),
                home: emptyInningSide,
                away: emptyInningSide
            )
        }
    }

    private var emptyInningSide: InningSide {
        InningSide(runs: nil, hits: 0, errors: 0, leftOnBase: 0)
    }

    private func inningSide(_ side: JSON) -> InningSide {
        InningSide(
            runs: integer(side["runs"]),
            hits: integer(side["hits"]) ?? 0,
            errors: integer(side["errors"]) ?? 0,
            leftOnBase: integer(side["leftOnBase"]) ?? 0
        )
    }

    private func buildScoringPlays(_ liveData: JSON) -> [NarrativePlay] {
        let plays = dictionary(liveData["plays"])
        let allPlays = plays["allPlays"] as? [JSON] ?? []
        return integerArray(plays["scoringPlays"]).compactMap { index in
            guard allPlays.indices.contains(index) else { return nil }
            let play = allPlays[index]
            let about = dictionary(play["about"])
            let result = dictionary(play["result"])
            let matchup = dictionary(play["matchup"])
            let inning = integer(about["inning"]) ?? 0
            let half = about["halfInning"] as? String ?? ""
            return NarrativePlay(
                inningNum: inning,
                half: half,
                batter: personName(matchup["batter"]),
                event: result["event"] as? String ?? "",
                rbi: integer(result["rbi"]) ?? 0,
                description: result["description"] as? String ?? result["event"] as? String ?? "Scoring play",
                awayScore: integer(result["awayScore"]) ?? 0,
                homeScore: integer(result["homeScore"]) ?? 0
            )
        }
    }

    private func liveSummary(
        boston: TeamBoxScore,
        opponent: TeamBoxScore,
        venue: String,
        linescore: JSON
    ) -> String {
        let situation = liveSituation(linescore)
        if boston.runs > opponent.runs {
            return "The Red Sox lead the \(clubName(opponent)), \(boston.runs)–\(opponent.runs), \(situation) at \(venue)."
        }
        if boston.runs < opponent.runs {
            return "The Red Sox trail the \(clubName(opponent)), \(opponent.runs)–\(boston.runs), \(situation) at \(venue)."
        }
        return "The Red Sox and \(clubName(opponent)) are tied, \(boston.runs)–\(opponent.runs), \(situation) at \(venue)."
    }

    private func liveSituation(_ linescore: JSON) -> String {
        let ordinalInning = linescore["currentInningOrdinal"] as? String
            ?? ordinal(integer(linescore["currentInning"]) ?? 1)
        let half = (linescore["inningHalf"] as? String ?? "").lowercased()
        let state = (linescore["inningState"] as? String ?? "").lowercased()
        if state == "middle" { return "after the top of the \(ordinalInning)" }
        if state == "end" { return "after the \(ordinalInning)" }
        return "in the \(half) of the \(ordinalInning)"
    }

    private func liveStatus(_ linescore: JSON) -> String {
        let ordinalInning = linescore["currentInningOrdinal"] as? String
            ?? ordinal(integer(linescore["currentInning"]) ?? 1)
        let half = (linescore["inningHalf"] as? String ?? "").lowercased()
        let state = (linescore["inningState"] as? String ?? "").lowercased()

        if state == "middle" { return "Middle of the \(ordinalInning)" }
        if state == "end" { return "End of the \(ordinalInning)" }
        if half == "top" { return "Top of the \(ordinalInning)" }
        if half == "bottom" { return "Bottom of the \(ordinalInning)" }
        return "In progress"
    }

    private func finalSummary(
        boston: TeamBoxScore,
        opponent: TeamBoxScore,
        venue: String,
        plays: [NarrativePlay]
    ) -> String {
        let annotated = annotate(plays, bostonAway: boston.side == "away")
        if boston.runs > opponent.runs {
            let largestDeficit = annotated.map { $0.afterOpponent - $0.afterBoston }.max() ?? 0
            let deficitIndex = annotated.lastIndex {
                $0.afterOpponent - $0.afterBoston == largestDeficit
            } ?? 0
            let goAhead = annotated.filter {
                $0.afterBoston > $0.beforeBoston
                    && $0.beforeBoston <= $0.beforeOpponent
                    && $0.afterBoston > $0.afterOpponent
            }
            let winningPlay = goAhead.last
            let walkoff = winningPlay != nil && boston.side == "home"
                && (winningPlay?.play.inningNum ?? 0) >= 9
                && winningPlay?.play.id == annotated.last?.play.id
            var sentences: [String] = []
            if walkoff, let winningPlay {
                sentences.append(
                    "\(winningPlay.play.batter) delivered a walk-off \(winningPlay.play.event.lowercased()) "
                        + "in the \(ordinal(winningPlay.play.inningNum)) inning as the Red Sox rallied past "
                        + "the \(clubName(opponent)), \(boston.runs)–\(opponent.runs), at \(venue)."
                )
            } else if largestDeficit >= 2 {
                sentences.append(
                    "The Red Sox erased a \(largestDeficit)-run deficit to beat the \(clubName(opponent)), "
                        + "\(boston.runs)–\(opponent.runs), at \(venue)."
                )
            } else if opponent.runs == 0 {
                sentences.append("The Red Sox shut out the \(clubName(opponent)), \(boston.runs)–\(opponent.runs), at \(venue).")
            } else {
                sentences.append("The Red Sox beat the \(clubName(opponent)), \(boston.runs)–\(opponent.runs), at \(venue).")
            }
            if largestDeficit >= 2, annotated.indices.contains(deficitIndex) {
                let lowPoint = annotated[deficitIndex]
                if let rally = annotated.dropFirst(deficitIndex + 1).first(where: {
                    $0.afterBoston > $0.beforeBoston
                }) {
                    let remaining = rally.afterOpponent - rally.afterBoston
                    let effect = remaining == 0 ? "tied the game"
                        : remaining < 0 ? "put Boston ahead"
                        : "cut the deficit to \(remaining == 1 ? "one" : "\(remaining)")"
                    sentences.append(
                        "Boston trailed \(lowPoint.afterOpponent)–\(lowPoint.afterBoston) before "
                            + "\(scoringAction(rally.play)) in the \(ordinal(rally.play.inningNum)) \(effect)."
                    )
                }
            }
            if walkoff, let winningPlay,
               let tying = annotated.dropFirst(deficitIndex + 1).first(where: {
                   $0.afterBoston > $0.beforeBoston && $0.beforeBoston < $0.beforeOpponent
                       && $0.afterBoston == $0.afterOpponent
               }), tying.play.id != winningPlay.play.id {
                let timing = winningPlay.play.inningNum - tying.play.inningNum == 1 ? "one inning later" : "later"
                sentences.append(
                    "\(scoringAction(tying.play)) tied it in the \(ordinal(tying.play.inningNum)), and "
                        + "\(winningPlay.play.batter) completed the comeback \(timing)."
                )
            } else if largestDeficit < 2, let winningPlay {
                sentences.append(
                    "\(scoringAction(winningPlay.play)) in the \(ordinal(winningPlay.play.inningNum)) "
                        + "put Boston ahead for good."
                )
            }
            return sentences.joined(separator: " ")
        }

        let largestLead = annotated.map { $0.afterBoston - $0.afterOpponent }.max() ?? 0
        let opponentGoAhead = annotated.last(where: {
            $0.afterOpponent > $0.afterBoston
                && $0.beforeOpponent <= $0.beforeBoston
                && $0.afterOpponent > $0.beforeOpponent
        })
        let bostonHighlight = annotated
            .filter { $0.afterBoston > $0.beforeBoston }
            .max {
                let leftRuns = $0.afterBoston - $0.beforeBoston
                let rightRuns = $1.afterBoston - $1.beforeBoston
                return (leftRuns, $0.play.inningNum) < (rightRuns, $1.play.inningNum)
            }
        var sentences: [String] = []
        if boston.runs == 0 {
            return "The Red Sox were shut out by the \(clubName(opponent)), \(opponent.runs)–\(boston.runs), at \(venue)."
        }
        if largestLead >= 2 {
            sentences.append(
                "The Red Sox couldn’t hold a \(largestLead)-run lead and fell to the \(clubName(opponent)), "
                    + "\(opponent.runs)–\(boston.runs), at \(venue)."
            )
        } else {
            sentences.append(
                "The Red Sox fell to the \(clubName(opponent)), \(opponent.runs)–\(boston.runs), at \(venue)."
            )
        }
        if let opponentGoAhead {
            sentences.append(
                "\(scoringAction(opponentGoAhead.play)) in the \(ordinal(opponentGoAhead.play.inningNum)) "
                    + "put the \(clubName(opponent)) ahead for good."
            )
        }
        if let bostonHighlight,
           bostonHighlight.play.id != opponentGoAhead?.play.id {
            sentences.append(
                "Boston’s biggest swing came on \(scoringAction(bostonHighlight.play)) "
                    + "in the \(ordinal(bostonHighlight.play.inningNum))."
            )
        }
        return sentences.joined(separator: " ")
    }

    private func interestingFacts(
        boston: TeamBoxScore,
        opponent: TeamBoxScore,
        inningsCount: Int,
        isLive: Bool
    ) -> [String] {
        var facts: [String] = []
        if !isLive && inningsCount > 9 {
            facts.append("The game went \(inningsCount) innings.")
        }
        if let top = boston.batting.max(by: { $0.hits < $1.hits }), top.hits >= 2 {
            facts.append("\(top.name) has \(top.hits) of the Red Sox’s \(boston.hits) hits\(isLive ? " so far" : "").")
        }
        let homers = boston.batting.filter { $0.homeRuns > 0 }
        if !homers.isEmpty {
            let total = homers.reduce(0) { $0 + $1.homeRuns }
            let names = homers.map { "\($0.name) (\($0.seasonHomeRuns ?? 0))" }.joined(separator: ", ")
            facts.append("The Red Sox have hit \(total) home run\(total == 1 ? "" : "s"): \(names).")
        }
        if !isLive, let starter = boston.pitching.first {
            facts.append(
                "\(starter.name) worked \(starter.inningsPitched) innings, allowed "
                    + "\(starter.earnedRuns) earned run\(starter.earnedRuns == 1 ? "" : "s"), "
                    + "and struck out \(starter.strikeOuts)."
            )
        }
        return Array(facts.prefix(5))
    }

    private func annotate(_ plays: [NarrativePlay], bostonAway: Bool) -> [AnnotatedPlay] {
        var away = 0
        var home = 0
        return plays.map { play in
            let beforeBoston = bostonAway ? away : home
            let beforeOpponent = bostonAway ? home : away
            away = play.awayScore
            home = play.homeScore
            return AnnotatedPlay(
                play: play,
                beforeBoston: beforeBoston,
                beforeOpponent: beforeOpponent,
                afterBoston: bostonAway ? away : home,
                afterOpponent: bostonAway ? home : away
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
        team.name
            .replacingOccurrences(of: "Boston Red Sox", with: "Red Sox")
            .replacingOccurrences(of: "Seattle Mariners", with: "Mariners")
            .replacingOccurrences(of: "New York Yankees", with: "Yankees")
    }

    private func ordinal(_ value: Int) -> String {
        let remainder = value % 100
        let suffix = (11...13).contains(remainder) ? "th" : [1: "st", 2: "nd", 3: "rd"][value % 10] ?? "th"
        return "\(value)\(suffix)"
    }

    private func dictionary(_ value: Any?) -> JSON {
        value as? JSON ?? [:]
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func integerArray(_ value: Any?) -> [Int] {
        (value as? [Any] ?? []).compactMap(integer)
    }

    private func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return "0.0"
    }

    private func personName(_ value: Any?) -> String {
        dictionary(value)["fullName"] as? String ?? ""
    }
}

private typealias JSON = [String: Any]

private struct NarrativePlay: Identifiable {
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

private struct AnnotatedPlay {
    let play: NarrativePlay
    let beforeBoston: Int
    let beforeOpponent: Int
    let afterBoston: Int
    let afterOpponent: Int
}

private enum MLBGameError: Error {
    case badResponse
    case notRedSox
}
