#!/usr/bin/env python3
"""Regression tests for regular-season and postseason schedule collection."""

from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

import fetch_mets_schedule
import fetch_rays_schedule
import fetch_schedule
import fetch_team_data
import fetch_yankees_schedule


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

    def test_legacy_schedules_include_postseason_games(self) -> None:
        modules = (
            (fetch_schedule, fetch_schedule.BOS),
            (fetch_yankees_schedule, fetch_yankees_schedule.NYY),
            (fetch_mets_schedule, fetch_mets_schedule.NYM),
            (fetch_rays_schedule, fetch_rays_schedule.TBR),
        )
        with tempfile.TemporaryDirectory() as directory:
            for index, (module, team_id) in enumerate(modules):
                output = Path(directory) / f"schedule-{index}.json"
                with self.subTest(module=module.__name__):
                    with (
                        patch.object(module, "datetime", PostseasonDatetime),
                        patch.object(module, "OUTPUT_PATH", output),
                        patch.object(
                            module,
                            "fetch_json",
                            side_effect=(SEASON_PAYLOAD, postseason_payload(team_id)),
                        ) as fetch,
                    ):
                        module.main()

                    feed = json.loads(output.read_text())
                    self.assertEqual([game["game_pk"] for game in feed["games"]], [849851])
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

    def test_legacy_schedules_stop_after_season_end(self) -> None:
        modules = (
            fetch_schedule,
            fetch_yankees_schedule,
            fetch_mets_schedule,
            fetch_rays_schedule,
        )
        with tempfile.TemporaryDirectory() as directory:
            for index, module in enumerate(modules):
                output = Path(directory) / f"schedule-{index}.json"
                with self.subTest(module=module.__name__):
                    with (
                        patch.object(module, "datetime", AfterPostseasonDatetime),
                        patch.object(module, "OUTPUT_PATH", output),
                        patch.object(module, "fetch_json", return_value=SEASON_PAYLOAD) as fetch,
                    ):
                        module.main()

                    self.assertEqual(json.loads(output.read_text())["games"], [])
                    fetch.assert_called_once_with(module.SEASON_API.format(season=2026))


if __name__ == "__main__":
    unittest.main()
