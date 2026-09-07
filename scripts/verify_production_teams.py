#!/usr/bin/env python3
"""Verify representative production payloads for every Hub Ball team."""

from __future__ import annotations

import argparse
import json
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

from team_registry import all_teams


FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"


def fetch_json(url: str) -> dict[str, Any]:
    last_error: Exception | None = None
    for headers in ({"Accept": "application/json"}, {
        "Accept": "application/json", "User-Agent": FALLBACK_USER_AGENT,
    }):
        for attempt in range(2):
            try:
                with urlopen(Request(url, headers=headers), timeout=25) as response:
                    if response.status != 200:
                        raise RuntimeError(f"HTTP {response.status}")
                    return json.load(response)
            except (HTTPError, URLError, TimeoutError, json.JSONDecodeError, RuntimeError) as exc:
                last_error = exc
                if attempt == 0:
                    time.sleep(1)
    raise RuntimeError(f"{url}: {last_error}")


def data_url(origin: str, team: dict[str, Any], file_name: str) -> str:
    prefix = "" if team["legacy_root_data"] else f"{team['data_directory']}/"
    return f"{origin}/api/data/{prefix}{file_name}"


def verify_team(origin: str, team: dict[str, Any]) -> list[str]:
    checked = []
    standings = fetch_json(data_url(origin, team, "standings.json"))
    rows = [row for division in standings["divisions"] for row in division["teams"]]
    favorites = [row for row in rows if row.get("is_favorite", row.get("is_red_sox", False))]
    assert len(favorites) == 1 and favorites[0]["id"] == team["mlb_id"]
    checked.append("standings")

    schedule = fetch_json(data_url(origin, team, "schedule.json"))
    assert schedule["team"] == team["short_name"]
    checked.append("schedule")

    recent = fetch_json(data_url(origin, team, "recent-game.json"))
    assert team["mlb_id"] in {recent["away"]["id"], recent["home"]["id"]}
    checked.append("recent-game")

    pitching = fetch_json(data_url(origin, team, "pitching.json"))
    assert pitching["team"] == team["full_name"] and pitching["pitchers"]
    checked.append("pitching")

    seasons = fetch_json(data_url(origin, team, "seasons.json"))
    latest = seasons[max(seasons)]
    assert latest["war_leaders"] and latest["batting_leaders"] and latest["pitching_leaders"]
    checked.append("leaders")

    source = team["news_sources"][0]
    news = fetch_json(data_url(origin, team, f"{source['key']}.json"))
    assert news["source"] and news["articles"]
    checked.append("news")

    posts = fetch_json(f"{origin}/api/x-posts?team={quote(team['api_key'])}")
    assert posts["source"] == "X" and posts["recent"]
    checked.append("x-posts")
    return checked


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--origin", default="https://red-sox.netlify.app")
    args = parser.parse_args()
    origin = args.origin.rstrip("/")
    failures = []
    for team in all_teams():
        try:
            checked = verify_team(origin, team)
            print(f"{team['full_name']}: {', '.join(checked)} OK")
        except (AssertionError, KeyError, RuntimeError) as exc:
            failures.append((team["full_name"], str(exc) or "identity assertion failed"))
            print(f"{team['full_name']}: FAILED ({failures[-1][1]})")
    if failures:
        raise SystemExit(f"{len(failures)} team(s) failed production verification")
    print("All 30 production team endpoints are healthy and team-specific")


if __name__ == "__main__":
    main()
