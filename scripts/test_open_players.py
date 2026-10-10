#!/usr/bin/env python3
"""Deterministic tests for the open-data player adapter."""

from __future__ import annotations

from datetime import date
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import fetch_players
import team_registry

from fetch_players import (
    aggregate_career_stats,
    age_from_birth_date,
    parse_roster,
    wikipedia_birth_date,
    wikipedia_birthplace,
    wikipedia_infobox_value,
    wikipedia_teams,
)


REGULAR_ROSTER = """{{MLB roster
|Date=September 5, 2026
|Pitchers=
|Starters=
{{MLBplayer|54|[[Example Starter]]}}
|Bullpen=
{{MLBplayer|22|[[Example Reliever]]}}
|Closer=
{{MLBplayer|10|[[Example Closer]]}}
|Two-way=
{{MLBplayer|17|[[Example Two-way Player]]}}
|Outfielders=
{{MLBplayer|&nbsp;7|[[Example Person (baseball)|Example Person]]}}
|InactivePitchers=
{{MLBplayer|30|[[Example Reserve Pitcher]]}}
|InactiveTW=
{{MLBplayer|31|[[Example Reserve Two-way Player]]}}
|InactiveInfielders=
{{MLBplayer|12|[[Example Infielder]]|IL}}
|60DayIL=
{{MLBplayer|33|[[Example Long-term Injury]]}}
|Restricted=
{{MLBplayer|34|[[Example Restricted Player]]}}
|Manager=
{{MLBplayer|1|[[Example Manager]]}}
|Coaches=
{{MLBplayer|2|Example Coach}}
}}"""

SPRING_ROSTER = """{{MLB spring training roster
|Date=September 29, 2026
|Pitchers=
{{MLBplayer|--|[[Example Pitcher]]}}
{{MLBplayer|11|[[Example Injured Pitcher]]|IL}}
<!-- {{MLBplayer|99|[[Commented-out Player]]}} -->
|Catchers=
{{MLBplayer|&nbsp;4|[[Example Catcher (baseball)|Example Catcher]]}}
|InactivePitchers=
{{MLBplayer|72|[[Example Invitee]]}}
|60DayIL=
{{MLBplayer|75|[[Example Long-term Injury]]}}
|Restricted=
{{MLBplayer|58|[[Example Restricted Player]]}}
|Manager=
{{MLBplayer|1|[[Example Manager]]}}
|Coaches=
{{MLBplayer|2|Example Coach}}
}}"""


