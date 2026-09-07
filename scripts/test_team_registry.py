#!/usr/bin/env python3
"""Validate the canonical 30-team Hub Ball registry."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "config" / "mlb-teams.json"
EXPECTED_EXISTING = {
    "boston": (111, "redsox", "redsox", True),
    "new-york": (147, "yankees", "yankees", True),
    "new-york-mets": (121, "mets", "mets", True),
    "tampa-bay": (139, "rays", "rays", True),
}


def unique(teams: list[dict], key: str) -> None:
    values = [team[key] for team in teams]
    assert len(values) == len(set(values)), f"duplicate {key}"


def main() -> None:
    document = json.loads(REGISTRY.read_text())
    teams = document["teams"]
    assert document["schema_version"] == 1
    assert len(teams) == 30
    for key in (
        "id", "swift_case", "mlb_id", "full_name", "abbreviation", "api_key",
        "data_directory", "x_handle",
    ):
        unique(teams, key)

    by_id = {team["id"]: team for team in teams}
    assert set(EXPECTED_EXISTING) <= set(by_id)
    assert sum(team["features"]["native_picker"] for team in teams) == 4
    for team_id, expected in EXPECTED_EXISTING.items():
        team = by_id[team_id]
        actual = (
            team["mlb_id"], team["api_key"], team["data_directory"],
            team["features"]["native_picker"],
        )
        assert actual == expected, f"existing team changed: {team_id}"

    feature_keys = {
        "native_picker", "home", "recent_game", "schedule", "standings",
        "pitching", "leaders", "news", "x_posts", "players", "stories",
    }
    color_keys = {"primary", "secondary", "background", "ink", "border", "positive"}
    for team in teams:
        assert team["league"] in {"AL", "NL"}
        assert team["division"] in {"East", "Central", "West"}
        assert set(team["features"]) == feature_keys
        assert color_keys <= set(team["colors"])
        assert team["news_sources"]
        assert all(source["url"].startswith("https://") for source in team["news_sources"])

    subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "generate_team_registry.py"), "--check"],
        check=True,
    )
    print("30-team registry is valid and generated views are current")


if __name__ == "__main__":
    main()
