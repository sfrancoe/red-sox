#!/usr/bin/env python3
"""Fetch current-season paths and leaders for registry teams."""

from __future__ import annotations

import argparse
import csv
import gzip
import io
import json
import sys
import time
from datetime import datetime, timezone
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from team_registry import data_directory, expansion_teams, team_by_key


FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
MLB = "https://statsapi.mlb.com/api/v1"
SCHEDULE_API = MLB + "/schedule?sportId=1&teamId={team}&season={season}&gameType=R"
HITTING_API = (
    MLB + "/stats?stats=season&group=hitting&teamId={team}&season={season}"
    "&playerPool={pool}&hydrate=person&limit=100"
)
PITCHING_API = (
    MLB + "/stats?stats=season&group=pitching&teamId={team}&season={season}"
    "&playerPool=ALL&hydrate=person&limit=100"
)
WAR_URLS = (
    "https://www.baseball-reference.com/data/war_daily_bat.txt",
    "https://www.baseball-reference.com/data/war_daily_pitch.txt",
)
PLAYED_STATES = {"Final", "Completed Early", "Game Over"}


def fetch_json(url: str) -> dict[str, Any]:
    last_error: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        for attempt in range(4):
            try:
                with urlopen(Request(url, headers=headers), timeout=45) as response:
                    return json.load(response)
            except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
                last_error = exc
                if attempt < 3:
                    time.sleep(2**attempt)
    raise RuntimeError(f"Could not fetch {url}: {last_error}")


def fetch_text(url: str) -> str:
    last_error: Exception | None = None
    for base_headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        headers = {**base_headers, "Accept-Encoding": "gzip"}
        for attempt in range(4):
            try:
                with urlopen(Request(url, headers=headers), timeout=120) as response:
                    raw = response.read()
                    if response.headers.get("Content-Encoding") == "gzip":
                        raw = gzip.decompress(raw)
                    return raw.decode("utf-8", errors="replace")
            except (HTTPError, URLError, TimeoutError, OSError) as exc:
                last_error = exc
                if attempt < 3:
                    time.sleep(2**attempt)
    raise RuntimeError(f"Could not fetch {url}: {last_error}")


def war_by_team(teams: list[dict[str, Any]], season: int) -> dict[str, list[dict[str, Any]]]:
    wanted = {team["baseball_reference_id"] for team in teams}
    totals: dict[str, dict[str, float]] = {key: {} for key in wanted}
    for url in WAR_URLS:
        for row in csv.DictReader(io.StringIO(fetch_text(url))):
            key = row.get("team_ID") or ""
            if key not in wanted:
                continue
            try:
                year = int(row.get("year_ID") or "")
                war = float(row.get("WAR") or "")
            except ValueError:
                continue
            if year != season:
                continue
            name = (row.get("name_common") or "").strip()
            if name:
                totals[key][name] = totals[key].get(name, 0.0) + war
    return {
        key: [
            {"name": name, "war": round(war, 1)}
            for name, war in sorted(players.items(), key=lambda item: (-item[1], item[0]))[:3]
        ]
        for key, players in totals.items()
    }


def batting_leaders(team: dict[str, Any], season: int) -> dict[str, dict[str, Any]]:
    pools = {}
    for pool in ("ALL", "QUALIFIED"):
        payload = fetch_json(HITTING_API.format(team=team["mlb_id"], season=season, pool=pool))
        stats = payload.get("stats") or []
        pools[pool] = stats[0].get("splits", []) if stats else []
    specs = {
        "hr": ("ALL", "homeRuns", int), "rbi": ("ALL", "rbi", int),
        "avg": ("QUALIFIED", "avg", float), "ops": ("QUALIFIED", "ops", float),
    }
    output = {}
    for label, (pool, field, converter) in specs.items():
        candidates = []
        for split in pools[pool]:
            name = split.get("player", {}).get("fullName", "").strip()
            raw = split.get("stat", {}).get(field)
            try:
                numeric = converter(raw)
            except (TypeError, ValueError):
                continue
            if name:
                candidates.append((numeric, name, raw))
        ranked = sorted(candidates, key=lambda row: (-row[0], row[1]))[:3]
        if not ranked:
            raise RuntimeError(f"No {label.upper()} leaders returned for {team['full_name']}")
        best = ranked[0][0]
        output[label] = {
            "names": sorted(row[1] for row in candidates if row[0] == best),
            "value": ranked[0][2],
            "top": [{"name": name, "value": raw} for _, name, raw in ranked],
        }
    return output


