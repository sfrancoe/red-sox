#!/usr/bin/env python3
"""Regression tests for team refresh failure isolation."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import call, patch

import fetch_team_data
import team_registry


class RecentGameSelectionTests(unittest.TestCase):
    team = {"mlb_id": 110, "short_name": "Orioles"}

    @staticmethod
    def game(game_pk: int, day: int, code: str) -> dict:
        return {
            "gamePk": game_pk, "gameDate": f"2026-09-{day:02d}T17:05:00Z",
            "status": {"abstractGameState": "Final", "codedGameState": code},
        }

    def test_skips_cancelled_and_postponed_games_marked_final(self) -> None:
        schedule = {"dates": [{"games": [
            self.game(823491, 25, "F"),
            self.game(823492, 26, "D"),
            self.game(823490, 27, "C"),
        ]}]}
        # Stop at the selected game's request, before any real network access.
        with patch.object(fetch_team_data, "fetch_json", side_effect=[
            schedule, RuntimeError("selected game requested"),
        ]) as fetch:
            with self.assertRaisesRegex(RuntimeError, "selected game requested"):
                fetch_team_data.recent_game_feed(self.team)
        self.assertEqual(fetch.call_args_list[1], call(
            fetch_team_data.LIVE_API.format(game_pk=823491),
        ))

    def test_no_completed_game_when_every_final_was_cancelled_or_postponed(self) -> None:
        schedule = {"dates": [{"games": [
            self.game(823492, 26, "D"), self.game(823490, 27, "C"),
        ]}]}
        with patch.object(fetch_team_data, "fetch_json", return_value=schedule) as fetch:
            with self.assertRaisesRegex(fetch_team_data.NoRecentGameError, "No completed Orioles game"):
                fetch_team_data.recent_game_feed(self.team)
        fetch.assert_called_once()


class OffseasonRecentGameTests(unittest.TestCase):
    team = {"full_name": "Baltimore Orioles", "short_name": "Orioles", "mlb_id": 110,
            "data_directory": "orioles"}

    def run_recent_game(self, directory: Path) -> None:
        with (
            patch.object(fetch_team_data, "data_directory", return_value=directory),
            patch.object(fetch_team_data, "fetch_json", return_value={"dates": []}),
        ):
            fetch_team_data.fetch_team(self.team, ["recent-game"])

    def test_keeps_last_recap_when_no_game_in_lookback_window(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            snapshot = Path(directory) / "recent-game.json"
            snapshot.write_text(json.dumps({"game_pk": 823489}))
            self.run_recent_game(Path(directory))
            self.assertEqual(json.loads(snapshot.read_text()), {"game_pk": 823489})

    def test_still_fails_when_there_is_no_recap_to_keep(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(fetch_team_data.NoRecentGameError):
                self.run_recent_game(Path(directory))


class RecapWordingTests(unittest.TestCase):
    """Recaps name the team's own city (the old Rays copy said "New York")."""

    @staticmethod
    def club(side: str, team_id: int, name: str, runs: int) -> dict:
        return {"side": side, "id": team_id, "club_name": name, "runs": runs, "hits": 8,
                "errors": 0, "batting": [], "pitching": [], "team_batting": {}}

    def test_comeback_recap_uses_registry_city_and_name(self) -> None:
        rays = team_registry.team_by_key("rays")
        favorite = self.club("away", rays["mlb_id"], "Rays", 5)
        opponent = self.club("home", 147, "Yankees", 3)
        scoring = [
            {"inning_num": 1, "batter": "Aaron Judge", "event": "Home Run", "rbi": 3,
             "away_score": 0, "home_score": 3},
            {"inning_num": 6, "batter": "Junior Caminero", "event": "Home Run", "rbi": 2,
             "away_score": 2, "home_score": 3},
            {"inning_num": 8, "batter": "Yandy Díaz", "event": "Double", "rbi": 3,
             "away_score": 5, "home_score": 3},
        ]
        summary = fetch_team_data.build_summary(rays, favorite, opponent, "Yankee Stadium", scoring)
        self.assertEqual(
            summary,
            "The Rays erased a 3-run deficit to beat the Yankees, 5–3, at Yankee Stadium. "
            "Tampa Bay trailed 3–0 before Junior Caminero’s two-run home run in the 6th "
            "cut the deficit to one.",
        )
        self.assertNotIn("New York", summary)


class RegistrySplitTests(unittest.TestCase):
    def test_only_boston_keeps_its_own_game_data_scripts(self) -> None:
        keys = {team["api_key"] for team in team_registry.shared_game_data_teams()}
        self.assertEqual(len(keys), 29)
        self.assertNotIn("redsox", keys)
        self.assertTrue({"yankees", "mets", "rays"} <= keys)

    def test_direct_newspaper_teams_stay_off_the_shared_news_fetcher(self) -> None:
        keys = {team["api_key"] for team in team_registry.shared_news_teams()}
        self.assertEqual(len(keys), 26)
        self.assertFalse(keys & {"redsox", "yankees", "mets", "rays"})


class FailureIsolationTests(unittest.TestCase):
    def test_keep_going_attempts_every_team_then_fails(self) -> None:
        teams = [
            {"full_name": "First Team"},
            {"full_name": "Second Team"},
        ]
        with (
            patch.object(fetch_team_data, "shared_game_data_teams", return_value=teams),
            patch.object(
                fetch_team_data,
                "fetch_team",
                side_effect=(RuntimeError("blocked"), None),
            ) as fetch,
            patch("sys.argv", ["fetch_team_data.py", "--section", "pitching", "--keep-going"]),
        ):
            with self.assertRaisesRegex(RuntimeError, "Refresh failed for 1 team"):
                fetch_team_data.main()

        self.assertEqual(
            fetch.call_args_list,
            [call(teams[0], ["pitching"]), call(teams[1], ["pitching"])],
        )


if __name__ == "__main__":
    unittest.main()
