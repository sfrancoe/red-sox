import SwiftUI

struct PlayoffBracketView: View {
    let payload: PostseasonPayload
    let onSelect: (PostseasonSeries) -> Void
    @ScaledMetric(relativeTo: .caption) private var minimumCardWidth = 82.0
    @ScaledMetric(relativeTo: .caption) private var cardHeight = 68.0
    @ScaledMetric(relativeTo: .caption) private var nameSize = 12.0
    private let columnSpacing = 10.0
    private let rowSpacing = 8.0
    private let leagueRailWidth = 18.0
    private let leagueRailSpacing = 4.0
    private let unresolvedLabel = "- - -"

    private func series(_ slot: PlayoffBracketSlot) -> PostseasonSeries? {
        payload.series.first { $0.id == slot.seriesID(season: payload.season) }
    }

    var body: some View {
        GeometryReader { bounds in
            let bracketWidth = max(
                bounds.size.width - 20 - leagueRailWidth - leagueRailSpacing,
                minimumCardWidth * 3 + columnSpacing * 2
            )
            let contentWidth = bracketWidth + leagueRailWidth + leagueRailSpacing
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 10) {
                    leagueBracket("AL", title: "AMERICAN LEAGUE", color: AppColor.steel, width: bracketWidth)
                    worldSeries(width: contentWidth)
                    leagueBracket("NL", title: "NATIONAL LEAGUE", color: AppColor.amber, width: bracketWidth)
                }
                .frame(width: contentWidth)
                .padding(10)
            }
            .defaultScrollAnchor(.topLeading)
            .accessibilityIdentifier("playoffs.bracket")
        }
    }

    private func leagueSlots(_ league: String) -> [PlayoffBracketSlot] {
        PlayoffBracketSlot.all.filter { $0.league == league }
    }

    private func columnIndex(for slot: PlayoffBracketSlot) -> Int {
        switch slot.round {
        case "wild-card": 0
        case "division-series": 1
        default: 2
        }
    }

    private func center(_ slot: PlayoffBracketSlot, width: CGFloat) -> CGPoint {
        let cell = (width - columnSpacing * 2) / 3
        let bracketHeight = cardHeight * 2 + rowSpacing
        let y = slot.round == "league-championship"
            ? bracketHeight / 2
            : cardHeight / 2 + CGFloat(slot.row) * (cardHeight + rowSpacing)
        return CGPoint(
            x: cell / 2 + CGFloat(columnIndex(for: slot)) * (cell + columnSpacing),
            y: y
        )
    }

    private func leagueBracket(_ league: String, title: String, color: Color, width: CGFloat) -> some View {
        let slots = leagueSlots(league)
        let cell = (width - columnSpacing * 2) / 3
        let bracketHeight = cardHeight * 2 + rowSpacing
        return HStack(spacing: leagueRailSpacing) {
            leagueHeading(title, color: color)
                .frame(width: leagueRailWidth, height: bracketHeight)

            VStack(spacing: 6) {
                HStack(spacing: columnSpacing) {
                    roundHeading("WILD CARD").frame(width: cell)
                    roundHeading("DIVISION").frame(width: cell)
                    Color.clear.frame(width: cell, height: 1)
                }
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for slot in slots {
                            guard let destination = slots.first(where: { $0.id == slot.destinationID }) else { continue }
                            let start = center(slot, width: width)
                            let end = center(destination, width: width)
                            let startEdge = CGPoint(x: start.x + cell / 2, y: start.y)
                            let endEdge = CGPoint(x: end.x - cell / 2, y: end.y)
                            let elbow = (startEdge.x + endEdge.x) / 2
                            var path = Path()
                            path.move(to: startEdge)
                            path.addLine(to: CGPoint(x: elbow, y: startEdge.y))
                            path.addLine(to: CGPoint(x: elbow, y: endEdge.y))
                            path.addLine(to: endEdge)
                            let confirmed = series(slot)?.winnerTeamId != nil
                            context.stroke(path, with: .color(confirmed ? AppColor.amber : AppColor.boneMuted.opacity(0.55)), lineWidth: confirmed ? 2 : 1)
                        }
                    }
                    .accessibilityHidden(true)

                    if let championship = slots.first(where: { $0.round == "league-championship" }) {
                        roundHeading(league == "AL" ? "ALCS" : "NLCS")
                            .frame(width: cell)
                            .position(
                                x: center(championship, width: width).x,
                                y: center(championship, width: width).y - cardHeight / 2 - 11
                            )
                    }

                    ForEach(slots) { slot in
                        matchup(slot, width: cell)
                            .frame(width: cell, height: cardHeight)
                            .position(center(slot, width: width))
                    }
                }
                .frame(width: width, height: bracketHeight)
            }
        }
        .frame(width: width + leagueRailWidth + leagueRailSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) playoff bracket")
    }

    private func worldSeries(width: CGFloat) -> some View {
        let slot = PlayoffBracketSlot.all.first { $0.league == "MLB" }!
        let cardWidth = min(max(minimumCardWidth * 1.7, width * 0.52), 280)
        return VStack(spacing: 12) {
            Text("WORLD SERIES")
                .font(.system(size: nameSize, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(AppColor.amber)
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                matchup(slot, width: cardWidth)
                    .frame(width: cardWidth, height: cardHeight)
                Image(systemName: "trophy.fill")
            }
            .font(.system(size: nameSize * 1.2, weight: .bold))
            .foregroundStyle(AppColor.amber)
        }
        .frame(width: width)
    }

    private func leagueHeading(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: nameSize, weight: .bold)).tracking(1.5)
            .foregroundStyle(color)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .background(AppColor.night)
    }

    private func roundHeading(_ text: String) -> some View {
        Text(text).font(.system(size: nameSize - 3, weight: .semibold))
            .tracking(0.5).foregroundStyle(AppColor.boneMuted)
            .background(AppColor.night)
    }

    private func matchup(_ slot: PlayoffBracketSlot, width: CGFloat) -> some View {
        let labelSize = width > 120 ? nameSize * 1.15 : nameSize
        let item = series(slot)
        let rows = participants(item, slot: slot)
        let hasScheduledDate = nextScheduledGame(for: item) != nil
        return Button {
            if let item { onSelect(item) }
        } label: {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Group {
                        if row.resolved {
                            HStack(spacing: 4) {
                                Text(compactName(row, width: width))
                                    .font(.system(size: labelSize, weight: .semibold))
                                    .foregroundStyle(AppColor.bone)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if item?.winnerTeamId == row.teamId, row.teamId != nil {
                                    Image(systemName: "checkmark").font(.system(size: labelSize - 2, weight: .bold))
                                        .foregroundStyle(AppColor.amber)
                                }
                                Text(row.teamId.flatMap { item?.wins(for: $0) }.map(String.init) ?? "–")
                                    .font(.system(size: labelSize, weight: .bold, design: .monospaced))
                                    .foregroundStyle(item?.winnerTeamId == row.teamId && row.teamId != nil ? AppColor.amber : AppColor.bone)
                            }
                        } else {
                            Text(unresolvedLabel)
                                .font(.system(size: labelSize, weight: .semibold))
                                .foregroundStyle(AppColor.playoffTBD)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.horizontal, 7)
                    .frame(maxHeight: .infinity)
                    if index == 0 { Rectangle().fill(AppColor.rule).frame(height: 0.5) }
                }
                Text(status(item))
                    .font(.system(size: labelSize - 3, weight: .medium))
                    .foregroundStyle(hasScheduledDate ? AppColor.night : (item?.state == "live" ? AppColor.amber : AppColor.boneMuted))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(hasScheduledDate ? AppColor.scheduleGray : AppColor.night)
            }
            .background(AppColor.nightRaised)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(slot.league == "MLB" ? AppColor.amber.opacity(0.8) : AppColor.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item == nil)
        .accessibilityIdentifier("bracket.\(slot.id)")
        .accessibilityLabel("\(slot.league) \(slot.round.replacingOccurrences(of: "-", with: " ")), \(rows.map { $0.name ?? $0.slot ?? "TBD" }.joined(separator: " versus "))")
        .accessibilityValue(rows.map { row in
            "\(row.name ?? row.slot ?? "TBD"): \(row.teamId.flatMap { item?.wins(for: $0) }.map { "\($0) series wins" } ?? "unresolved")"
        }.joined(separator: ", ") + ". " + status(item))
        .accessibilityHint("Opens series details")
    }

    private func participants(_ item: PostseasonSeries?, slot: PlayoffBracketSlot) -> [PostseasonClub] {
        var result = item?.participants ?? []
        let fallback: [String]
        switch slot.round {
        case "world-series": fallback = ["AL champion", "NL champion"]
        case "league-championship": fallback = ["TBD", "TBD"]
        default: fallback = item?.unresolvedSlots ?? []
        }
        for label in fallback where result.count < 2 {
            result.append(PostseasonClub(teamId: nil, name: nil, abbreviation: nil, slot: label, resolved: false))
        }
        while result.count < 2 {
            result.append(PostseasonClub(teamId: nil, name: nil, abbreviation: nil, slot: "TBD", resolved: false))
        }
        return Array(result.prefix(2))
    }

    private func compactName(_ club: PostseasonClub, width: CGFloat) -> String {
        if let id = club.teamId, let team = HubTeam.allCases.first(where: { $0.mlbID == id }) {
            return width > 150 ? team.shortName : (club.abbreviation ?? team.abbreviation)
        }
        let label = club.slot ?? club.name ?? "TBD"
        if label.hasSuffix("champion") { return label }
        return label.replacingOccurrences(of: "AL ", with: "")
            .replacingOccurrences(of: "NL ", with: "")
            .replacingOccurrences(of: "Wild Card #", with: "WC ")
            .replacingOccurrences(of: " Winner", with: " winner")
    }

    private func status(_ item: PostseasonSeries?) -> String {
        guard let item else { return "MATCHUP \(unresolvedLabel)" }
        if item.state == "complete" { return "FINAL · \(item.completedGameCount) GAMES" }
        if item.state == "unknown" { return "UNDER REVIEW" }
        let games = payload.games.filter { $0.seriesId == item.id }
        if let live = games.first(where: { $0.abstractState == "Live" }) {
            return "LIVE" + (live.liveInning.map { " · INNING \($0)" } ?? "")
        }
        if let next = nextScheduledGame(for: item) {
            return displayDate(next)
        }
        return item.requiredWins.map { "FIRST TO \($0)" } ?? "MATCHUP \(unresolvedLabel)"
    }

    private func displayDate(_ game: PostseasonGame) -> String {
        guard let rawDate = game.gameDate else { return unresolvedLabel }
        let parts = rawDate.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]), (1...12).contains(month),
              let day = Int(parts[2]) else { return unresolvedLabel }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[month - 1]) \(day)"
    }

    private func nextScheduledGame(for item: PostseasonSeries?) -> PostseasonGame? {
        guard let item else { return nil }
        return payload.games
            .filter {
                $0.seriesId == item.id
                    && ($0.abstractState == "Preview" || $0.abstractState == "Scheduled")
            }
            .min(by: { ($0.gameDate ?? "") < ($1.gameDate ?? "") })
    }

}
