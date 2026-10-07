#!/usr/bin/env python3
"""Regression tests for team refresh failure isolation."""

from __future__ import annotations

import unittest
from unittest.mock import call, patch

import fetch_team_data


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
            with self.assertRaisesRegex(RuntimeError, "No completed Orioles game"):
                fetch_team_data.recent_game_feed(self.team)
        fetch.assert_called_once()


class FailureIsolationTests(unittest.TestCase):
    def test_keep_going_attempts_every_team_then_fails(self) -> None:
        teams = [
            {"full_name": "First Team"},
            {"full_name": "Second Team"},
        ]
        with (
            patch.object(fetch_team_data, "expansion_teams", return_value=teams),
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
