#!/usr/bin/env python3
"""Schema and licensing invariants for the open player directory."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLAYER_PATH = ROOT / "data" / "players.json"
IOS_PLAYER_PATH = ROOT / "ios" / "Hub Ball" / "Hub Ball" / "players.json"
POSITION_GROUPS = {"Pitcher", "Catcher", "Infielder", "Outfielder", "Hitter"}
BANNED_TEXT = ("statsapi.mlb.com", "mlbstatic.com", '"photo"', "SportsDataIO")


def main() -> None:
    feed = json.loads(PLAYER_PATH.read_text())
    ios_feed = json.loads(IOS_PLAYER_PATH.read_text())
    assert feed == ios_feed, "the app's bundled player snapshot is stale"
    players = feed["players"]
    assert feed["roster_type"] == "open-current-roster"
    assert 35 <= len(players) <= 60, "unexpected roster size"
    assert feed["player_count"] == len(players)
    assert feed["active_count"] == sum(player["is_active_roster"] for player in players)
    assert len({player["id"] for player in players}) == len(players)
    assert "CC0" in feed["source"]["license"]
    assert "CC BY-SA" in feed["source"]["license"]
    assert "Retrosheet" in feed["source"]["license"]
    assert feed["source"]["stats_through"] == 2025
    assert "obtained free of charge" in feed["source"]["stats_attribution"]

    for player in players:
        assert player["name"] and player["position"]["group"] in POSITION_GROUPS
        assert player["roster_status"] and player["teams"]
        assert player["wikidata_id"], f"missing Wikidata record for {player['name']}"
        assert player["source_url"] and player["wikipedia_url"]
        assert "career_stats" in player and player["career_stats"]["through_season"] == 2025
        assert player["career_stats"]["status"] in {"available", "not_in_2025_release"}

    available = [player for player in players if player["career_stats"]["status"] == "available"]
    assert len(available) >= 30, "too few roster players matched to Retrosheet"
    assert any(player["career_stats"]["batting"] for player in available)
    assert any(player["career_stats"]["pitching"] for player in available)

    serialized = json.dumps(feed)
    for text in BANNED_TEXT:
        assert text not in serialized, f"player feed contains banned source or field: {text}"
    print(f"Open player data checks passed for {len(players)} profiles.")


if __name__ == "__main__":
    main()
