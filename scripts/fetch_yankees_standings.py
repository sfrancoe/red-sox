#!/usr/bin/env python3
"""Fetch American League division and Wild Card standings from MLB."""

from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


NYY = 147
AL = 103
ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "data" / "yankees" / "standings.json"
API = (
    "https://statsapi.mlb.com/api/v1/standings?leagueId={league}"
    "&season={season}&standingsTypes=regularSeason,wildCard&hydrate=team"
)
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
DIVISIONS = {201: "AL East", 202: "AL Central", 200: "AL West"}
DIVISION_ORDER = {201: 0, 202: 1, 200: 2}


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
    raise RuntimeError(f"Could not fetch AL standings: {last_error}")


def last_ten(team_record: dict[str, Any]) -> str:
    splits = (team_record.get("records") or {}).get("splitRecords") or []
    split = next((item for item in splits if item.get("type") == "lastTen"), None)
    if not split:
        return "—"
    return f"{split.get('wins', 0)}-{split.get('losses', 0)}"


def team_row(team_record: dict[str, Any], rank_key: str) -> dict[str, Any]:
    team = team_record.get("team") or {}
    streak = team_record.get("streak") or {}
    return {
        "id": team.get("id"),
        "name": team.get("name") or "Team",
        "short_name": team.get("shortName") or team.get("teamName") or "Team",
        "abbreviation": team.get("abbreviation") or "",
        "rank": team_record.get(rank_key) or "—",
        "wins": team_record.get("wins", 0),
        "losses": team_record.get("losses", 0),
        "pct": team_record.get("winningPercentage") or ".000",
        "games_back": team_record.get("gamesBack") or "—",
        "wild_card_games_back": team_record.get("wildCardGamesBack") or "—",
        "last_ten": last_ten(team_record),
        "streak": streak.get("streakCode") or "—",
        "is_favorite": team.get("id") == NYY,
    }


def build_feed(payload: dict[str, Any], season: int) -> dict[str, Any]:
    divisions = []
    wild_card = []
    for record in payload.get("records", []):
        standings_type = record.get("standingsType")
        team_records = record.get("teamRecords") or []
        if standings_type == "regularSeason":
            division_id = (record.get("division") or {}).get("id")
            if division_id not in DIVISIONS:
                continue
            divisions.append(
                {
                    "id": division_id,
                    "name": DIVISIONS[division_id],
                    "teams": [team_row(team, "divisionRank") for team in team_records],
                }
            )
        elif standings_type == "wildCard":
            wild_card = [team_row(team, "wildCardRank") for team in team_records]

    divisions.sort(key=lambda division: DIVISION_ORDER[division["id"]])
    if len(divisions) != 3 or not wild_card:
        raise RuntimeError("MLB returned incomplete American League standings")
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "MLB Stats API",
        "season": season,
        "league": "American League",
        "divisions": divisions,
        "wild_card": wild_card,
    }


def feed_changed(feed: dict[str, Any]) -> bool:
    try:
        current = json.loads(OUTPUT_PATH.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return True
    keys = ("season", "divisions", "wild_card")
    return any(current.get(key) != feed.get(key) for key in keys)


def main() -> None:
    season = datetime.now(timezone.utc).year
    url = API.format(league=AL, season=season)
    feed = build_feed(fetch_json(url), season)
    if not feed_changed(feed):
        print(f"No AL standings changes; kept {OUTPUT_PATH}")
        return
    OUTPUT_PATH.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote AL standings for {season} to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
