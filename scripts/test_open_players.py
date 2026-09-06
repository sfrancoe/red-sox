#!/usr/bin/env python3
"""Deterministic tests for the open-data player adapter."""

from __future__ import annotations

from datetime import date

from fetch_players import (
    aggregate_career_stats,
    age_from_birth_date,
    parse_roster,
    wikipedia_birth_date,
    wikipedia_birthplace,
    wikipedia_infobox_value,
    wikipedia_teams,
)


def main() -> None:
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
