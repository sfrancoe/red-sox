#!/usr/bin/env python3
"""Build roster-scoped career postseason leaderboards from the MLB Stats API."""

from __future__ import annotations

import argparse
import json
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from team_registry import all_teams


ROOT = Path(__file__).resolve().parents[1]
MLB_API = "https://statsapi.mlb.com/api/v1"
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
ROSTER_TYPE = "40Man"
EXPECTED_FIELD_SIZE = 12
HITTER_MIN_PA = 20
HITTER_MIN_GAMES = 8
PITCHER_RATE_MIN_OUTS = 45  # 15 IP
PITCHER_COUNT_MIN_GAMES = 5
PITCHER_COUNT_MIN_OUTS = 30  # 10 IP
OUTPUT_DIRECTORY = ROOT / "data" / "postseason-history"

CATEGORIES = {
    "hitting": (
        ("ops", "OPS", True, "rate"),
        ("avg", "AVG", True, "rate"),
        ("homeRuns", "HR", True, "count"),
        ("rbi", "RBI", True, "count"),
    ),
    "pitching": (
        ("wins", "Wins", True, "count"),
        ("whip", "WHIP", False, "rate"),
        ("era", "ERA", False, "rate"),
        ("saves", "Saves", True, "count"),
        ("strikeOuts", "Strikeouts", True, "count"),
    ),
}


def fetch_json(path: str, params: dict[str, str]) -> Any:
    url = f"{MLB_API}{path}?{urlencode(params)}"
    last_error: Exception | None = None
    for user_agent in (None, FALLBACK_USER_AGENT):
        headers = {"Accept": "application/json"}
        if user_agent:
            headers["User-Agent"] = user_agent
        for attempt in range(3):
            try:
                with urlopen(Request(url, headers=headers), timeout=45) as response:
                    return json.load(response)
            except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
                last_error = exc
                if attempt < 2:
                    retry_after = 0
                    if isinstance(exc, HTTPError) and exc.code == 429:
                        try:
                            retry_after = int(exc.headers.get("Retry-After", "0"))
                        except (TypeError, ValueError):
                            pass
                    time.sleep(max(2**attempt, retry_after))
    raise RuntimeError(f"MLB request failed for {url}: {last_error}")


def discover_playoff_teams(season: int) -> list[dict[str, Any]]:
    payload = fetch_json(
        "/standings",
        {
            "leagueId": "103,104",
            "season": str(season),
            "standingsTypes": "regularSeason",
            "hydrate": "team",
        },
    )
    registry = {team["mlb_id"]: team for team in all_teams()}
    teams: list[dict[str, Any]] = []
    for division in payload.get("records", []):
        for record in division.get("teamRecords", []):
            if record.get("clinched") is not True:
                continue
            raw = record.get("team") or {}
            team_id = raw.get("id")
            known = registry.get(team_id)
            if not known:
                raise RuntimeError(f"Clinched MLB team {team_id!r} is absent from the team registry")
            teams.append(
                {
                    "teamId": team_id,
                    "name": known["full_name"],
                    "abbreviation": known["abbreviation"],
                    "league": known["league"],
                }
            )
    teams.sort(key=lambda team: (team["league"], team["name"]))
    if not teams:
        raise RuntimeError(f"MLB standings did not identify any clinched teams for {season}")
    if len(teams) > EXPECTED_FIELD_SIZE:
        raise RuntimeError(f"MLB standings identified an impossible {len(teams)}-team playoff field")
    return teams


def fetch_roster(team: dict[str, Any], season: int) -> list[dict[str, Any]]:
    payload = fetch_json(
        f"/teams/{team['teamId']}/roster",
        {"rosterType": ROSTER_TYPE, "season": str(season)},
    )
    roster = []
    for item in payload.get("roster", []):
        person = item.get("person") or {}
        player_id = person.get("id")
        name = person.get("fullName")
        position_type = (item.get("position") or {}).get("type")
        if isinstance(player_id, int) and isinstance(name, str) and name:
            roster.append(
                {
                    "playerId": player_id,
                    "name": name,
                    "teamId": team["teamId"],
                    "teamAbbreviation": team["abbreviation"],
                    "positionType": position_type,
                }
            )
    if not roster:
        raise RuntimeError(f"MLB returned an empty {ROSTER_TYPE} roster for {team['name']}")
    return roster


