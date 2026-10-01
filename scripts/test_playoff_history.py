#!/usr/bin/env python3
"""Deterministic checks for season and career postseason statistics."""

import json
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from fetch_playoff_history import (
    build_categories,
    extract_postseason_stats,
    innings_to_outs,
    parse_number,
    should_write_snapshot,
)


def player(player_id: int, position_type: str = "Two-Way Player") -> dict:
    return {
        "playerId": player_id,
        "name": f"Player {player_id:02d}",
        "teamId": 111,
        "teamAbbreviation": "BOS",
        "league": "AL",
        "positionType": position_type,
    }


def hitting(ops: str, plate_appearances: int) -> dict:
    return {
        "gamesPlayed": 1,
        "plateAppearances": plate_appearances,
        "ops": ops,
        "avg": ".300",
        "homeRuns": 0,
        "rbi": 0,
    }


def pitching(innings_pitched: str) -> dict:
    return {
        "gamesPitched": 1,
        "inningsPitched": innings_pitched,
        "wins": 0,
        "whip": "1.50",
        "era": "3.00",
        "saves": 0,
        "strikeOuts": 2,
    }


person = {
    "stats": [
        {"type": {"displayName": "career"}, "group": {"displayName": "hitting"},
         "splits": [{"stat": hitting(".900", 120)}]},
        {"type": {"displayName": "season"}, "group": {"displayName": "hitting"},
         "splits": [{"season": "2025", "stat": hitting(".800", 50)},
                    {"season": "2026", "stat": hitting("1.250", 4)}]},
    ]
}
extracted = extract_postseason_stats(person, 2026)
assert extracted["career"]["hitting"]["ops"] == ".900"
assert extracted["season"]["hitting"]["ops"] == "1.250"
assert extract_postseason_stats(person, 2027)["season"] == {}
assert innings_to_outs("15.0") == 45
assert innings_to_outs("10.2") == 32
assert parse_number("inf") is None

players = [player(index) for index in range(1, 14)]
stats = {
    item["playerId"]: {
        "career": {"hitting": hitting(f".{500 + item['playerId']:03d}", 20)},
        "season": {},
    }
    for item in players
}
stats[1]["season"]["hitting"] = hitting("1.250", 1)
stats[2]["career"]["hitting"] = hitting(".000", 0)
stats[2]["season"]["hitting"] = hitting(".750", 2)
stats[3]["career"]["pitching"] = pitching("0.0")
stats[4]["career"]["pitching"] = pitching("1.2")
stats[4]["season"]["pitching"] = pitching("0.0")

categories = build_categories(players, stats)
ops = next(item for item in categories["hitting"] if item["key"] == "ops")
by_id = {entry["playerId"]: entry for entry in ops["entries"]}
assert len(by_id) == 13  # The feed keeps the full sortable list, beyond the old top ten.
assert by_id[1]["season"]["value"] == 1.25  # One-game 2026 samples are visible.
assert by_id[1]["career"]["value"] == 0.501
assert by_id[2]["career"] is None  # No batting value without a plate appearance.
assert by_id[2]["season"]["value"] == 0.75

era = next(item for item in categories["pitching"] if item["key"] == "era")
wins = next(item for item in categories["pitching"] if item["key"] == "wins")
assert [entry["playerId"] for entry in era["entries"]] == [4]
assert [entry["playerId"] for entry in wins["entries"]] == [3, 4]
assert era["entries"][0]["season"] is None
assert era["higherIsBetter"] is False

# Pitcher hitting artifacts and position players' pitching blocks stay out of the table.
pitcher = player(99, "Pitcher")
position_player = player(100, "Outfielder")
artifact_stats = {
    **stats,
    99: {"career": {"hitting": hitting("2.000", 1), "pitching": pitching("2.0")}},
    100: {"career": {"pitching": pitching("2.0")}},
}
artifact_categories = build_categories(players + [pitcher, position_player], artifact_stats)
assert all(entry["playerId"] != 99 for category in artifact_categories["hitting"] for entry in category["entries"])
assert all(entry["playerId"] != 100 for category in artifact_categories["pitching"] for entry in category["entries"])

with tempfile.TemporaryDirectory() as directory:
    output = Path(directory) / "snapshot.json"
    locked = {"status": "locked", "generatedAt": datetime.now(timezone.utc).isoformat(), "teams": [1]}
    output.write_text(json.dumps(locked))
    assert not should_write_snapshot(output, locked)
    assert should_write_snapshot(output, {**locked, "teams": [1, 2]})
    assert should_write_snapshot(output, {**locked, "status": "finalizing"})

print("playoff season and career statistics tests passed")
