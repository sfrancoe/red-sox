#!/usr/bin/env python3
"""Regression tests for team refresh failure isolation."""

from __future__ import annotations

import unittest
from unittest.mock import call, patch

import fetch_team_data


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