class RosterParsingTests(unittest.TestCase):
    def test_regular_roster_keeps_players_and_statuses(self) -> None:
        rows, roster_date = parse_roster(REGULAR_ROSTER)
        players = {row["name"]: row for row in rows}
        self.assertEqual(len(rows), 10)
        self.assertEqual(roster_date, "September 5, 2026")
        for name in ("Example Starter", "Example Reliever", "Example Closer", "Example Two-way Player"):
            self.assertEqual((players[name]["group"], players[name]["abbreviation"]), ("Pitcher", "P"))
            self.assertTrue(players[name]["active"])
            self.assertEqual(players[name]["status"], "Active")
        self.assertEqual(players["Example Person"]["page_title"], "Example Person (baseball)")
        self.assertEqual(players["Example Person"]["number"], "7")
        for name, status in (
            ("Example Reserve Pitcher", "Inactive roster"),
            ("Example Reserve Two-way Player", "Inactive roster"),
            ("Example Infielder", "Injured list"),
            ("Example Long-term Injury", "60-day injured list"),
            ("Example Restricted Player", "Restricted list"),
        ):
            self.assertFalse(players[name]["active"])
            self.assertEqual(players[name]["status"], status)

    def test_spring_roster_keeps_pitchers_and_distinguishes_invitees(self) -> None:
        rows, roster_date = parse_roster(SPRING_ROSTER)
        players = {row["name"]: row for row in rows}
        self.assertEqual(len(rows), 6)
        self.assertEqual(roster_date, "September 29, 2026")
        self.assertEqual(players["Example Pitcher"]["group"], "Pitcher")
        self.assertEqual(players["Example Pitcher"]["status"], "40-man roster")
        self.assertEqual(players["Example Catcher"]["status"], "40-man roster")
        self.assertEqual(players["Example Catcher"]["number"], "4")
        self.assertEqual(players["Example Invitee"]["status"], "Non-roster invitee")
        self.assertEqual(players["Example Injured Pitcher"]["status"], "Injured list")
        self.assertEqual(players["Example Long-term Injury"]["status"], "60-day injured list")
        self.assertEqual(players["Example Restricted Player"]["status"], "Restricted list")
        self.assertFalse(any(row["active"] for row in rows))

    def test_regular_roster_also_supports_generic_pitchers(self) -> None:
        rows, _ = parse_roster("{{MLB roster\n|Pitchers=\n{{MLBplayer||[[Example Pitcher]]}}\n}}")
        self.assertEqual(len(rows), 1)
        self.assertIsNone(rows[0]["number"])
        self.assertTrue(rows[0]["active"])
        self.assertEqual(rows[0]["status"], "Active")

    def test_injured_player_is_never_marked_active(self) -> None:
        rows, _ = parse_roster("{{MLB roster\n|Pitchers=\n{{MLBplayer|11|[[Example Pitcher]]|IL}}\n}}")
        self.assertEqual(rows[0]["status"], "Injured list")
        self.assertFalse(rows[0]["active"])

    def test_unknown_player_section_fails_instead_of_losing_pitchers(self) -> None:
        for section in ("FuturePitchers", "Future-Pitchers", "Future pitchers"):
            with self.subTest(section=section), self.assertRaisesRegex(RuntimeError, "Unsupported.*section"):
                parse_roster(SPRING_ROSTER.replace("|Pitchers=", f"|{section}="))

    def test_missing_pitchers_fails_even_with_enough_hitters_and_an_injured_pitcher(self) -> None:
        hitters = "\n".join(f"{{{{MLBplayer|{i}|[[Hitter {i}]]}}}}" for i in range(26))
        with self.assertRaisesRegex(RuntimeError, "no primary pitching rows"):
            parse_roster("{{MLB roster\n|Outfielders=\n" + hitters +
                         "\n|60DayIL=\n{{MLBplayer|11|[[Injured Pitcher]]}}\n}}")

    def test_malformed_player_row_cannot_be_silently_skipped(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "Unparsed.*Pitchers"):
            parse_roster(SPRING_ROSTER.replace("[[Example Pitcher]]", "Example Pitcher"))

    def test_duplicate_player_or_section_fails(self) -> None:
        for extra in (
            "{{MLBplayer|--|[[Example Pitcher]]}}\n",
            "|Pitchers=\n{{MLBplayer|90|[[Different Pitcher]]}}\n",
        ):
            with self.subTest(extra=extra), self.assertRaisesRegex(RuntimeError, "Duplicate"):
                parse_roster(SPRING_ROSTER.replace("|Catchers=", extra + "|Catchers="))

    def test_unsupported_roster_format_fails(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "Unsupported Wikipedia roster template"):
            parse_roster(SPRING_ROSTER.replace("MLB spring training roster", "Future MLB roster"))

    def test_feed_preserves_spring_membership_and_statuses(self) -> None:
        rows, roster_date = parse_roster(SPRING_ROSTER)
        feed = fetch_players.build_feed(
            {"mlb_id": 121, "full_name": "New York Mets"},
            "Template:New York Mets roster", rows, {}, {}, {}, {}, roster_date, 123,
        )
        players = {row["name"]: row for row in feed["players"]}
        self.assertEqual(feed["player_count"], 6)
        self.assertEqual(feed["active_count"], 0)
        self.assertEqual(feed["source"]["roster_revision"], 123)
        self.assertEqual(players["Example Pitcher"]["position"]["group"], "Pitcher")
        self.assertEqual(players["Example Pitcher"]["roster_status"], "40-man roster")
        self.assertEqual(players["Example Invitee"]["roster_status"], "Non-roster invitee")
        self.assertFalse(players["Example Injured Pitcher"]["is_active_roster"])

    def test_rejected_roster_preserves_files_and_does_not_prune_careers(self) -> None:
        team = {"api_key": "redsox", "full_name": "Boston Red Sox", "data_directory": "redsox"}
        invalid = SPRING_ROSTER.replace("|Pitchers=", "|Future-Pitchers=")
        with TemporaryDirectory() as directory:
            root = Path(directory)
            bundled = root / "ios" / "players.json"
            careers = root / "data" / "player-careers"
            for path in (root / "data" / "redsox" / "players.json", bundled, careers / "123.json"):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('{"sentinel": "previous snapshot"}\n')
            before = {path: path.read_bytes() for path in root.rglob("*.json")}

            def roster(_template: str) -> tuple[list[dict], str | None, int]:
                rows, roster_date = parse_roster(invalid)
                return rows, roster_date, 123

            with (
                patch.object(fetch_players, "ROOT", root),
                patch.object(team_registry, "ROOT", root),
                patch.object(fetch_players, "IOS_OUTPUT_PATH", bundled),
                patch.object(fetch_players, "CAREER_OUTPUT_DIRECTORY", careers),
                patch.object(fetch_players, "all_teams", return_value=[team]),
                patch.object(fetch_players, "cached_career_stats", return_value={}),
                patch.object(fetch_players, "chadwick_people", return_value=[]),
                patch.object(fetch_players, "current_mlb_people", return_value={}),
                patch.object(fetch_players, "wikipedia_roster", side_effect=roster),
                patch.object(fetch_players, "urlopen", side_effect=AssertionError("Unexpected network request")),
                patch("sys.argv", ["fetch_players.py"]),
                self.assertRaisesRegex(RuntimeError, "Unsupported.*section"),
            ):
                fetch_players.main()
            self.assertEqual({path: path.read_bytes() for path in root.rglob("*.json")}, before)


