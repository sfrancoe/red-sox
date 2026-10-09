"""Read and resolve the canonical Hub Ball MLB team registry."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "config" / "mlb-teams.json"

# Teams still refreshed by their own team-named scripts instead of the shared
# registry fetchers. Shrink these sets as each team migrates; never add to them.
# Boston keeps its own game-data scripts until its root `data/*.json` paths are
# retired from shipped app builds.
LEGACY_GAME_DATA_KEYS = frozenset({"redsox"})
# Direct newspaper scrapers (fetch_globe_news, fetch_<team>_news, ...) still own
# news for these teams until the shared news fetcher can scrape direct sources.
LEGACY_NEWS_KEYS = frozenset({"redsox", "yankees", "mets", "rays"})


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


def shared_game_data_teams() -> list[dict[str, Any]]:
    """Teams whose schedule, recap, standings, pitching and leaders use shared fetchers."""
    return [team for team in all_teams() if team["api_key"] not in LEGACY_GAME_DATA_KEYS]


def shared_news_teams() -> list[dict[str, Any]]:
    """Teams whose newspaper feeds use the shared news fetcher."""
    return [team for team in all_teams() if team["api_key"] not in LEGACY_NEWS_KEYS]
