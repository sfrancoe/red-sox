#!/usr/bin/env python3
"""Build the Above the Forecast pitching comparison from FanGraphs data."""

from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


BOS = 111
AL = 103
FANGRAPHS_BOS = 3
ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "data" / "pitching.json"
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
PROJECTIONS_API = (
    "https://www.fangraphs.com/api/projections"
    "?type=steamer&stats=pit&pos=all&team=0&lg=all&players=0"
)
ACTUAL_API = (
    "https://www.fangraphs.com/api/leaders/major-league/data"
    "?pos=all&stats=pit&lg=all&qual=0&type=8&season={season}&season1={season}"
    "&ind=0&team={team}&pageitems=200&pagenum=1"
)
STANDINGS_API = (
    "https://statsapi.mlb.com/api/v1/standings?leagueId={league}"
    "&season={season}&standingsTypes=regularSeason&hydrate=team"
)


def fetch_json(url: str) -> Any:
    """Use normal request defaults first, then the approved fallback UA."""
    last_error: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        for attempt in range(3):
            try:
                request = Request(url, headers=headers)
                with urlopen(request, timeout=45) as response:
                    return json.load(response)
            except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
                last_error = exc
                if attempt < 2:
                    time.sleep(2**attempt)
        if headers:
            break
    raise RuntimeError(f"Could not fetch pitching data: {last_error}")


