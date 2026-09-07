"""Read and resolve the canonical Hub Ball MLB team registry."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "config" / "mlb-teams.json"
LEGACY_TEAM_KEYS = {"redsox", "yankees", "mets", "rays"}


def all_teams() -> list[dict[str, Any]]:
    return json.loads(REGISTRY_PATH.read_text())["teams"]


def team_by_key(key: str) -> dict[str, Any]:
    normalized = key.strip().lower()
    for team in all_teams():
        if normalized in {
            team["id"].lower(), team["api_key"].lower(),
            team["abbreviation"].lower(), team["data_directory"].lower(),
        }:
            return team
    raise KeyError(f"Unknown MLB team: {key}")


def data_directory(team: dict[str, Any]) -> Path:
    return ROOT / "data" / team["data_directory"]


def expansion_teams() -> list[dict[str, Any]]:
    return [team for team in all_teams() if team["api_key"] not in LEGACY_TEAM_KEYS]
