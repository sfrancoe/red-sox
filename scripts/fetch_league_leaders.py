#!/usr/bin/env python3
"""Generate versioned AL/NL/MLB leaderboards from complete MLB populations.

WAR is deliberately marked unavailable until a stable Baseball Reference-to-MLB
identity crosswalk is supplied.  A name-only join would create plausible but
wrong ranks, especially for historical and two-way players.
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
MLB = "https://statsapi.mlb.com/api/v1/stats"
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
CATEGORIES = ("war", "whip", "hr", "avg", "ops", "rbi")
LEAGUES = {"al": 103, "nl": 104, "mlb": None}


def fetch_json(url: str) -> dict[str, Any]:
    last: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        try:
            with urlopen(Request(url, headers=headers), timeout=90) as response:
                return json.load(response)
        except Exception as exc:
            last = exc
    raise RuntimeError(f"Could not fetch {url}: {last}")


def innings_outs(value: object) -> int | None:
    try:
        whole, _, outs = str(value).partition(".")
        whole_i, outs_i = int(whole), int(outs or 0)
        if outs_i not in (0, 1, 2):
            return None
        return whole_i * 3 + outs_i
    except (TypeError, ValueError):
        return None


def rank(entries: list[dict[str, Any]], ascending: bool) -> list[dict[str, Any]]:
    entries.sort(key=lambda row: (row["value"], row["name"], row["player_id"]) if ascending
                 else (-row["value"], row["name"], row["player_id"]))
    previous: float | None = None
    for index, entry in enumerate(entries, 1):
        if entry["value"] != previous:
            current_rank = index
            previous = entry["value"]
        entry["rank"] = current_rank
        entry["tied"] = sum(1 for candidate in entries if candidate["value"] == entry["value"]) > 1
    return entries


def formatted(category: str, value: float) -> str:
    if category in ("avg", "ops", "whip"):
        return f"{value:.3f}".lstrip("0")
    if category == "war":
        return f"{value:.1f}"
    return str(int(value))


def stats(season: int, group: str, league_id: int | None, pool: str) -> list[dict[str, Any]]:
    league = f"&leagueId={league_id}" if league_id else ""
    url = (f"{MLB}?stats=season&group={group}&season={season}&gameType=R"
           f"&playerPool={pool}{league}&hydrate=person,team&limit=2000")
    payload = fetch_json(url)
    return (payload.get("stats") or [{}])[0].get("splits") or []


def entry(split: dict[str, Any], category: str, raw: object) -> dict[str, Any] | None:
    player, team = split.get("player") or {}, split.get("team") or {}
    try:
        value = float(raw)
        person_id = int(player["id"])
    except (KeyError, TypeError, ValueError):
        return None
    name = str(player.get("fullName") or "").strip()
    if not name:
        return None
    return {"player_id": person_id, "provider": "mlb", "name": name, "value": value,
            "display_value": formatted(category, value), "team_id": team.get("id"),
            "team_abbreviation": team.get("abbreviation") or "Multiple teams"}


def category_rows(season: int, league_id: int | None) -> dict[str, Any]:
    hitting_all = stats(season, "hitting", league_id, "ALL")
    hitting_qualified = stats(season, "hitting", league_id, "QUALIFIED")
    pitching = stats(season, "pitching", league_id, "ALL")
    specs = {"hr": (hitting_all, "homeRuns", False, "All hitters"),
             "rbi": (hitting_all, "rbi", False, "All hitters"),
             "avg": (hitting_qualified, "avg", False, "Qualified hitters"),
             "ops": (hitting_qualified, "ops", False, "Qualified hitters")}
    result: dict[str, Any] = {}
    for key, (splits, field, ascending, label) in specs.items():
        rows = [candidate for split in splits if (candidate := entry(split, key, (split.get("stat") or {}).get(field)))]
        result[key] = {"availability": "available", "eligibility": label,
                       "population_count": len(rows), "entries": rank(rows, ascending)}
    whip = []
    for split in pitching:
        stat = split.get("stat") or {}
        if (outs := innings_outs(stat.get("inningsPitched"))) is not None and outs >= 120:
            if candidate := entry(split, "whip", stat.get("whip")):
                whip.append(candidate)
    result["whip"] = {"availability": "available" if whip else "empty",
                      "eligibility": "Min. 40 IP", "population_count": len(whip),
                      "entries": rank(whip, True)}
    result["war"] = {"availability": "unavailable", "eligibility": "Baseball Reference bWAR",
                     "message": "Comparison unavailable until verified provider identity mapping is published.",
                     "population_count": 0, "entries": []}
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("years", nargs="*", type=int)
    args = parser.parse_args()
    years = args.years or sorted({int(year) for path in ROOT.glob("data/**/seasons.json")
                                  for year in json.loads(path.read_text()).keys()}, reverse=True)
    output = ROOT / "data/leaderboards"
    output.mkdir(parents=True, exist_ok=True)
    for season in years:
        scopes = {scope: category_rows(season, league) for scope, league in LEAGUES.items()}
        artifact = {"schema_version": 1, "season": season,
                    "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                    "sources": {"mlb": "MLB Stats API regular-season statistics", "war": "Baseball Reference daily bWAR"},
                    "scopes": scopes, "team_contexts": {}}
        destination = output / f"{season}.json"
        temporary = destination.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(artifact, separators=(",", ":")) + "\n")
        temporary.replace(destination)
        print(f"Wrote {destination}")


if __name__ == "__main__":
    main()