def number(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def innings_value(value: Any) -> float:
    """Convert FanGraphs' baseball notation (143.2 = 143 2/3) to innings."""
    text = str(value or 0)
    whole, _, remainder = text.partition(".")
    outs = int(whole) * 3 + int((remainder or "0")[:1])
    return outs / 3


def innings_display(value: Any) -> str:
    text = str(value or 0)
    if "." not in text:
        return f"{text}.0"
    whole, remainder = text.split(".", 1)
    return f"{whole}.{(remainder or '0')[0]}"


def role_for(row: dict[str, Any]) -> str:
    games = int(number(row.get("G")))
    starts = int(number(row.get("GS")))
    relief_ip = number(row.get("Relief-IP"))
    saves = int(number(row.get("SV")))
    holds = int(number(row.get("HLD")))
    if starts >= 5 and relief_ip >= 12:
        return "Swingman"
    if starts >= 5 or (starts and starts >= games / 2):
        return "Starter"
    if saves >= 10:
        return "Closer"
    if holds >= 10:
        return "Setup"
    return "Reliever"


def games_played(payload: dict[str, Any]) -> int:
    for record in payload.get("records", []):
        for team in record.get("teamRecords", []):
            if (team.get("team") or {}).get("id") == BOS:
                return int(team.get("wins", 0)) + int(team.get("losses", 0))
    raise RuntimeError("Could not find Boston's games played in MLB standings")


def rounded(value: float, places: int = 1) -> float:
    return round(value, places)


def build_feed(
    projections: list[dict[str, Any]],
    actual_payload: dict[str, Any],
    standings_payload: dict[str, Any],
    season: int,
) -> dict[str, Any]:
    actual_rows = actual_payload.get("data") or []
    if not actual_rows:
        raise RuntimeError("FanGraphs returned no Red Sox pitching rows")

    projection_by_mlb_id = {
        str(row.get("xMLBAMID")): row
        for row in projections
        if row.get("xMLBAMID")
    }
    played = games_played(standings_payload)
    season_fraction = played / 162
    pitchers = []

    for actual in actual_rows:
        mlb_id = str(actual.get("xMLBAMID") or "")
        projection = projection_by_mlb_id.get(mlb_id)
        actual_ip = innings_value(actual.get("IP"))
        actual_war = number(actual.get("WAR"))
        projected_war = number(projection.get("WAR")) if projection else 0
        projected_ip = number(projection.get("IP")) if projection else 0
        forecast_war_to_date = projected_war * season_fraction
        forecast_ip_to_date = projected_ip * season_fraction

        pitchers.append(
            {
                "id": int(number(actual.get("xMLBAMID"))),
                "name": actual.get("PlayerName") or "Red Sox pitcher",
                "throws": actual.get("Throws") or "—",
                "role": role_for(actual),
                "games": int(number(actual.get("G"))),
                "starts": int(number(actual.get("GS"))),
                "saves": int(number(actual.get("SV"))),
                "holds": int(number(actual.get("HLD"))),
                "actual": {
                    "ip": innings_display(actual.get("IP")),
                    "ip_value": rounded(actual_ip, 3),
                    "war": rounded(actual_war, 2),
                    "era": rounded(number(actual.get("ERA")), 2),
                    "fip": rounded(number(actual.get("FIP")), 2),
                    "k_minus_bb_pct": rounded(number(actual.get("K-BB%")) * 100, 1),
                },
                "forecast": None
                if not projection
                else {
                    "ip": rounded(projected_ip, 1),
                    "war": rounded(projected_war, 2),
                    "era": rounded(number(projection.get("ERA")), 2),
                    "fip": rounded(number(projection.get("FIP")), 2),
                    "k_minus_bb_pct": rounded(number(projection.get("K-BB%")) * 100, 1),
                    "team_at_fetch": projection.get("Team") or None,
                },
                "forecast_to_date": {
                    "ip": rounded(forecast_ip_to_date, 1),
                    "war": rounded(forecast_war_to_date, 2),
                },
                "war_gap": rounded(actual_war - forecast_war_to_date, 2),
            }
        )

    pitchers.sort(key=lambda pitcher: pitcher["actual"]["war"], reverse=True)
    total_ip = sum(pitcher["actual"]["ip_value"] for pitcher in pitchers)
    total_er = sum(number(row.get("ER")) for row in actual_rows)
    actual_war = sum(pitcher["actual"]["war"] for pitcher in pitchers)
    forecast_war = sum(pitcher["forecast_to_date"]["war"] for pitcher in pitchers)
    for pitcher in pitchers:
        pitcher["innings_share_pct"] = rounded(
            pitcher["actual"]["ip_value"] / total_ip * 100 if total_ip else 0,
            1,
        )

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "season": season,
        "team": "Boston Red Sox",
        "games_played": played,
        "season_fraction": rounded(season_fraction, 4),
        "method": (
            "Actual FanGraphs pitching WAR is compared with preseason Steamer WAR "
            "prorated to Boston's games played."
        ),
        "sources": {
            "actual": "FanGraphs Major League Leaderboards",
            "forecast": "FanGraphs Steamer preseason projections",
            "games_played": "MLB Stats API",
            "actual_url": "https://www.fangraphs.com/leaders/major-league",
            "forecast_url": "https://www.fangraphs.com/projections",
        },
        "team_summary": {
            "actual_war": rounded(actual_war, 1),
            "forecast_war_to_date": rounded(forecast_war, 1),
            "war_gap": rounded(actual_war - forecast_war, 1),
            "innings": rounded(total_ip, 1),
            "era": rounded(total_er / total_ip * 9 if total_ip else 0, 2),
        },
        "pitchers": pitchers,
    }


def feed_changed(feed: dict[str, Any]) -> bool:
    try:
        current = json.loads(OUTPUT_PATH.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return True
    keys = ("season", "games_played", "team_summary", "pitchers")
    return any(current.get(key) != feed.get(key) for key in keys)


def main() -> None:
    season = datetime.now(timezone.utc).year
    projections = fetch_json(PROJECTIONS_API)
    actual = fetch_json(ACTUAL_API.format(season=season, team=FANGRAPHS_BOS))
    standings = fetch_json(STANDINGS_API.format(league=AL, season=season))
    if not isinstance(projections, list):
        raise RuntimeError("FanGraphs returned an unexpected projections response")
    feed = build_feed(projections, actual, standings, season)
    if not feed_changed(feed):
        print(f"No pitching changes; kept {OUTPUT_PATH}")
        return
    OUTPUT_PATH.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote Above the Forecast pitching data to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
