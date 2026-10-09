#!/usr/bin/env python3
"""Guard: every team refreshes through the shared registry fetchers.

Team-named scripts (`fetch_<team>_*.py`) and workflows (`refresh-<team>-*.yml`)
are how the first four teams were built before the 30-team registry. They are
being retired one step at a time; this test stops new ones from appearing and
stops the legacy sets in team_registry.py from growing.
"""

from __future__ import annotations

import unittest
from pathlib import Path

import team_registry


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
WORKFLOWS = ROOT / ".github" / "workflows"

# Remaining exceptions, each owned by a legacy set in team_registry.py.
# Boston's own game-data scripts are unprefixed (fetch_schedule.py etc.), so
# they are covered by LEGACY_GAME_DATA_KEYS rather than by file names here.
ALLOWED_NEWS_SCRIPTS = {f"fetch_{key}_news.py" for key in ("yankees", "mets", "rays")}
ALLOWED_NEWS_WORKFLOWS = {f"refresh-{key}-news.yml" for key in ("yankees", "mets", "rays")}


class TeamSpecificFetcherTests(unittest.TestCase):
    def team_tokens(self) -> set[str]:
        return {
            token
            for team in team_registry.all_teams()
            for token in (team["api_key"], team["data_directory"])
        }

    def test_no_team_named_fetch_scripts(self) -> None:
        found = {
            path.name for token in self.team_tokens()
            for path in SCRIPTS.glob(f"fetch_{token}_*.py")
        }
        self.assertEqual(found - ALLOWED_NEWS_SCRIPTS, set(),
                         "Add teams through config/mlb-teams.json and the shared fetchers")

    def test_no_team_named_refresh_workflows(self) -> None:
        found = {
            path.name for token in self.team_tokens()
            for path in WORKFLOWS.glob(f"refresh-{token}-*.yml")
        }
        self.assertEqual(found - ALLOWED_NEWS_WORKFLOWS, set(),
                         "Refresh teams through the shared refresh-mlb-team-*.yml workflows")

    def test_news_exceptions_belong_to_legacy_news_teams(self) -> None:
        for name in ALLOWED_NEWS_SCRIPTS | ALLOWED_NEWS_WORKFLOWS:
            key = name.removeprefix("fetch_").removeprefix("refresh-").split("_")[0].split("-")[0]
            self.assertIn(key, team_registry.LEGACY_NEWS_KEYS, name)

    def test_legacy_sets_only_shrink(self) -> None:
        self.assertLessEqual(team_registry.LEGACY_GAME_DATA_KEYS, {"redsox"})
        self.assertLessEqual(team_registry.LEGACY_NEWS_KEYS, {"redsox", "yankees", "mets", "rays"})


if __name__ == "__main__":
    unittest.main()
