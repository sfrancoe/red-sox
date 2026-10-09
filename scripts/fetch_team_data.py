#!/usr/bin/env python3
"""Fetch schedule, recap, standings, and pitching feeds for registry teams."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from http_refresh import fetch_json as fetch_provider_json

from team_registry import data_directory, shared_game_data_teams, team_by_key
from schedule_broadcasts import television_broadcasts


FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
EASTERN = ZoneInfo("America/New_York")
MLB = "https://statsapi.mlb.com"
SCHEDULE_API = (
    MLB + "/api/v1/schedule?sportId=1&teamId={team}&startDate={start}"
    "&endDate={end}&gameTypes=R,F,D,L,W&hydrate=probablePitcher,team,broadcasts(all)"
)
SEASON_API = MLB + "/api/v1/seasons/{season}?sportId=1"
PITCHER_STATS_API = (
    MLB + "/api/v1/people/{player_id}/stats?stats=season&group=pitching&season={season}"
)
STANDINGS_API = (
    MLB + "/api/v1/standings?leagueId={league}&season={season}"
    "&standingsTypes=regularSeason,wildCard&hydrate=team"
)
LIVE_API = MLB + "/api/v1.1/game/{game_pk}/feed/live"
CONTENT_API = MLB + "/api/v1/game/{game_pk}/content"
PROJECTIONS_API = (
    "https://www.fangraphs.com/api/projections"
    "?type=steamer&stats=pit&pos=all&team=0&lg=all&players=0"
)
ACTUAL_API = (
    "https://www.fangraphs.com/api/leaders/major-league/data"
    "?pos=all&stats=pit&lg=all&qual=0&type=8&season={season}&season1={season}"
    "&ind=0&team={team}&pageitems=200&pagenum=1"
)
DIVISIONS = {
    "AL": ({201: "AL East", 202: "AL Central", 200: "AL West"}, [201, 202, 200], 103),
    "NL": ({204: "NL East", 205: "NL Central", 203: "NL West"}, [204, 205, 203], 104),
}
_projections: list[dict[str, Any]] | None = None
_pitching_client = None


def fetch_json(url: str, required: bool = True, timeout: int = 45) -> Any:
    try:
        return fetch_provider_json(url, timeout=timeout)
    except RuntimeError:
        if required:
            raise
        return {}


def write_feed(path: Path, feed: dict[str, Any], ignored: tuple[str, ...] = ("generated_at",)) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        current = json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        current = None
    keys = [key for key in feed if key not in ignored]
    if current is not None and all(current.get(key) == feed.get(key) for key in keys):
        print(f"  unchanged {path}")
        return
    path.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    print(f"  wrote {path}")


def record(entry: dict[str, Any], live: bool = False) -> str:
    source = (entry.get("record") or {}) if live else entry
    league_record = source.get("leagueRecord") or {}
    wins, losses = league_record.get("wins"), league_record.get("losses")
    return f"{wins}-{losses}" if wins is not None and losses is not None else "—"


def pitcher(entry: dict[str, Any]) -> str:
    return str((entry.get("probablePitcher") or {}).get("fullName") or "").strip()


def pitcher_id(entry: dict[str, Any]) -> int | None:
    value = (entry.get("probablePitcher") or {}).get("id")
    return int(value) if value is not None else None


def pitcher_record(player_id: int, season: int) -> str:
    try:
        payload = fetch_json(PITCHER_STATS_API.format(player_id=player_id, season=season))
        splits = ((payload.get("stats") or [{}])[0].get("splits") or [])
        stats = (splits[0].get("stat") or {}) if splits else {}
        wins, losses = stats.get("wins"), stats.get("losses")
        return f"{wins}-{losses}" if wins is not None and losses is not None else "—"
    except (RuntimeError, IndexError, TypeError, ValueError):
        return "—"


def regular_season_end(payload: dict[str, Any]) -> date:
    seasons = payload.get("seasons") or []
    value = seasons[0].get("regularSeasonEndDate") if seasons else None
    if not value:
        raise RuntimeError("MLB did not return the regular-season end date")
    return date.fromisoformat(str(value))


def season_end(payload: dict[str, Any]) -> date:
    seasons = payload.get("seasons") or []
    value = seasons[0].get("seasonEndDate") if seasons else None
    if not value:
        raise RuntimeError("MLB did not return the season end date")
    return date.fromisoformat(str(value))


def schedule_feed(team: dict[str, Any]) -> dict[str, Any]:
    today = datetime.now(EASTERN).date()
    season_payload = fetch_json(SEASON_API.format(season=today.year))
    regular_end = regular_season_end(season_payload)
    end = season_end(season_payload)
    if today > end:
        payload = {"dates": []}
    else:
        payload = fetch_json(SCHEDULE_API.format(
            team=team["mlb_id"], start=today.isoformat(), end=end.isoformat(),
        ))
    probable_ids = {
        value
        for day in payload.get("dates", [])
        for game in day.get("games", [])
        for side in ("away", "home")
        if (value := pitcher_id(((game.get("teams") or {}).get(side) or {}))) is not None
    }
    pitcher_records = {value: pitcher_record(value, today.year) for value in sorted(probable_ids)}
    games = []
    for day in payload.get("dates", []):
        for game in day.get("games", []):
            if (game.get("status") or {}).get("abstractGameState") == "Final":
                continue
            sides = game.get("teams") or {}
            away, home = sides.get("away") or {}, sides.get("home") or {}
            if away.get("team", {}).get("id") == team["mlb_id"]:
                favorite, opponent, location = away, home, "away"
            elif home.get("team", {}).get("id") == team["mlb_id"]:
                favorite, opponent, location = home, away, "home"
            else:
                continue
            game_date = str(game.get("gameDate") or "")
            try:
                local_date = datetime.fromisoformat(game_date.replace("Z", "+00:00")).astimezone(EASTERN).date()
                days_away = (local_date - today).days
            except ValueError:
                days_away = 99
            opponent_team = opponent.get("team") or {}
            games.append({
                "game_pk": game.get("gamePk"), "game_date": game_date,
                "status": (game.get("status") or {}).get("detailedState") or "Scheduled",
                "venue": (game.get("venue") or {}).get("name") or "", "location": location,
                "opponent": opponent_team.get("teamName") or opponent_team.get("clubName")
                or opponent_team.get("name") or "Opponent",
                "opponent_record": record(opponent),
                "favorite_team_record": record(favorite),
                "favorite_team_pitcher": pitcher(favorite),
                "opponent_pitcher": pitcher(opponent),
                "favorite_team_pitcher_record": pitcher_records.get(pitcher_id(favorite) or 0, "—"),
                "opponent_pitcher_record": pitcher_records.get(pitcher_id(opponent) or 0, "—"),
                "show_probables": days_away <= 4,
                "series_description": game.get("seriesDescription") or "Regular Season",
                "doubleheader": game.get("doubleHeader") not in (None, "N"),
                "game_number": game.get("gameNumber") or 1,
                "broadcasts": television_broadcasts(game),
            })
    games.sort(key=lambda game: (game["game_date"], game["game_pk"] or 0))
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(), "source": "MLB Stats API",
        "team": team["short_name"], "regular_season_end": regular_end.isoformat(), "games": games,
    }


def last_ten(team_record: dict[str, Any]) -> str:
    splits = (team_record.get("records") or {}).get("splitRecords") or []
    item = next((row for row in splits if row.get("type") == "lastTen"), None)
    return f"{item.get('wins', 0)}-{item.get('losses', 0)}" if item else "—"


def standings_row(team_record: dict[str, Any], rank_key: str, favorite_id: int) -> dict[str, Any]:
    club = team_record.get("team") or {}
    return {
        "id": club.get("id"), "name": club.get("name") or "Team",
        "short_name": club.get("shortName") or club.get("teamName") or "Team",
        "abbreviation": club.get("abbreviation") or "", "rank": team_record.get(rank_key) or "—",
        "wins": team_record.get("wins", 0), "losses": team_record.get("losses", 0),
        "pct": team_record.get("winningPercentage") or ".000",
        "games_back": team_record.get("gamesBack") or "—",
        "wild_card_games_back": team_record.get("wildCardGamesBack") or "—",
        "last_ten": last_ten(team_record),
        "streak": (team_record.get("streak") or {}).get("streakCode") or "—",
        "is_favorite": club.get("id") == favorite_id,
    }


def standings_feed(team: dict[str, Any]) -> dict[str, Any]:
    season = datetime.now(timezone.utc).year
    names, order, league_id = DIVISIONS[team["league"]]
    payload = fetch_json(STANDINGS_API.format(league=league_id, season=season))
    divisions, wild_card = [], []
    for record_block in payload.get("records", []):
        rows = record_block.get("teamRecords") or []
        if record_block.get("standingsType") == "regularSeason":
            division_id = (record_block.get("division") or {}).get("id")
            if division_id in names:
                divisions.append({
                    "id": division_id, "name": names[division_id],
                    "teams": [standings_row(row, "divisionRank", team["mlb_id"]) for row in rows],
                })
        elif record_block.get("standingsType") == "wildCard":
            wild_card = [standings_row(row, "wildCardRank", team["mlb_id"]) for row in rows]
    divisions.sort(key=lambda item: order.index(item["id"]))
    if len(divisions) != 3 or not wild_card:
        raise RuntimeError(f"MLB returned incomplete {team['league']} standings")
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(), "source": "MLB Stats API",
        "season": season, "league": "American League" if team["league"] == "AL" else "National League",
        "divisions": divisions, "wild_card": wild_card,
    }


def player_rows(team_box: dict[str, Any], role: str) -> list[dict[str, Any]]:
    players = team_box.get("players") or {}
    ids = team_box.get("batters" if role == "batting" else "pitchers") or []
    rows = []
    for order, player_id_value in enumerate(ids):
        player = players.get(f"ID{player_id_value}") or {}
        stats = (player.get("stats") or {}).get(role) or {}
        if role == "batting" and not stats.get("plateAppearances"):
            continue
        if role == "pitching" and not stats.get("gamesPitched"):
            continue
        row = {
            "mlb_id": player_id_value,
            "name": (player.get("person") or {}).get("fullName") or "Player",
            "position": (player.get("position") or {}).get("abbreviation") or "",
            "note": stats.get("note") or "", "order": order,
        }
        if role == "batting":
            row.update({key: stats.get(key, 0) for key in (
                "atBats", "runs", "hits", "rbi", "baseOnBalls", "strikeOuts",
                "leftOnBase", "homeRuns", "stolenBases",
            )})
            season_stats = (player.get("seasonStats") or {}).get("batting") or {}
            row["average"] = season_stats.get("avg") or ".---"
            row["season_home_runs"] = int(season_stats.get("homeRuns") or 0)
        else:
            row.update({key: stats.get(key, 0) for key in (
                "inningsPitched", "hits", "runs", "earnedRuns", "baseOnBalls",
                "strikeOuts", "homeRuns", "numberOfPitches",
            )})
        rows.append(row)
    return rows


def team_box(side: str, game_data: dict[str, Any], live_data: dict[str, Any]) -> dict[str, Any]:
    club = game_data["teams"][side]
    box = live_data["boxscore"]["teams"][side]
    totals = live_data["linescore"]["teams"][side]
    return {
        "side": side, "id": club.get("id"), "name": club.get("name"),
        "club_name": club.get("teamName") or club.get("clubName") or club.get("name"),
        "abbreviation": club.get("abbreviation"), "record": record(club, live=True),
        "runs": totals.get("runs", 0), "hits": totals.get("hits", 0),
        "errors": totals.get("errors", 0), "left_on_base": totals.get("leftOnBase", 0),
        "batting": player_rows(box, "batting"), "pitching": player_rows(box, "pitching"),
        "team_batting": (box.get("teamStats") or {}).get("batting") or {},
    }


def decision(live_data: dict[str, Any], key: str) -> str:
    return ((live_data.get("decisions") or {}).get(key) or {}).get("fullName") or ""


class NoRecentGameError(RuntimeError):
    """No completed game inside the lookback window (off days, offseason)."""


def ordinal(value: int) -> str:
    if 10 < value % 100 < 14:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(value % 10, "th")
    return f"{value}{suffix}"


def possessive(name: str) -> str:
    return f"{name}’" if name.endswith("s") else f"{name}’s"


def scoring_action(play: dict[str, Any], team: dict[str, Any]) -> str:
    batter = play.get("batter") or team["city_name"]
    event = str(play.get("event") or "scoring play").lower()
    event = {"sac fly": "sacrifice fly", "field error": "error"}.get(event, event)
    runs = int(play.get("rbi") or 0)
    run_label = {2: "two-run ", 3: "three-run ", 4: "grand slam "}.get(runs, "")
    if runs == 4 and event == "home run":
        event = ""
    return f"{possessive(batter)} {run_label}{event}".strip()


def build_summary(team: dict[str, Any], favorite: dict[str, Any], opponent: dict[str, Any],
                  venue: str, scoring: list[dict[str, Any]]) -> str:
    """One-paragraph recap: comebacks, walk-offs, shutouts and blown leads."""
    name, place = team["short_name"], team["city_name"]
    ours, theirs = favorite["runs"], opponent["runs"]
    score = f"{ours}–{theirs}"
    opponent_name = opponent["club_name"]
    annotated = []
    away_score = home_score = 0
    for play in scoring:
        before_ours = away_score if favorite["side"] == "away" else home_score
        before_theirs = home_score if favorite["side"] == "away" else away_score
        away_score = int(play.get("away_score") or 0)
        home_score = int(play.get("home_score") or 0)
        annotated.append({
            **play,
            "before_ours": before_ours, "before_theirs": before_theirs,
            "after_ours": away_score if favorite["side"] == "away" else home_score,
            "after_theirs": home_score if favorite["side"] == "away" else away_score,
        })

    if ours > theirs:
        largest_deficit = max(
            (play["after_theirs"] - play["after_ours"] for play in annotated), default=0,
        )
        deficit_index = max(
            range(len(annotated)),
            key=lambda index: annotated[index]["after_theirs"] - annotated[index]["after_ours"],
            default=0,
        )
        go_ahead = [
            play for play in annotated
            if play["after_ours"] > play["before_ours"]
            and play["before_ours"] <= play["before_theirs"]
            and play["after_ours"] > play["after_theirs"]
        ]
        winning_play = go_ahead[-1] if go_ahead else None
        walkoff = (
            winning_play is not None and favorite["side"] == "home"
            and int(winning_play.get("inning_num") or 0) >= 9
            and winning_play is annotated[-1]
        )
        if walkoff:
            first = (
                f"{winning_play.get('batter') or place} delivered a walk-off "
                f"{str(winning_play.get('event') or 'hit').lower()} in the "
                f"{ordinal(int(winning_play['inning_num']))} inning as the {name} rallied past "
                f"the {opponent_name}, {score}, at {venue}."
            )
        elif largest_deficit >= 2:
            first = (
                f"The {name} erased a {largest_deficit}-run deficit to beat the "
                f"{opponent_name}, {score}, at {venue}."
            )
        elif theirs == 0:
            first = f"The {name} shut out the {opponent_name}, {score}, at {venue}."
        else:
            first = f"The {name} beat the {opponent_name}, {score}, at {venue}."

        details = []
        if largest_deficit >= 2 and annotated:
            low_point = annotated[deficit_index]
            rally_play = next((
                play for play in annotated[deficit_index + 1:]
                if play["after_ours"] > play["before_ours"]
            ), None)
            if rally_play:
                remaining = rally_play["after_theirs"] - rally_play["after_ours"]
                effect = (
                    "tied the game" if remaining == 0
                    else f"put {place} ahead" if remaining < 0
                    else f"cut the deficit to {'one' if remaining == 1 else remaining}"
                )
                details.append(
                    f"{place} trailed {low_point['after_theirs']}–{low_point['after_ours']} before "
                    f"{scoring_action(rally_play, team)} in the "
                    f"{ordinal(int(rally_play['inning_num']))} {effect}."
                )
        tying_play = next((
            play for play in annotated[deficit_index + 1:]
            if play["after_ours"] > play["before_ours"]
            and play["before_ours"] < play["before_theirs"]
            and play["after_ours"] == play["after_theirs"]
        ), None)
        if walkoff and tying_play and tying_play is not winning_play:
            innings_later = int(winning_play["inning_num"]) - int(tying_play["inning_num"])
            timing = "one inning later" if innings_later == 1 else "later"
            details.append(
                f"{scoring_action(tying_play, team)} tied it in the "
                f"{ordinal(int(tying_play['inning_num']))}, and "
                f"{winning_play.get('batter') or place} completed the comeback {timing}."
            )
        return " ".join([first, *details])

    largest_lead = max((play["after_ours"] - play["after_theirs"] for play in annotated), default=0)
    if ours == 0:
        return f"The {name} were shut out by the {opponent_name}, {theirs}–{ours}, at {venue}."
    if largest_lead >= 2:
        return (
            f"The {name} couldn’t hold a {largest_lead}-run lead and fell to the "
            f"{opponent_name}, {theirs}–{ours}, at {venue}."
        )
    return f"The {name} fell to the {opponent_name}, {theirs}–{ours}, at {venue}."


def interesting_facts(team: dict[str, Any], favorite: dict[str, Any],
                      opponent: dict[str, Any], innings_count: int) -> list[str]:
    name = team["short_name"]
    facts = []
    if innings_count > 9:
        facts.append(f"The game went {innings_count} innings.")
    if favorite["runs"] == 0:
        facts.append(f"The {name} were held scoreless despite putting {favorite['hits']} hits on the board.")
    elif opponent["runs"] == 0:
        facts.append(f"{name} pitchers combined for a {innings_count}-inning shutout.")

    earned = sum(int(row.get("earnedRuns") or 0) for row in favorite["pitching"])
    unearned = max(0, opponent["runs"] - earned)
    if favorite["errors"] >= 2:
        detail = f"; {unearned} opponent runs were unearned" if unearned else ""
        facts.append(f"The {name} committed {favorite['errors']} errors{detail}.")

    opponent_batting = opponent.get("team_batting") or {}
    steals = int(opponent_batting.get("stolenBases") or 0)
    caught = int(opponent_batting.get("caughtStealing") or 0)
    if steals >= 3:
        facts.append(
            f"The {opponent['club_name']} went {steals}-for-{steals + caught} on stolen-base attempts."
        )

    top_hitter = max(favorite["batting"], key=lambda row: int(row.get("hits") or 0), default=None)
    if top_hitter and int(top_hitter.get("hits") or 0) >= 2:
        facts.append(
            f"{top_hitter['name']} collected {top_hitter['hits']} of the "
            f"{possessive(name)} {favorite['hits']} hits."
        )

    homers = [row for row in favorite["batting"] if int(row.get("homeRuns") or 0)]
    if homers:
        names = ", ".join(f"{row['name']} ({row['season_home_runs']})" for row in homers)
        total = sum(int(row["homeRuns"]) for row in homers)
        facts.append(f"The {name} hit {total} home run{'s' if total != 1 else ''}: {names}.")

    starter = favorite["pitching"][0] if favorite["pitching"] else None
    if starter:
        earned_runs = int(starter.get("earnedRuns") or 0)
        facts.append(
            f"{starter['name']} worked {starter['inningsPitched']} innings, allowed "
            f"{earned_runs} earned run{'s' if earned_runs != 1 else ''}, and struck out "
            f"{starter['strikeOuts']}."
        )
    return facts[:5]


def recent_game_feed(team: dict[str, Any]) -> dict[str, Any]:
    today = datetime.now(EASTERN).date()
    payload = fetch_json(SCHEDULE_API.format(
        team=team["mlb_id"], start=(today - timedelta(days=14)).isoformat(), end=today.isoformat(),
    ))
    finals = [
        game for day in payload.get("dates", []) for game in day.get("games", [])
        if (game.get("status") or {}).get("abstractGameState") == "Final"
        # MLB also labels cancelled and postponed games as abstractly Final.
        and (game.get("status") or {}).get("codedGameState") not in {"C", "D"}
    ]
    if not finals:
        raise NoRecentGameError(f"No completed {team['short_name']} game found in the past 14 days")
    finals.sort(key=lambda game: (game.get("gameDate") or "", game.get("gamePk") or 0))
    game_pk = int(finals[-1]["gamePk"])
    live = fetch_json(LIVE_API.format(game_pk=game_pk))
    content = fetch_json(CONTENT_API.format(game_pk=game_pk), required=False)
    return build_recent_game_feed(team, game_pk, live, content)


def build_recent_game_feed(team: dict[str, Any], game_pk: int, live: dict[str, Any],
                           content: dict[str, Any]) -> dict[str, Any]:
    game_data, live_data = live["gameData"], live["liveData"]
    away, home = team_box("away", game_data, live_data), team_box("home", game_data, live_data)
    favorite = away if away["id"] == team["mlb_id"] else home
    opponent = home if favorite is away else away
    won = favorite["runs"] > opponent["runs"]
    venue = (game_data.get("venue") or {}).get("name") or "the ballpark"
    innings = live_data["linescore"].get("innings") or []
    all_plays = (live_data.get("plays") or {}).get("allPlays") or []
    scoring = []
    for index in (live_data.get("plays") or {}).get("scoringPlays") or []:
        play = all_plays[index]
        about, result = play.get("about") or {}, play.get("result") or {}
        matchup = play.get("matchup") or {}
        scoring.append({
            "inning": f"{about.get('halfInning', '').title()} {about.get('inning', '')}",
            "inning_num": about.get("inning", 0), "half": about.get("halfInning", ""),
            "batter": (matchup.get("batter") or {}).get("fullName") or "",
            "event": result.get("event") or "", "rbi": result.get("rbi", 0),
            "description": result.get("description") or result.get("event") or "Scoring play",
            "away_score": result.get("awayScore", 0), "home_score": result.get("homeScore", 0),
        })
    recap = (((content.get("editorial") or {}).get("recap") or {}).get("mlb") or {})
    recap_slug = str(recap.get("slug") or "").strip()
    game_info = game_data.get("gameInfo") or {}
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(), "source": "MLB Stats API",
        "game_pk": game_pk, "game_date": (game_data.get("datetime") or {}).get("dateTime") or "",
        "venue": venue, "game_duration_minutes": game_info.get("gameDurationMinutes"),
        "attendance": game_info.get("attendance"), "innings_count": len(innings),
        "result": "Win" if won else "Loss",
        "summary": build_summary(team, favorite, opponent, venue, scoring),
        "facts": interesting_facts(team, favorite, opponent, len(innings)),
        "decisions": {key: decision(live_data, key) for key in ("winner", "loser", "save")},
        "away": away, "home": home, "innings": innings, "scoring_plays": scoring,
        "official_recap": {
            "headline": str(recap.get("headline") or "").strip(),
            "url": f"https://www.mlb.com/news/{recap_slug}" if recap_slug else "",
        },
        "gameday_url": f"https://www.mlb.com/gameday/{game_pk}",
    }


def number(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def innings_value(value: Any) -> float:
    whole, _, remainder = str(value or 0).partition(".")
    return (int(whole) * 3 + int((remainder or "0")[:1])) / 3


def innings_display(value: Any) -> str:
    whole, _, remainder = str(value or 0).partition(".")
    return f"{whole}.{(remainder or '0')[:1]}"


def role_for(row: dict[str, Any]) -> str:
    games, starts = int(number(row.get("G"))), int(number(row.get("GS")))
    if starts >= 5 and number(row.get("Relief-IP")) >= 12:
        return "Swingman"
    if starts >= 5 or (starts and starts >= games / 2):
        return "Starter"
    if int(number(row.get("SV"))) >= 10:
        return "Closer"
    if int(number(row.get("HLD"))) >= 10:
        return "Setup"
    return "Reliever"


def pitching_feed(team: dict[str, Any]) -> dict[str, Any]:
    # Direct callers obey the same winter/season policy as the consolidated job.
    from refresh_pitching import FanGraphsClient, load_policy, output_path, refresh_allowed, build_team
    policy = load_policy()
    if not refresh_allowed(policy, datetime.now(timezone.utc).date()):
        return json.loads(output_path(team).read_text())
    global _projections, _pitching_client
    if _pitching_client is None:
        _pitching_client = FanGraphsClient(policy["request_spacing_seconds"], policy["budget_seconds"])
    if _projections is None:
        _projections = _pitching_client.get(policy["projections_url"])
    return build_team(team, _projections, policy["season"], _pitching_client)


def build_pitching_feed(team: dict[str, Any], projections: list[dict[str, Any]],
                        actual_payload: dict[str, Any], standings: dict[str, Any],
                        season: int) -> dict[str, Any]:
    actual_rows = actual_payload.get("data") or []
    if not actual_rows:
        raise RuntimeError(f"FanGraphs returned no {team['short_name']} pitching rows")
    played = next(
        int(row.get("wins", 0)) + int(row.get("losses", 0))
        for block in standings.get("records", []) for row in block.get("teamRecords", [])
        if (row.get("team") or {}).get("id") == team["mlb_id"]
    )
    fraction = played / 162
    projection_by_id = {
        str(row.get("xMLBAMID")): row for row in projections if row.get("xMLBAMID")
    }
    pitchers = []
    for actual in actual_rows:
        mlb_id = str(actual.get("xMLBAMID") or "")
        projection = projection_by_id.get(mlb_id)
        actual_ip, actual_war = innings_value(actual.get("IP")), number(actual.get("WAR"))
        projected_war = number(projection.get("WAR")) if projection else 0
        projected_ip = number(projection.get("IP")) if projection else 0
        pitchers.append({
            "id": int(number(actual.get("xMLBAMID"))),
            "name": actual.get("PlayerName") or f"{team['short_name']} pitcher",
            "throws": actual.get("Throws") or "—", "role": role_for(actual),
            "games": int(number(actual.get("G"))), "starts": int(number(actual.get("GS"))),
            "saves": int(number(actual.get("SV"))), "holds": int(number(actual.get("HLD"))),
            "actual": {
                "ip": innings_display(actual.get("IP")), "ip_value": round(actual_ip, 3),
                "war": round(actual_war, 2), "era": round(number(actual.get("ERA")), 2),
                "fip": round(number(actual.get("FIP")), 2),
                "k_minus_bb_pct": round(number(actual.get("K-BB%")) * 100, 1),
            },
            "forecast": None if not projection else {
                "ip": round(projected_ip, 1), "war": round(projected_war, 2),
                "era": round(number(projection.get("ERA")), 2),
                "fip": round(number(projection.get("FIP")), 2),
                "k_minus_bb_pct": round(number(projection.get("K-BB%")) * 100, 1),
                "team_at_fetch": projection.get("Team") or None,
            },
            "forecast_to_date": {
                "ip": round(projected_ip * fraction, 1), "war": round(projected_war * fraction, 2),
            },
            "war_gap": round(actual_war - projected_war * fraction, 2),
        })
    pitchers.sort(key=lambda row: row["actual"]["war"], reverse=True)
    total_ip = sum(row["actual"]["ip_value"] for row in pitchers)
    total_er = sum(number(row.get("ER")) for row in actual_rows)
    for row in pitchers:
        row["innings_share_pct"] = round(row["actual"]["ip_value"] / total_ip * 100 if total_ip else 0, 1)
    actual_war = sum(row["actual"]["war"] for row in pitchers)
    forecast_war = sum(row["forecast_to_date"]["war"] for row in pitchers)
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(), "season": season,
        "team": team["full_name"], "games_played": played, "season_fraction": round(fraction, 4),
        "method": (
            "Actual FanGraphs pitching WAR is compared with preseason Steamer WAR "
            f"prorated to {team['city_name']}'s games played."
        ),
        "sources": {
            "actual": "FanGraphs Major League Leaderboards",
            "forecast": "FanGraphs Steamer preseason projections", "games_played": "MLB Stats API",
            "actual_url": "https://www.fangraphs.com/leaders/major-league",
            "forecast_url": "https://www.fangraphs.com/projections",
        },
        "team_summary": {
            "actual_war": round(actual_war, 1), "forecast_war_to_date": round(forecast_war, 1),
            "war_gap": round(actual_war - forecast_war, 1), "innings": round(total_ip, 1),
            "era": round(total_er / total_ip * 9 if total_ip else 0, 2),
        },
        "pitchers": pitchers,
    }


def fetch_team(team: dict[str, Any], sections: list[str]) -> None:
    output = data_directory(team)
    print(f"{team['full_name']}:")
    builders = {
        "schedule": ("schedule.json", schedule_feed),
        "recent-game": ("recent-game.json", recent_game_feed),
        "standings": ("standings.json", standings_feed),
        "pitching": ("pitching.json", pitching_feed),
    }
    for section in sections:
        file_name, builder = builders[section]
        try:
            feed = builder(team)
        except NoRecentGameError as exc:
            # Off days and the offseason: the last completed game stays the
            # right recap, so keep it rather than failing every later team.
            if not (output / file_name).exists():
                raise
            print(f"  kept {output / file_name} ({exc})")
            continue
        write_feed(output / file_name, feed)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team", action="append", default=[])
    parser.add_argument(
        "--section", action="append",
        choices=("schedule", "recent-game", "standings", "pitching"), default=[],
    )
    parser.add_argument(
        "--keep-going", action="store_true",
        help="Try every selected team, then fail if any team could not be refreshed.",
    )
    args = parser.parse_args()
    teams = [team_by_key(key) for key in args.team] if args.team else shared_game_data_teams()
    sections = args.section or ["schedule", "recent-game", "standings", "pitching"]
    failures: list[tuple[str, RuntimeError]] = []
    for team in teams:
        try:
            fetch_team(team, sections)
        except RuntimeError as exc:
            if not args.keep_going:
                raise
            failures.append((team["full_name"], exc))
            print(f"  ERROR: {exc}", file=sys.stderr)
    if failures:
        names = ", ".join(name for name, _ in failures)
        raise RuntimeError(f"Refresh failed for {len(failures)} team(s): {names}") from failures[0][1]


if __name__ == "__main__":
    main()
