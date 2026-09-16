#!/usr/bin/env python3
"""Validate the generated, shared player-career records used by the native card."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from team_registry import all_teams, data_directory


ROOT = Path(__file__).resolve().parents[1]
CAREER_DIRECTORY = ROOT / "data" / "player-careers"


def player_path(team: dict) -> Path:
    root = ROOT / "data" if team["legacy_root_data"] else data_directory(team)
    return root / "players.json"


def rows_are_chronological(rows: list[dict]) -> bool:
    expected = sorted(rows, key=lambda row: (row["season"], row["row_type"] == "subtotal", row["team"]))
    return rows == expected


def validate_player(player: dict) -> None:
    path = CAREER_DIRECTORY / f"{player['id']}.json"
    assert path.exists(), f"missing detailed career record for {player['name']}"
    record = json.loads(path.read_text())
    assert record["schema_version"] == 1
    assert record["player_id"] == player["id"]
    assert record["status"] in {"available", "unavailable", "temporarily_unavailable"}
    for group in ("batting", "pitching"):
        rows = record[group]
        assert rows_are_chronological(rows), f"{player['name']} {group} rows are not chronological"
        assert len({row["id"] for row in rows}) == len(rows), f"duplicate {group} row for {player['name']}"
        for row in rows:
            assert row["row_type"] in {"team_stint", "subtotal"}
            assert row["team"] and row["level"]
            if group == "pitching" and row.get("innings_outs") is not None:
                assert row["innings_outs"] >= 0
            if group == "batting" and not any(
                row.get(key) for key in ("at_bats", "hits", "walks", "runs_batted_in", "home_runs", "stolen_bases")
            ):
                assert all(row.get(key) is None for key in ("average", "on_base_percentage", "slugging_percentage", "ops"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team", action="append", default=[])
    args = parser.parse_args()
    teams = all_teams()
    if args.team:
        requested = {value.lower() for value in args.team}
        teams = [team for team in teams if requested & {team["id"].lower(), team["api_key"].lower(), team["abbreviation"].lower()}]
        assert len(teams) == len(requested), "unknown or duplicate team key"
    seen: set[int] = set()
    for team in teams:
        feed = json.loads(player_path(team).read_text())
        for player in feed["players"]:
            if player["id"] not in seen:
                validate_player(player)
                seen.add(player["id"])
    print(f"Player career checks passed for {len(seen)} profiles across {len(teams)} teams.")


if __name__ == "__main__":
    main()
