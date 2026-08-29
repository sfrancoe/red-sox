#!/usr/bin/env python3
"""Fetch the upcoming Red Sox schedule from the MLB Stats API."""

from __future__ import annotations

import json
import time
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo


BOS = 111
ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "data" / "schedule.json"
API = (
    "https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId={team}"
    "&startDate={start}&endDate={end}&gameType=R&hydrate=probablePitcher,team"
)
SEASON_API = "https://statsapi.mlb.com/api/v1/seasons/{season}?sportId=1"
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
EASTERN = ZoneInfo("America/New_York")


def fetch_json(url: str) -> dict[str, Any]:
    """Use normal request defaults first, then the approved fallback UA."""
    last_error: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        for attempt in range(3):
            try:
                request = Request(url, headers=headers)
                with urlopen(request, timeout=30) as response:
                    return json.load(response)
            except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
                last_error = exc
                if attempt < 2:
                    time.sleep(2**attempt)
        if headers:
            break
    raise RuntimeError(f"Could not fetch upcoming schedule: {last_error}")


def record(team_entry: dict[str, Any]) -> str:
    league_record = team_entry.get("leagueRecord") or {}
    wins = league_record.get("wins")
    losses = league_record.get("losses")
    return f"{wins}-{losses}" if wins is not None and losses is not None else "—"


def pitcher(team_entry: dict[str, Any]) -> str:
    return str((team_entry.get("probablePitcher") or {}).get("fullName") or "").strip()


def regular_season_end(payload: dict[str, Any]) -> date:
    seasons = payload.get("seasons") or []
    value = seasons[0].get("regularSeasonEndDate") if seasons else None
    if not value:
        raise RuntimeError("MLB did not return the regular-season end date")
    try:
        return date.fromisoformat(str(value))
    except ValueError as exc:
        raise RuntimeError("MLB returned an invalid regular-season end date") from exc


def game_row(game: dict[str, Any], today) -> dict[str, Any] | None:
    teams = game.get("teams") or {}
    away = teams.get("away") or {}
    home = teams.get("home") or {}
    away_team = away.get("team") or {}
    home_team = home.get("team") or {}
    if away_team.get("id") == BOS:
        red_sox, opponent, location = away, home, "away"
    elif home_team.get("id") == BOS:
        red_sox, opponent, location = home, away, "home"
    else:
        return None

    game_date = str(game.get("gameDate") or "")
    try:
        local_date = datetime.fromisoformat(game_date.replace("Z", "+00:00")).astimezone(EASTERN).date()
        days_away = (local_date - today).days
    except ValueError:
        days_away = 99

    status = game.get("status") or {}
    opponent_team = opponent.get("team") or {}
    return {
        "game_pk": game.get("gamePk"),
        "game_date": game_date,
        "status": status.get("detailedState") or "Scheduled",
        "venue": (game.get("venue") or {}).get("name") or "",
        "location": location,
        "opponent": (
            opponent_team.get("teamName")
            or opponent_team.get("clubName")
            or opponent_team.get("name")
            or "Opponent"
        ),
        "opponent_record": record(opponent),
        "red_sox_record": record(red_sox),
        "red_sox_pitcher": pitcher(red_sox),
        "opponent_pitcher": pitcher(opponent),
        "show_probables": days_away <= 4,
        "series_description": game.get("seriesDescription") or "Regular Season",
        "doubleheader": game.get("doubleHeader") not in (None, "N"),
        "game_number": game.get("gameNumber") or 1,
    }


def build_feed(payload: dict[str, Any], today, season_end: date) -> dict[str, Any]:
    games = []
    for date_entry in payload.get("dates", []):
        for game in date_entry.get("games", []):
            status = game.get("status") or {}
            if status.get("abstractGameState") == "Final":
                continue
            row = game_row(game, today)
            if row:
                games.append(row)
    games.sort(key=lambda game: (game["game_date"], game["game_pk"] or 0))
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "MLB Stats API",
        "team": "Red Sox",
        "regular_season_end": season_end.isoformat(),
        "games": games,
    }


def feed_changed(feed: dict[str, Any]) -> bool:
    try:
        current = json.loads(OUTPUT_PATH.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return True
    keys = ("regular_season_end", "games")
    return any(current.get(key) != feed.get(key) for key in keys)


def main() -> None:
    today = datetime.now(EASTERN).date()
    season_payload = fetch_json(SEASON_API.format(season=today.year))
    end = regular_season_end(season_payload)
    url = API.format(team=BOS, start=today.isoformat(), end=end.isoformat())
    feed = build_feed(fetch_json(url), today, end)
    if not feed_changed(feed):
        print(f"No upcoming schedule changes; kept {OUTPUT_PATH}")
        return
    OUTPUT_PATH.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(feed['games'])} upcoming Red Sox games to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
