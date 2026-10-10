#!/usr/bin/env python3
"""Regression tests for regular-season and postseason schedule collection."""

from __future__ import annotations

import unittest
from datetime import datetime
from unittest.mock import patch

import fetch_team_data


SEASON_PAYLOAD = {"seasons": [{
    "regularSeasonEndDate": "2026-09-27",
    "seasonEndDate": "2026-10-31",
}]}


class PostseasonDatetime(datetime):
    @classmethod
    def now(cls, tz=None):
        value = cls(2026, 9, 28, 12)
        return value.replace(tzinfo=tz) if tz is not None else value


class AfterPostseasonDatetime(datetime):
    @classmethod
    def now(cls, tz=None):
        value = cls(2026, 11, 1, 12)
        return value.replace(tzinfo=tz) if tz is not None else value


def postseason_payload(team_id: int) -> dict:
    opponent_id = 147 if team_id != 147 else 111
    return {"dates": [{"games": [{
        "gamePk": 849851,
        "gameDate": "2026-09-30T00:00:00Z",
        "gameType": "F",
        "status": {"abstractGameState": "Preview", "detailedState": "Scheduled"},
        "teams": {
            "away": {"team": {"id": team_id, "teamName": "Favorite"}},
            "home": {"team": {"id": opponent_id, "teamName": "Opponent"}},
        },
        "venue": {"name": "Ballpark"},
        "seriesDescription": "AL Wild Card Series",
        "doubleHeader": "N",
        "gameNumber": 1,
    }]}]}


class PostseasonScheduleTests(unittest.TestCase):
    def test_registry_recent_game_includes_every_postseason_round(self) -> None:
        team = {"mlb_id": 147, "short_name": "Yankees"}
        for game_type in ("F", "D", "L", "W"):
            with self.subTest(game_type=game_type):
                payload = {"dates": [{"games": [{
                    "gamePk": 849851, "gameType": game_type,
                    "gameDate": "2026-09-29T23:00:00Z",
                    "status": {"abstractGameState": "Final", "codedGameState": "F"},
                }]}]}
                with patch.object(fetch_team_data, "fetch_json", side_effect=[
                    payload, RuntimeError("selected game requested"),
                ]) as fetch:
                    with self.assertRaisesRegex(RuntimeError, "selected game requested"):
                        fetch_team_data.recent_game_feed(team)
                self.assertIn("gameTypes=R,F,D,L,W", fetch.call_args_list[0].args[0])
                self.assertIn("849851", fetch.call_args_list[1].args[0])

    def test_registry_schedule_includes_postseason_games(self) -> None:
        team = {"mlb_id": 110, "short_name": "Orioles"}
        with (
            patch.object(fetch_team_data, "datetime", PostseasonDatetime),
            patch.object(
                fetch_team_data,
                "fetch_json",
                side_effect=(SEASON_PAYLOAD, postseason_payload(team["mlb_id"])),
            ) as fetch,
        ):
            feed = fetch_team_data.schedule_feed(team)

        self.assertEqual([game["game_pk"] for game in feed["games"]], [849851])
        self.assertEqual(feed["games"][0]["series_description"], "AL Wild Card Series")
        schedule_url = fetch.call_args_list[1].args[0]
        self.assertIn("endDate=2026-10-31", schedule_url)
        self.assertIn("gameTypes=R,F,D,L,W", schedule_url)

    def test_registry_schedule_stops_after_season_end(self) -> None:
        team = {"mlb_id": 110, "short_name": "Orioles"}
        with (
            patch.object(fetch_team_data, "datetime", AfterPostseasonDatetime),
            patch.object(fetch_team_data, "fetch_json", return_value=SEASON_PAYLOAD) as fetch,
        ):
            feed = fetch_team_data.schedule_feed(team)

        self.assertEqual(feed["games"], [])
        fetch.assert_called_once_with(fetch_team_data.SEASON_API.format(season=2026))



if __name__ == "__main__":
    unittest.main()
