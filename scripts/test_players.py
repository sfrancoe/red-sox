#!/usr/bin/env python3
"""Schema and licensing invariants for the open player directory."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from team_registry import all_teams, data_directory


ROOT = Path(__file__).resolve().parents[1]
IOS_PLAYER_PATH = ROOT / "ios" / "Hub Ball" / "Hub Ball" / "players.json"
POSITION_GROUPS = {"Pitcher", "Catcher", "Infielder", "Outfielder", "Hitter"}
BANNED_TEXT = ("statsapi.mlb.com", "mlbstatic.com", '"photo"', "SportsDataIO")


def player_path(team: dict) -> Path:
    root = ROOT / "data" if team["legacy_root_data"] else data_directory(team)
    return root / "players.json"


def validate(team: dict) -> int:
    feed = json.loads(player_path(team).read_text())
    if team["api_key"] == "redsox":
        ios_feed = json.loads(IOS_PLAYER_PATH.read_text())
        assert feed == ios_feed, "the app's bundled Red Sox player snapshot is stale"
    players = feed["players"]
    assert feed["roster_type"] == "open-current-roster"
    assert feed["team"] == {"id": team["mlb_id"], "name": team["full_name"]}
    assert 25 <= len(players) <= 65, f"unexpected {team['api_key']} roster size"
    assert feed["player_count"] == len(players)
    assert feed["active_count"] == sum(player["is_active_roster"] for player in players)
    assert len({player["id"] for player in players}) == len(players)
    assert "CC0" in feed["source"]["license"]
    assert "CC BY-SA" in feed["source"]["license"]
    assert "Retrosheet" in feed["source"]["license"]
    assert feed["source"]["stats_through"] == 2025
    assert "obtained free of charge" in feed["source"]["stats_attribution"]

    wikidata_matches = 0
    for player in players:
        assert player["name"] and player["position"]["group"] in POSITION_GROUPS
        assert player["roster_status"] and isinstance(player["teams"], list)
        assert player["wikipedia_url"]
        if player["wikidata_id"]:
            wikidata_matches += 1
            assert player["source_url"]
        assert "career_stats" in player and player["career_stats"]["through_season"] == 2025
        assert player["career_stats"]["status"] in {
            "available", "not_in_2025_release", "temporarily_unavailable",
        }
    assert wikidata_matches >= int(len(players) * 0.7), f"too few {team['api_key']} Wikidata matches"

    available = [player for player in players if player["career_stats"]["status"] == "available"]
    if available:
        assert any(
            player["career_stats"]["batting"] or player["career_stats"]["pitching"]
            for player in available
        )

    serialized = json.dumps(feed)
    for text in BANNED_TEXT:
        assert text not in serialized, f"player feed contains banned source or field: {text}"
    return len(players)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team", action="append", default=[])
    args = parser.parse_args()
    teams = all_teams()
    if args.team:
        requested = {key.lower() for key in args.team}
        teams = [
            team for team in teams
            if requested & {
                team["id"].lower(), team["api_key"].lower(),
                team["abbreviation"].lower(), team["data_directory"].lower(),
            }
        ]
        assert len(teams) == len(requested), "unknown or duplicate team key"
    total = 0
    for team in teams:
        count = validate(team)
        total += count
        print(f"{team['full_name']}: {count} open player profiles")
    print(f"Open player data checks passed for {total} profiles across {len(teams)} teams.")


if __name__ == "__main__":
    main()
