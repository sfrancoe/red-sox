#!/usr/bin/env python3
"""Deterministic checks for playoff-history qualification and ranking rules."""

import json
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from fetch_playoff_history import build_categories, innings_to_outs, should_write_snapshot


def player(player_id: int, name: str, position_type: str = "Two-Way Player") -> dict:
    return {
        "playerId": player_id,
        "name": name,
        "teamId": 111,
        "teamAbbreviation": "BOS",
        "positionType": position_type,
    }


players = [player(index, f"Player {index:02d}") for index in range(1, 14)]
stats = {}
for index, item in enumerate(players, 1):
    stats[item["playerId"]] = {
        "hitting": {
            "gamesPlayed": 8,
            "plateAppearances": 20,
            "ops": f".{500 + index:03d}",
            "avg": f".{200 + index:03d}",
            "homeRuns": index,
            "rbi": index * 2,
        },
        "pitching": {
            "gamesPlayed": 5,
            "gamesPitched": 5,
            "inningsPitched": "15.0",
            "wins": index,
            "whip": f"{2 - index / 100:.2f}",
            "era": f"{6 - index / 10:.2f}",
            "saves": index,
            "strikeOuts": index * 3,
        },
    }

# Exclude a tiny sample even when its rate would otherwise lead every board.
stats[1]["hitting"].update(gamesPlayed=2, plateAppearances=7, ops="2.000", avg=".900")
stats[1]["pitching"].update(gamesPlayed=2, gamesPitched=2, inningsPitched="3.2", whip="0.01", era="0.01")

categories = build_categories(players, stats)
hitting = {item["key"]: item for item in categories["hitting"]}
pitching = {item["key"]: item for item in categories["pitching"]}

assert innings_to_outs("15.0") == 45
assert innings_to_outs("10.2") == 32
assert hitting["ops"]["best"][0]["playerId"] == 13
assert hitting["ops"]["worst"][0]["playerId"] == 2
assert pitching["era"]["best"][0]["playerId"] == 13
assert pitching["era"]["worst"][0]["playerId"] == 2
assert pitching["whip"]["best"][0]["playerId"] == 13
assert pitching["whip"]["worst"][0]["playerId"] == 2
assert len(hitting["rbi"]["best"]) == 10
assert all(entry["playerId"] != 1 for entry in pitching["era"]["best"])
assert pitching["wins"]["best"][0]["value"] == 13

# A pitcher's misleading MLB hitting games-played total cannot qualify him as a hitter.
pitcher = player(99, "Pitcher Hitting Artifact", "Pitcher")
pitcher_stats = {
    "hitting": {"gamesPlayed": 40, "plateAppearances": 1, "ops": ".000", "avg": ".000", "homeRuns": 0, "rbi": 0},
    "pitching": {"gamesPitched": 20, "inningsPitched": "18.0", "wins": 1, "whip": "1.10", "era": "2.50", "saves": 2, "strikeOuts": 22},
}
artifact_categories = build_categories(players + [pitcher], {**stats, 99: pitcher_stats})
assert all(entry["playerId"] != 99 for category in artifact_categories["hitting"] for entry in category["worst"])
assert any(entry["playerId"] == 99 for category in artifact_categories["pitching"] for entry in category["best"])

with tempfile.TemporaryDirectory() as directory:
    output = Path(directory) / "snapshot.json"
    locked = {"status": "locked", "generatedAt": datetime.now(timezone.utc).isoformat(), "teams": [1]}
    output.write_text(json.dumps(locked))
    assert not should_write_snapshot(output, locked)
    assert should_write_snapshot(output, {**locked, "teams": [1, 2]})
    assert should_write_snapshot(output, {**locked, "status": "finalizing"})

print("playoff history qualification and ranking tests passed")