def fetch_rosters(teams: list[dict[str, Any]], season: int) -> list[dict[str, Any]]:
    with ThreadPoolExecutor(max_workers=4) as executor:
        results = list(executor.map(lambda team: fetch_roster(team, season), teams))
    players: dict[int, dict[str, Any]] = {}
    for roster in results:
        for player in roster:
            existing = players.get(player["playerId"])
            if existing and existing["teamId"] != player["teamId"]:
                raise RuntimeError(f"Player {player['playerId']} appeared on multiple current rosters")
            players[player["playerId"]] = player
    return list(players.values())


def fetch_career_stats(players: list[dict[str, Any]]) -> dict[int, dict[str, dict[str, Any]]]:
    stats: dict[int, dict[str, dict[str, Any]]] = {}
    player_ids = sorted(player["playerId"] for player in players)
    for start in range(0, len(player_ids), 100):
        batch = player_ids[start:start + 100]
        payload = fetch_json(
            "/people",
            {
                "personIds": ",".join(map(str, batch)),
                "hydrate": "stats(type=career,group=[hitting,pitching],gameType=P)",
            },
        )
        returned = {person.get("id") for person in payload.get("people", [])}
        missing = set(batch) - returned
        if missing:
            raise RuntimeError(f"MLB omitted {len(missing)} requested players from career stats")
        for person in payload.get("people", []):
            player_stats: dict[str, dict[str, Any]] = {}
            for block in person.get("stats", []):
                group = (block.get("group") or {}).get("displayName")
                splits = block.get("splits") or []
                if group in CATEGORIES and splits and isinstance(splits[0].get("stat"), dict):
                    player_stats[group] = splits[0]["stat"]
            stats[person["id"]] = player_stats
    return stats


def parse_number(value: Any) -> float | None:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    return parsed if parsed == parsed else None


def innings_to_outs(value: Any) -> int:
    rendered = str(value or "0.0")
    whole, _, fraction = rendered.partition(".")
    if fraction not in {"0", "1", "2"}:
        raise ValueError(f"Invalid baseball innings value: {rendered}")
    return int(whole) * 3 + int(fraction)


def qualified(group: str, category_kind: str, stat: dict[str, Any]) -> bool:
    games = int(stat.get("gamesPlayed") or stat.get("gamesPitched") or 0)
    if group == "hitting":
        return int(stat.get("plateAppearances") or 0) >= HITTER_MIN_PA or games >= HITTER_MIN_GAMES
    outs = innings_to_outs(stat.get("inningsPitched"))
    if category_kind == "rate":
        return outs >= PITCHER_RATE_MIN_OUTS
    return games >= PITCHER_COUNT_MIN_GAMES or outs >= PITCHER_COUNT_MIN_OUTS


def make_entry(player: dict[str, Any], group: str, stat: dict[str, Any], value: float) -> dict[str, Any]:
    entry = {
        **{key: value for key, value in player.items() if key != "positionType"},
        "value": value,
        "games": int(stat.get("gamesPlayed") or stat.get("gamesPitched") or 0),
    }
    if group == "hitting":
        entry["plateAppearances"] = int(stat.get("plateAppearances") or 0)
        entry["inningsPitched"] = None
    else:
        entry["plateAppearances"] = None
        entry["inningsPitched"] = str(stat.get("inningsPitched") or "0.0")
    return entry


def ranked(entries: list[dict[str, Any]], descending: bool) -> list[dict[str, Any]]:
    ordered = sorted(
        entries,
        key=lambda entry: (
            -entry["value"] if descending else entry["value"],
            -entry["games"],
            entry["name"],
            entry["playerId"],
        ),
    )[:10]
    return [{"rank": index, **entry} for index, entry in enumerate(ordered, 1)]


