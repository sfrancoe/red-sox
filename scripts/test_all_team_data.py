#!/usr/bin/env python3
"""Validate generated team identity and every native-consumed feed."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.parse import urlparse

from team_registry import all_teams, data_directory, team_by_key


ROOT = Path(__file__).resolve().parents[1]


def load(root: Path, name: str):
    return json.loads((root / name).read_text())


def validate(team: dict) -> None:
    root = ROOT / "data" if team["legacy_root_data"] else data_directory(team)
    schedule = load(root, "schedule.json")
    assert schedule["team"] == team["short_name"]
    assert schedule["games"]
    assert all(game["game_pk"] for game in schedule["games"])

    recent = load(root, "recent-game.json")
    assert team["mlb_id"] in {recent["away"]["id"], recent["home"]["id"]}
    assert team["short_name"] in recent["summary"]
    assert recent["innings"] and recent["away"]["batting"] and recent["home"]["batting"]

    standings = load(root, "standings.json")
    teams = [row for division in standings["divisions"] for row in division["teams"]]
    favorites = [row for row in teams if row.get("is_favorite", row.get("is_red_sox", False))]
    assert len(favorites) == 1 and favorites[0]["id"] == team["mlb_id"]
    expected_league = "American League" if team["league"] == "AL" else "National League"
    assert standings["league"] == expected_league

    pitching = load(root, "pitching.json")
    assert pitching["team"] == team["full_name"]
    assert pitching["pitchers"] and pitching["games_played"] > 0
    assert all(row["id"] and row["name"] for row in pitching["pitchers"])

    seasons = load(root, "seasons.json")
    current = seasons[max(seasons)]
    assert current["war_leaders"] and current["batting_leaders"] and current["pitching_leaders"]
    assert len(current["diff"]) == len(current["seq"]) == current["end_game"]
    assert load(root, "meta.json")["team_id"] == team["mlb_id"]

    for source in team["news_sources"]:
        feed = load(root, f"{source['key']}.json")
        assert feed["articles"], source["key"]
        source_host = urlparse(source["url"]).netloc.removeprefix("www.")
        urls = [article["url"] for article in feed["articles"]]
        assert len(urls) == len(set(urls)), f"duplicate {team['api_key']}/{source['key']} article"
        assert all(source_host in urlparse(url).netloc.removeprefix("www.") for url in urls)
        assert all(article["title"] for article in feed["articles"])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team", action="append", default=[])
    args = parser.parse_args()
    teams = [team_by_key(key) for key in args.team] if args.team else all_teams()
    for team in teams:
        validate(team)
        print(f"{team['full_name']}: OK")
    assert len({team["data_directory"] for team in all_teams()}) == 30
    assert len({team["api_key"] for team in all_teams()}) == 30
    print(f"Validated {len(teams)} team data sets")


if __name__ == "__main__":
    main()