def main() -> None:
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(RosterParsingTests)
    )
    if not result.wasSuccessful():
        raise SystemExit(1)
    sample = """{{MLB roster
|Date=September 5, 2026
|Starters=
{{MLBplayer|54|[[Example Pitcher]]}}
|Outfielders=
{{MLBplayer|&nbsp;7|[[Example Person (baseball)|Example Person]]}}
|InactiveInfielders=
{{MLBplayer|12|[[Example Infielder]]|IL}}
|Manager=
{{MLBplayer|1|[[Example Manager]]}}
}}"""
    rows, roster_date = parse_roster(sample)
    assert roster_date == "September 5, 2026"
    assert [row["name"] for row in rows] == ["Example Pitcher", "Example Person", "Example Infielder"]
    assert rows[0]["group"] == "Pitcher" and rows[0]["active"]
    assert rows[1]["number"] == "7" and rows[1]["page_title"] == "Example Person (baseball)"
    assert rows[2]["status"] == "Injured list" and not rows[2]["active"]
    biography = """{{Infobox baseball biography
| teams = * [[First Club]] (2020)
* [[Second Club (baseball)|Second Club]] (2021–present)
| birth_date = {{Birth date and age|2000|3|4}}
| birth_place = [[Portland, Oregon|Portland]], Oregon, U.S.
| bats = Left
| throws = Right
| awards = * [[All-Star]]
}}"""
    assert wikipedia_teams(biography) == ["First Club", "Second Club"]
    assert wikipedia_birth_date(biography) == "2000-03-04"
    assert wikipedia_birthplace(biography) == "Portland, Oregon, U.S."
    assert wikipedia_infobox_value(biography, "bats") == "Left"
    assert age_from_birth_date("2000-03-04", date(2026, 3, 3)) == 25

    batting = aggregate_career_stats(
        [{
            "gid": "BOS202504010", "b_pa": "4", "b_ab": "3", "b_r": "1", "b_h": "2",
            "b_d": "1", "b_t": "0", "b_hr": "0", "b_rbi": "1", "b_sf": "0",
            "b_hbp": "0", "b_w": "1", "b_k": "1", "b_sb": "1", "b_cs": "0",
        }],
        [],
        [{"gid": "BOS202504020"}],
    )["batting"]
    assert batting["games"] == 2 and batting["average"] == .667
    assert batting["on_base_percentage"] == .75 and batting["slugging_percentage"] == 1.0
    assert batting["ops"] == 1.75

    pitching = aggregate_career_stats(
        [],
        [{
            "gid": "BOS202504030", "p_ipouts": "18", "p_h": "4", "p_r": "2", "p_er": "2",
            "p_hr": "1", "p_w": "2", "p_k": "7", "p_hbp": "0", "p_wp": "0", "p_bk": "0",
            "wp": "1", "lp": "0", "save": "0", "p_gs": "1", "p_cg": "0",
        }],
        [],
    )["pitching"]
    assert pitching["innings_outs"] == 18 and pitching["wins"] == 1
    assert pitching["era"] == 3.0 and pitching["whip"] == 1.0
    print("Open player adapter checks passed.")


if __name__ == "__main__":
    main()