def build_categories(
    players: list[dict[str, Any]],
    stats_by_player: dict[int, dict[str, dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    output: dict[str, list[dict[str, Any]]] = {}
    for group, definitions in CATEGORIES.items():
        categories = []
        for key, label, higher_is_better, category_kind in definitions:
            candidates = []
            for player in players:
                position_type = player.get("positionType")
                if group == "hitting" and position_type == "Pitcher":
                    continue
                if group == "pitching" and position_type not in {None, "Pitcher", "Two-Way Player"}:
                    continue
                stat = stats_by_player.get(player["playerId"], {}).get(group)
                if not stat or not qualified(group, category_kind, stat):
                    continue
                value = parse_number(stat.get(key))
                if value is not None:
                    candidates.append(make_entry(player, group, stat, value))
            categories.append(
                {
                    "key": key,
                    "label": label,
                    "higherIsBetter": higher_is_better,
                    "qualification": (
                        f"{HITTER_MIN_PA}+ PA or {HITTER_MIN_GAMES}+ games"
                        if group == "hitting"
                        else (
                            f"{PITCHER_RATE_MIN_OUTS // 3}+ IP"
                            if category_kind == "rate"
                            else f"{PITCHER_COUNT_MIN_GAMES}+ appearances or {PITCHER_COUNT_MIN_OUTS // 3}+ IP"
                        )
                    ),
                    "best": ranked(candidates, descending=higher_is_better),
                    "worst": ranked(candidates, descending=not higher_is_better),
                }
            )
        output[group] = categories
    return output


def build_snapshot(season: int) -> dict[str, Any]:
    teams = discover_playoff_teams(season)
    players = fetch_rosters(teams, season)
    stats = fetch_career_stats(players)
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    return {
        "schemaVersion": 1,
        "season": season,
        "status": "locked" if len(teams) == EXPECTED_FIELD_SIZE else "finalizing",
        "generatedAt": now,
        "rosterRefreshedAt": now,
        "statsRefreshedAt": now,
        "source": "MLB Stats API",
        "sourceURL": f"{MLB_API}/standings?leagueId=103,104&season={season}",
        "rosterType": ROSTER_TYPE,
        "teams": teams,
        "playerCount": len(players),
        "categories": build_categories(players, stats),
    }


def should_write_snapshot(output: Path, snapshot: dict[str, Any]) -> bool:
    if not output.exists() or snapshot["status"] != "locked":
        return True
    try:
        existing = json.loads(output.read_text())
        checked = datetime.fromisoformat(existing["generatedAt"].replace("Z", "+00:00"))
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
        return True
    volatile = {"generatedAt", "rosterRefreshedAt", "statsRefreshedAt"}
    same_content = (
        {key: value for key, value in existing.items() if key not in volatile}
        == {key: value for key, value in snapshot.items() if key not in volatile}
    )
    age = datetime.now(timezone.utc) - checked
    return not same_content or age.total_seconds() >= 24 * 60 * 60


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--season", type=int, default=datetime.now(timezone.utc).year)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--scheduled", action="store_true", help="Skip outside the configured postseason window")
    args = parser.parse_args()
    today = datetime.now(timezone.utc).date()
    if args.scheduled and not (
        today.year == args.season
        and (today.month == 9 and today.day >= 20 or today.month == 10 or today.month == 11 and today.day <= 10)
    ):
        print(f"Outside the {args.season} playoff refresh window; nothing to do")
        return
    output = args.output or OUTPUT_DIRECTORY / f"{args.season}.json"
    snapshot = build_snapshot(args.season)
    output.parent.mkdir(parents=True, exist_ok=True)
    if should_write_snapshot(output, snapshot):
        output.write_text(json.dumps(snapshot, indent=2, ensure_ascii=False) + "\n")
    else:
        print(f"No leaderboard or roster changes; keeping the current daily snapshot at {output}")
        return
    print(
        f"Wrote {output}: {len(snapshot['teams'])} playoff teams, "
        f"{snapshot['playerCount']} rostered players, {snapshot['status']}"
    )


if __name__ == "__main__":
    main()
