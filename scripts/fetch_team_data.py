#!/usr/bin/env python3
"""Fetch schedule, recap, standings, and pitching feeds for registry teams."""

from __future__ import annotations

import argparse
import json
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

from team_registry import data_directory, expansion_teams, team_by_key


FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
EASTERN = ZoneInfo("America/New_York")
MLB = "https://statsapi.mlb.com"
SCHEDULE_API = (
    MLB + "/api/v1/schedule?sportId=1&teamId={team}&startDate={start}"
    "&endDate={end}&gameType=R&hydrate=probablePitcher,team"
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


def fetch_json(url: str, required: bool = True, timeout: int = 45) -> Any:
    """Use normal defaults first, then the approved fallback UA."""
    last_error: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        for attempt in range(3):
            try:
                with urlopen(Request(url, headers=headers), timeout=timeout) as response:
                    return json.load(response)
            except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
                last_error = exc
                if attempt < 2:
                    time.sleep(2**attempt)
    if required:
        raise RuntimeError(f"Could not fetch {url}: {last_error}")
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


def schedule_feed(team: dict[str, Any]) -> dict[str, Any]:
    today = datetime.now(EASTERN).date()
    end = regular_season_end(fetch_json(SEASON_API.format(season=today.year)))
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
            })
    games.sort(key=lambda game: (game["game_date"], game["game_pk"] or 0))
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(), "source": "MLB Stats API",
        "team": team["short_name"], "regular_season_end": end.isoformat(), "games": games,
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


def recent_game_feed(team: dict[str, Any]) -> dict[str, Any]:
    today = datetime.now(EASTERN).date()
    payload = fetch_json(SCHEDULE_API.format(
        team=team["mlb_id"], start=(today - timedelta(days=14)).isoformat(), end=today.isoformat(),
    ))
    finals = [
        game for day in payload.get("dates", []) for game in day.get("games", [])
        if (game.get("status") or {}).get("abstractGameState") == "Final"
    ]
    if not finals:
        raise RuntimeError(f"No completed {team['short_name']} game found in the past 14 days")
    finals.sort(key=lambda game: (game.get("gameDate") or "", game.get("gamePk") or 0))
    game_pk = int(finals[-1]["gamePk"])
    live = fetch_json(LIVE_API.format(game_pk=game_pk))
    content = fetch_json(CONTENT_API.format(game_pk=game_pk), required=False)
    game_data, live_data = live["gameData"], live["liveData"]
    away, home = team_box("away", game_data, live_data), team_box("home", game_data, live_data)
    favorite = away if away["id"] == team["mlb_id"] else home
    opponent = home if favorite is away else away
    won = favorite["runs"] > opponent["runs"]
    venue = (game_data.get("venue") or {}).get("name") or "the ballpark"
    score = f"{favorite['runs']}–{opponent['runs']}" if won else f"{opponent['runs']}–{favorite['runs']}"
    summary = (
        f"The {team['short_name']} beat the {opponent['club_name']}, {score}, at {venue}."
        if won else f"The {team['short_name']} fell to the {opponent['club_name']}, {score}, at {venue}."
    )
    facts = []
    innings = live_data["linescore"].get("innings") or []
    if len(innings) > 9:
        facts.append(f"The game went {len(innings)} innings.")
    top_hitter = max(favorite["batting"], key=lambda row: int(row.get("hits") or 0), default=None)
    if top_hitter and int(top_hitter.get("hits") or 0) >= 2:
        facts.append(f"{top_hitter['name']} collected {top_hitter['hits']} hits.")
    starter = favorite["pitching"][0] if favorite["pitching"] else None
    if starter:
        facts.append(
            f"{starter['name']} worked {starter['inningsPitched']} innings and struck out "
            f"{starter['strikeOuts']}."
        )
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
        "result": "Win" if won else "Loss", "summary": summary, "facts": facts[:5],
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
    global _projections
    season = datetime.now(timezone.utc).year
    if _projections is None:
        loaded = fetch_json(PROJECTIONS_API)
        if not isinstance(loaded, list):
            raise RuntimeError("FanGraphs returned an unexpected projections response")
        _projections = loaded
    actual_payload = fetch_json(ACTUAL_API.format(season=season, team=team["fangraphs_id"]))
    _, _, league_id = DIVISIONS[team["league"]]
    standings = fetch_json(STANDINGS_API.format(league=league_id, season=season))
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
        str(row.get("xMLBAMID")): row for row in _projections if row.get("xMLBAMID")
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
        write_feed(output / file_name, builder(team))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team", action="append", default=[])
    parser.add_argument(
        "--section", action="append",
        choices=("schedule", "recent-game", "standings", "pitching"), default=[],
    )
    args = parser.parse_args()
    teams = [team_by_key(key) for key in args.team] if args.team else expansion_teams()
    sections = args.section or ["schedule", "recent-game", "standings", "pitching"]
    for team in teams:
        fetch_team(team, sections)


if __name__ == "__main__":
    main()