def pitching_leaders(team: dict[str, Any], season: int) -> dict[str, dict[str, Any]]:
    payload = fetch_json(PITCHING_API.format(team=team["mlb_id"], season=season))
    stats = payload.get("stats") or []
    splits = stats[0].get("splits", []) if stats else []
    candidates = []
    for split in splits:
        name = split.get("player", {}).get("fullName", "").strip()
        stat = split.get("stat") or {}
        try:
            whole, _, outs = str(stat.get("inningsPitched") or "0").partition(".")
            innings = int(whole) + int(outs or 0) / 3
            whip = float(stat.get("whip"))
        except (TypeError, ValueError):
            continue
        if name and innings >= 40:
            candidates.append((whip, name, stat.get("whip")))
    ranked = sorted(candidates, key=lambda row: (row[0], row[1]))[:3]
    if not ranked:
        raise RuntimeError(f"No qualified WHIP leaders returned for {team['full_name']}")
    return {"whip": {"top": [{"name": name, "value": raw} for _, name, raw in ranked]}}


def season_path(team: dict[str, Any], season: int) -> dict[str, Any]:
    payload = fetch_json(SCHEDULE_API.format(team=team["mlb_id"], season=season))
    rows = []
    for day in payload.get("dates", []):
        for game in day.get("games", []):
            status = game.get("status") or {}
            if status.get("codedGameState") not in ("F", "O") or status.get("detailedState") not in PLAYED_STATES:
                continue
            for side in ("home", "away"):
                entry = (game.get("teams") or {}).get(side) or {}
                if (entry.get("team") or {}).get("id") != team["mlb_id"]:
                    continue
                record = entry.get("leagueRecord") or {}
                if record.get("wins") is None or record.get("losses") is None:
                    continue
                rows.append({
                    "date": game.get("officialDate", ""), "game_date": game.get("gameDate", ""),
                    "game_number": game.get("gameNumber", 1), "pk": game.get("gamePk", 0),
                    "wins": record["wins"], "losses": record["losses"],
                })
    rows.sort(key=lambda row: (row["date"], row["game_number"], row["game_date"], row["pk"]))
    if not rows:
        raise RuntimeError(f"No completed {team['short_name']} games returned")
    diff, sequence, wins, losses = [], [], 0, 0
    for row in rows:
        next_wins, next_losses = row["wins"], row["losses"]
        if next_wins == wins and next_losses == losses:
            continue
        sequence.append("W" if next_wins > wins else "L")
        wins, losses = next_wins, next_losses
        diff.append(wins - losses)
    return {
        "diff": diff, "seq": "".join(sequence), "record": f"{wins}-{losses}",
        "end_game": len(diff), "in_progress": len(diff) < 162,
        "last_game_date": rows[-1]["date"],
    }


def write_team(team: dict[str, Any], season: int, war: list[dict[str, Any]]) -> None:
    print(f"{team['full_name']} leaders:")
    result = season_path(team, season)
    result["batting_leaders"] = batting_leaders(team, season)
    result["pitching_leaders"] = pitching_leaders(team, season)
    result["war_leaders"] = war
    if not war:
        raise RuntimeError(f"No Baseball Reference WAR leaders returned for {team['full_name']}")
    result["war_leader"] = war[0]
    seasons = {str(season): result}
    output = data_directory(team)
    output.mkdir(parents=True, exist_ok=True)
    (output / "seasons.json").write_text(json.dumps(seasons, indent=1) + "\n")
    meta = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source": "MLB Stats API (statsapi.mlb.com)",
        "war_source": "Baseball Reference daily bWAR (baseball-reference.com/data)",
        "team_id": team["mlb_id"],
        "seasons": {str(season): {
            "record": result["record"], "games": result["end_game"],
            "in_progress": result["in_progress"], "war_leader": result["war_leader"],
            "war_leaders": result["war_leaders"],
            "pitching_leaders": result["pitching_leaders"],
            "batting_leaders": result["batting_leaders"],
        }},
    }
    (output / "meta.json").write_text(json.dumps(meta, indent=1) + "\n")
    print(f"  wrote {output / 'seasons.json'} and {output / 'meta.json'}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team", action="append", default=[])
    parser.add_argument("--season", type=int, default=datetime.now(timezone.utc).year)
    args = parser.parse_args()
    teams = [team_by_key(key) for key in args.team] if args.team else expansion_teams()
    war = war_by_team(teams, args.season)
    for team in teams:
        write_team(team, args.season, war.get(team["baseball_reference_id"], []))
    return 0


if __name__ == "__main__":
    sys.exit(main())
