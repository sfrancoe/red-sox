#!/usr/bin/env python3
"""Guard: every team refreshes through the shared registry fetchers.

Team-named scripts (`fetch_<team>_*.py`, `test_<team>_data.py`) and workflows
(`refresh-<team>-*.yml`) are how the first four teams were built before the
30-team registry. All have been retired; this test stops them coming back.
"""

from __future__ import annotations

import unittest
from pathlib import Path

import team_registry


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
WORKFLOWS = ROOT / ".github" / "workflows"

# Boston's original scripts had no team prefix, so they are listed by name.
# fetch_seasons.py stays: it builds the Four Roads / Game 108 story data, not
# team feeds. fetch_x_posts.py stays: Boston's curated X list is a different
# source from the official-account snapshots, not a duplicate pipeline.
RETIRED_UNPREFIXED_SCRIPTS = {
    "fetch_schedule.py", "fetch_recent_game.py", "fetch_standings.py", "fetch_pitching.py",
    "fetch_globe_news.py", "fetch_herald_news.py", "fetch_rss_news.py",
}


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
            for pattern in (f"fetch_{token}_*.py", f"test_{token}_data*.py")
            for path in SCRIPTS.glob(pattern)
        }
        self.assertEqual(found, set(),
                         "Add teams through config/mlb-teams.json and the shared fetchers")

    def test_no_team_named_refresh_workflows(self) -> None:
        found = {
            path.name for token in self.team_tokens()
            for path in WORKFLOWS.glob(f"refresh-{token}-*.yml")
        }
        self.assertEqual(found, set(),
                         "Refresh teams through the shared refresh-mlb-team-*.yml workflows")

    def test_retired_boston_scripts_stay_retired(self) -> None:
        present = {name for name in RETIRED_UNPREFIXED_SCRIPTS if (SCRIPTS / name).exists()}
        self.assertEqual(present, set(), "Boston refreshes through the shared fetchers")

    def test_feeds_live_in_team_folders(self) -> None:
        """Only story data and shared artifacts sit at the data root."""
        root_files = {path.name for path in (ROOT / "data").glob("*.json")}
        self.assertLessEqual(root_files, {"seasons.json", "meta.json", "mlb300-hitters.json"})


if __name__ == "__main__":
    unittest.main()
