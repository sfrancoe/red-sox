#!/usr/bin/env python3
"""Build the native Players directory from openly reusable Wikimedia data.

Wikidata's structured records are CC0. Wikipedia's current roster template is
used only to identify roster membership, uniform number, and broad position group.
No article prose or player photography is copied.
"""

from __future__ import annotations

import hashlib
import html
import argparse
import csv
import io
import json
import re
import time
import unicodedata
import zipfile
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

from team_registry import all_teams, data_directory, team_by_key


ROOT = Path(__file__).resolve().parents[1]
IOS_OUTPUT_PATH = ROOT / "ios" / "Hub Ball" / "Hub Ball" / "players.json"
CAREER_OUTPUT_DIRECTORY = ROOT / "data" / "player-careers"
WIKIPEDIA_API = "https://en.wikipedia.org/w/api.php"
WIKIDATA_API = "https://www.wikidata.org/w/api.php"
MLB_STATS_API = "https://statsapi.mlb.com/api/v1/people/{player_id}/stats"
MLB_PEOPLE_API = "https://statsapi.mlb.com/api/v1/people"
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
CHADWICK_REGISTER_URL = (
    "https://raw.githubusercontent.com/chadwickbureau/register/master/data/people-{suffix}.csv"
)
RETROSHEET_PLAYER_URL = "https://www.retrosheet.org/downloads/playerid_.php"
RETROSHEET_STATS_THROUGH = 2025
RETROSHEET_NOTICE = (
    "The information used here was obtained free of charge from and is copyrighted by Retrosheet. "
    "Interested parties may contact Retrosheet at 20 Sunset Rd., Newark, DE 19711."
)
CAREER_SCHEMA_VERSION = 1
FALLBACK_ID_BASE = 1_900_000_000

SECTION_DETAILS = {
    "Starters": ("Pitcher", "P", True),
    "Bullpen": ("Pitcher", "P", True),
    "Closer": ("Pitcher", "P", True),
    "Catchers": ("Catcher", "C", True),
    "Infielders": ("Infielder", "IF", True),
    "Outfielders": ("Outfielder", "OF", True),
    "DH": ("Hitter", "DH", True),
    "InactivePitchers": ("Pitcher", "P", False),
    "InactiveCatchers": ("Catcher", "C", False),
    "InactiveInfielders": ("Infielder", "IF", False),
    "InactiveOutfielders": ("Outfielder", "OF", False),
    "InactiveDH": ("Hitter", "DH", False),
    "60DayIL": ("Pitcher", "P", False),
    "Restricted": ("Hitter", "", False),
}


def fetch_json(base_url: str, params: dict[str, str]) -> Any:
    url = f"{base_url}?{urlencode(params)}"
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
                    time.sleep(max(2**attempt, retry_after, 10 if isinstance(exc, HTTPError) and exc.code == 429 else 0))
    raise RuntimeError(f"Could not fetch open player data from {base_url}: {last_error}")


def fetch_bytes(url: str, data: bytes | None = None, content_type: str | None = None) -> bytes:
    last_error: Exception | None = None
    for user_agent in (None, FALLBACK_USER_AGENT):
        headers: dict[str, str] = {}
        if content_type:
            headers["Content-Type"] = content_type
        if user_agent:
            headers["User-Agent"] = user_agent
        for attempt in range(3):
            try:
                with urlopen(Request(url, data=data, headers=headers), timeout=60) as response:
                    return response.read()
            except (HTTPError, URLError, TimeoutError) as exc:
                last_error = exc
                if attempt < 2:
                    time.sleep(2**attempt)
    raise RuntimeError(f"Could not fetch open player data from {url}: {last_error}")


def normalized_name(value: str) -> str:
    rendered = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]", "", rendered)


def chadwick_people() -> list[dict[str, str]]:
    people: list[dict[str, str]] = []
    for suffix in "0123456789abcdef":
        contents = fetch_bytes(CHADWICK_REGISTER_URL.format(suffix=suffix)).decode("utf-8-sig")
        people.extend(csv.DictReader(io.StringIO(contents)))
    return people


def resolve_retrosheet_ids(players: list[dict[str, Any]], people: list[dict[str, str]]) -> None:
    by_mlbam = {row["key_mlbam"]: row for row in people if row.get("key_mlbam") and row.get("key_retro")}
    by_wikidata = {row["key_wikidata"]: row for row in people if row.get("key_wikidata") and row.get("key_retro")}
    by_name: dict[str, list[dict[str, str]]] = {}
    for row in people:
        if not row.get("key_retro"):
            continue
        for name in (
            f"{row.get('name_first', '')} {row.get('name_last', '')}",
            f"{row.get('name_given', '')} {row.get('name_last', '')}",
        ):
            by_name.setdefault(normalized_name(name), []).append(row)

    for player in players:
        match = by_mlbam.get(str(player["id"])) or by_wikidata.get(player.get("wikidata_id", ""))
        if not match:
            candidates = by_name.get(normalized_name(player["name"]), [])
            birth_parts = (player.get("birth_date") or "").split("-")
            if len(birth_parts) == 3:
                dated = [
                    row for row in candidates
                    if [row.get("birth_year"), row.get("birth_month", "").zfill(2), row.get("birth_day", "").zfill(2)]
                    == birth_parts
                ]
                candidates = dated or candidates
            recent = [row for row in candidates if int(row.get("mlb_played_last") or 0) >= 2024]
            candidates = recent or candidates
            if len(candidates) == 1:
                match = candidates[0]
        player["retrosheet_id"] = match.get("key_retro") if match else None


def current_mlb_people() -> dict[str, list[dict[str, Any]]]:
    """Index the current official directory once for stable IDs absent from Wikidata."""
    payload = fetch_json("https://statsapi.mlb.com/api/v1/sports/1/players", {"season": str(datetime.now(timezone.utc).year)})
    indexed: dict[str, list[dict[str, Any]]] = {}
    for person in payload.get("people", []):
        if person.get("id") and person.get("fullName"):
            indexed.setdefault(normalized_name(person["fullName"]), []).append(person)
    return indexed


def resolve_mlb_ids(players: list[dict[str, Any]], indexed_people: dict[str, list[dict[str, Any]]]) -> None:
    """Fill only unambiguous official IDs; never infer one from a name alone."""
    for player in players:
        if player.get("mlb_id"):
            continue
        candidates = indexed_people.get(normalized_name(player["name"]), [])
        if player.get("birth_date"):
            dated = [person for person in candidates if person.get("birthDate") == player["birth_date"]]
            candidates = dated or []
        if len(candidates) == 1:
            player["mlb_id"] = int(candidates[0]["id"])
            player["id"] = player["mlb_id"]
        elif player.get("mlb_id") is None:
            player["id"] = fallback_id(player["name"])


def primary_mlb_positions(player_ids: list[int]) -> dict[int, dict[str, str]]:
    """Return the official primary position for each resolved MLB player ID."""
    positions: dict[int, dict[str, str]] = {}
    unique_ids = sorted(set(player_ids))
    for start in range(0, len(unique_ids), 100):
        payload = fetch_json(
            MLB_PEOPLE_API,
            {"personIds": ",".join(str(player_id) for player_id in unique_ids[start:start + 100])},
        )
        for person in payload.get("people", []):
            player_id = person.get("id")
            position = person.get("primaryPosition") or {}
            name = str(position.get("name") or "").strip()
            abbreviation = str(position.get("abbreviation") or "").strip()
            if not isinstance(player_id, int) or not name or not abbreviation or abbreviation == "X":
                continue
            positions[player_id] = {"name": name, "abbreviation": abbreviation}
    return positions


def apply_primary_mlb_positions(players: list[dict[str, Any]]) -> None:
    """Keep broad roster groups for filters while displaying the MLB primary position."""
    positions = primary_mlb_positions([
        player["mlb_id"] for player in players if isinstance(player.get("mlb_id"), int)
    ])
    for player in players:
        position = positions.get(player.get("mlb_id"))
        if position:
            player["position"]["name"] = position["name"]
            player["position"]["abbreviation"] = position["abbreviation"]


def integer(row: dict[str, str], key: str) -> int:
    value = row.get(key, "").strip()
    return int(value) if value else 0


def stat_rows(archive: zipfile.ZipFile, suffix: str) -> list[dict[str, str]]:
    filename = next((name for name in archive.namelist() if name.endswith(suffix)), None)
    if not filename:
        return []
    contents = archive.read(filename).decode("utf-8-sig")
    return [
        row for row in csv.DictReader(io.StringIO(contents))
        if row.get("stattype") == "value" and row.get("gametype") == "regular"
    ]


def rate(numerator: float, denominator: float, digits: int = 3) -> float | None:
    return round(numerator / denominator, digits) if denominator else None


def career_stats(retrosheet_id: str | None) -> dict[str, Any]:
    empty = {
        "through_season": RETROSHEET_STATS_THROUGH,
        "status": "not_in_2025_release",
        "batting": None,
        "pitching": None,
    }
    if not retrosheet_id:
        return empty

    payload = fetch_bytes(
        RETROSHEET_PLAYER_URL,
        data=urlencode({"ID": retrosheet_id}).encode(),
        content_type="application/x-www-form-urlencoded",
    )
    try:
        with zipfile.ZipFile(io.BytesIO(payload)) as archive:
            batting_rows = stat_rows(archive, "_b.csv")
            pitching_rows = stat_rows(archive, "_p.csv")
            fielding_rows = stat_rows(archive, "_f.csv")
    except zipfile.BadZipFile as exc:
        raise RuntimeError(f"Retrosheet returned an invalid player log for {retrosheet_id}") from exc

    return aggregate_career_stats(batting_rows, pitching_rows, fielding_rows)


def unavailable_career_stats() -> dict[str, Any]:
    return {
        "through_season": RETROSHEET_STATS_THROUGH,
        "status": "temporarily_unavailable",
        "batting": None,
        "pitching": None,
    }


def aggregate_career_stats(
    batting_rows: list[dict[str, str]],
    pitching_rows: list[dict[str, str]],
    fielding_rows: list[dict[str, str]],
) -> dict[str, Any]:
    all_games = {row["gid"] for row in batting_rows + pitching_rows + fielding_rows}
    batting = None
    if batting_rows:
        totals = {key: sum(integer(row, key) for row in batting_rows) for key in (
            "b_pa", "b_ab", "b_r", "b_h", "b_d", "b_t", "b_hr", "b_rbi",
            "b_sf", "b_hbp", "b_w", "b_k", "b_sb", "b_cs",
        )}
        singles = totals["b_h"] - totals["b_d"] - totals["b_t"] - totals["b_hr"]
        total_bases = singles + 2 * totals["b_d"] + 3 * totals["b_t"] + 4 * totals["b_hr"]
        on_base_denominator = totals["b_ab"] + totals["b_w"] + totals["b_hbp"] + totals["b_sf"]
        batting = {
            "games": len(all_games),
            "plate_appearances": totals["b_pa"],
            "at_bats": totals["b_ab"],
            "runs": totals["b_r"],
            "hits": totals["b_h"],
            "doubles": totals["b_d"],
            "triples": totals["b_t"],
            "home_runs": totals["b_hr"],
            "runs_batted_in": totals["b_rbi"],
            "walks": totals["b_w"],
            "strikeouts": totals["b_k"],
            "stolen_bases": totals["b_sb"],
            "caught_stealing": totals["b_cs"],
            "average": rate(totals["b_h"], totals["b_ab"]),
            "on_base_percentage": rate(totals["b_h"] + totals["b_w"] + totals["b_hbp"], on_base_denominator),
            "slugging_percentage": rate(total_bases, totals["b_ab"]),
        }
        if batting["on_base_percentage"] is not None and batting["slugging_percentage"] is not None:
            batting["ops"] = round(batting["on_base_percentage"] + batting["slugging_percentage"], 3)
        else:
            batting["ops"] = None

    pitching = None
    if pitching_rows:
        totals = {key: sum(integer(row, key) for row in pitching_rows) for key in (
            "p_ipouts", "p_h", "p_r", "p_er", "p_hr", "p_w", "p_k", "p_hbp",
            "p_wp", "p_bk", "wp", "lp", "save", "p_gs", "p_cg",
        )}
        pitching = {
            "games": len({row["gid"] for row in pitching_rows}),
            "games_started": totals["p_gs"],
            "wins": totals["wp"],
            "losses": totals["lp"],
            "saves": totals["save"],
            "innings_outs": totals["p_ipouts"],
            "hits": totals["p_h"],
            "runs": totals["p_r"],
            "earned_runs": totals["p_er"],
            "home_runs": totals["p_hr"],
            "walks": totals["p_w"],
            "strikeouts": totals["p_k"],
            "hit_batters": totals["p_hbp"],
            "wild_pitches": totals["p_wp"],
            "balks": totals["p_bk"],
            "complete_games": totals["p_cg"],
            "era": rate(27 * totals["p_er"], totals["p_ipouts"], 2),
            "whip": rate(3 * (totals["p_w"] + totals["p_h"]), totals["p_ipouts"]),
        }

    return {
        "through_season": RETROSHEET_STATS_THROUGH,
        "status": "available" if batting or pitching else "not_in_2025_release",
        "batting": batting,
        "pitching": pitching,
    }


def optional_int(value: Any) -> int | None:
    if value in (None, "", "--", "---"):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def optional_float(value: Any) -> float | None:
    if value in (None, "", "--", "---", ".---"):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def innings_outs(value: Any) -> int | None:
    """Convert baseball innings notation (12.2 = 12 innings, 2 outs) to outs."""
    rendered = str(value or "").strip()
    match = re.fullmatch(r"(\d+)\.(\d)", rendered)
    if not match or match.group(2) not in {"0", "1", "2"}:
        return None
    return int(match.group(1)) * 3 + int(match.group(2))


def stats_splits(player_id: int, group: str, minors: bool) -> list[dict[str, Any]]:
    params = {"stats": "yearByYear", "group": group}
    if minors:
        params["leagueListId"] = "milb_all"
    else:
        params["sportId"] = "1"
    payload = fetch_json(MLB_STATS_API.format(player_id=player_id), params)
    stats = payload.get("stats", [])
    return stats[0].get("splits", []) if stats else []


def career_season_rows(player_id: int, group: str, minors: bool) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for split in stats_splits(player_id, group, minors):
        season = optional_int(split.get("season"))
        if not season or split.get("gameType") not in (None, "R"):
            continue
        stat = split.get("stat", {})
        sport = split.get("sport", {})
        league = split.get("league", {})
        is_subtotal = optional_int(split.get("numTeams")) not in (None, 1)
        # A minor-league response includes both a full minor-league season subtotal
        # and intermediate league-level subtotals. Keep only the full subtotal plus
        # its team stints; otherwise a traded season is counted multiple times.
        if is_subtotal and sport.get("abbreviation") != "Minors":
            continue
        team = split.get("team", {})
        team_name = team.get("name") or (f"{split.get('numTeams')} teams" if is_subtotal else None)
        if not team_name:
            # An unlabelled aggregate cannot be reconciled with team stints.
            continue
        row = {
            "id": f"{player_id}-{group}-{'minors' if minors else 'mlb'}-{season}-{sport.get('id', 'level')}-{team.get('id', 'subtotal')}",
            "season": season,
            "team": team_name,
            "league": league.get("name"),
            "level": sport.get("abbreviation"),
            "row_type": "subtotal" if is_subtotal else "team_stint",
            "games": optional_int(stat.get("gamesPlayed")),
        }
        if group == "hitting":
            row.update({
                "at_bats": optional_int(stat.get("atBats")), "runs": optional_int(stat.get("runs")),
                "hits": optional_int(stat.get("hits")), "doubles": optional_int(stat.get("doubles")),
                "triples": optional_int(stat.get("triples")), "home_runs": optional_int(stat.get("homeRuns")),
                "runs_batted_in": optional_int(stat.get("rbi")), "stolen_bases": optional_int(stat.get("stolenBases")),
                "walks": optional_int(stat.get("baseOnBalls")), "strikeouts": optional_int(stat.get("strikeOuts")),
                "average": optional_float(stat.get("avg")), "on_base_percentage": optional_float(stat.get("obp")),
                "slugging_percentage": optional_float(stat.get("slg")), "ops": optional_float(stat.get("ops")),
            })
            if not any(row[key] for key in ("at_bats", "hits", "walks", "runs_batted_in", "home_runs", "stolen_bases")):
                # The API can emit a season row for a pitcher who never had a plate
                # appearance. Keep its no-appearance row, but never turn .000 into a
                # fabricated batting rate.
                for key in ("average", "on_base_percentage", "slugging_percentage", "ops"):
                    row[key] = None
        else:
            row.update({
                "games_started": optional_int(stat.get("gamesStarted")), "wins": optional_int(stat.get("wins")),
                "losses": optional_int(stat.get("losses")), "saves": optional_int(stat.get("saves")),
                "innings_outs": innings_outs(stat.get("inningsPitched")), "hits": optional_int(stat.get("hits")),
                "earned_runs": optional_int(stat.get("earnedRuns")), "home_runs": optional_int(stat.get("homeRuns")),
                "walks": optional_int(stat.get("baseOnBalls")), "strikeouts": optional_int(stat.get("strikeOuts")),
                "era": optional_float(stat.get("era")), "whip": optional_float(stat.get("whip")),
            })
            if not row["innings_outs"]:
                row["era"] = None
                row["whip"] = None
        rows.append(row)
    return sorted(rows, key=lambda row: (row["season"], row["row_type"] == "subtotal", row["team"]))


def detailed_career(player: dict[str, Any]) -> dict[str, Any]:
    """Return year/team rows from the provider, preserving unavailable values as null."""
    player_id = player["id"]
    if player_id >= FALLBACK_ID_BASE:
        return {
            "schema_version": CAREER_SCHEMA_VERSION,
            "player_id": player_id,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "data_as_of": None,
            "status": "unavailable",
            "coverage": [],
            "source": None,
            "batting": [],
            "pitching": [],
        }
    batting = career_season_rows(player_id, "hitting", False) + career_season_rows(player_id, "hitting", True)
    pitching = career_season_rows(player_id, "pitching", False) + career_season_rows(player_id, "pitching", True)
    batting.sort(key=lambda row: (row["season"], row["row_type"] == "subtotal", row["team"]))
    pitching.sort(key=lambda row: (row["season"], row["row_type"] == "subtotal", row["team"]))
    coverage = []
    for level, rows in (("MLB", [*filter(lambda row: row["level"] == "MLB", batting + pitching)]), ("Minors", [*filter(lambda row: row["level"] != "MLB", batting + pitching)])):
        if rows:
            coverage.append({
                "league": level,
                "level": level,
                "first_season": min(row["season"] for row in rows),
                "last_season": max(row["season"] for row in rows),
                "status": "available",
                "note": None,
            })
    return {
        "schema_version": CAREER_SCHEMA_VERSION,
        "player_id": player_id,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "data_as_of": datetime.now(timezone.utc).date().isoformat(),
        "status": "available" if batting or pitching else "unavailable",
        "coverage": coverage,
        "source": {
            "name": "MLB Stats API",
            "url": MLB_STATS_API.format(player_id=player_id),
            "attribution": "Season and minor-league statistics supplied by the MLB Stats API; regular season only.",
        },
        "batting": batting,
        "pitching": pitching,
    }


def write_detailed_careers(players: list[dict[str, Any]], skip_new: bool) -> None:
    CAREER_OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    pending = []
    for player in players:
        path = CAREER_OUTPUT_DIRECTORY / f"{player['id']}.json"
        if skip_new and path.exists():
            continue
        pending.append(player)

    def refresh(player: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any] | None]:
        path = CAREER_OUTPUT_DIRECTORY / f"{player['id']}.json"
        try:
            return player, detailed_career(player)
        except RuntimeError:
            if path.exists():
                # A prior good snapshot is safer than deleting a career on a transient outage.
                return player, None
            return player, {
                "schema_version": CAREER_SCHEMA_VERSION,
                "player_id": player["id"],
                "generated_at": datetime.now(timezone.utc).isoformat(),
                "data_as_of": None,
                "status": "temporarily_unavailable",
                "coverage": [],
                "source": None,
                "batting": [],
                "pitching": [],
            }

    # Four players at once is enough to keep the daily 30-team refresh practical
    # without treating the public provider as an unlimited bulk-export service.
    with ThreadPoolExecutor(max_workers=4) as executor:
        results = executor.map(refresh, pending)
        for player, detail in results:
            if detail is None:
                continue
            path = CAREER_OUTPUT_DIRECTORY / f"{player['id']}.json"
            path.write_text(json.dumps(detail, indent=2, ensure_ascii=False) + "\n")


def output_path(team: dict[str, Any]) -> Path:
    root = ROOT / "data" if team["legacy_root_data"] else data_directory(team)
    return root / "players.json"


def cached_career_stats() -> dict[str, dict[str, Any]]:
    cached: dict[str, dict[str, Any]] = {}
    paths = [output_path(team) for team in all_teams()]
    for path in paths:
        if not path.exists():
            continue
        try:
            previous = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        for player in previous.get("players", []):
            retrosheet_id = player.get("retrosheet_id")
            stats = player.get("career_stats", {})
            if (
                retrosheet_id
                and stats.get("through_season") == RETROSHEET_STATS_THROUGH
                and stats.get("status") != "temporarily_unavailable"
            ):
                cached[retrosheet_id] = stats
    return cached


def clean_number(value: str) -> str | None:
    rendered = html.unescape(re.sub(r"<[^>]+>", "", value)).replace("\xa0", "").strip()
    return rendered or None


def slugify(value: str, player_id: int) -> str:
    normalized = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    slug = re.sub(r"[^a-z0-9]+", "-", normalized.lower()).strip("-")
    return slug or f"player-{player_id}"


def parse_roster(wikitext: str) -> tuple[list[dict[str, Any]], str | None]:
    date_match = re.search(r"\|Date\s*=\s*([^\n]+)", wikitext)
    roster_date = date_match.group(1).strip() if date_match else None
    rows: list[dict[str, Any]] = []
    for section, (group, abbreviation, active) in SECTION_DETAILS.items():
        match = re.search(
            rf"\|{re.escape(section)}[ \t]*=[ \t]*(.*?)(?=\n\|[A-Za-z0-9]+[ \t]*=|\Z)",
            wikitext,
            flags=re.DOTALL,
        )
        if not match:
            continue
        pattern = re.compile(
            r"\{\{MLBplayer\|([^|]+)\|\[\[([^|\]]+)(?:\|([^\]]+))?\]\](?:\|([^}]+))?\}\}"
        )
        for player_match in pattern.finditer(match.group(1)):
            page_title = player_match.group(2).strip()
            display_name = (player_match.group(3) or page_title).strip()
            marker = (player_match.group(4) or "").strip().upper()
            if section == "60DayIL":
                status = "60-day injured list"
            elif marker == "IL":
                status = "Injured list"
            elif section == "Restricted":
                status = "Restricted list"
            else:
                status = "Active" if active else "Inactive roster"
            rows.append(
                {
                    "name": display_name,
                    "page_title": page_title,
                    "number": clean_number(player_match.group(1)),
                    "group": group,
                    "abbreviation": abbreviation,
                    "active": active,
                    "status": status,
                }
            )
    if not rows:
        raise RuntimeError("Wikipedia roster template contained no player rows")
    return rows, roster_date


def wikipedia_roster(roster_template: str) -> tuple[list[dict[str, Any]], str | None, int | None]:
    payload = fetch_json(
        WIKIPEDIA_API,
        {"action": "parse", "page": roster_template, "prop": "wikitext", "format": "json"},
    )
    parsed = payload.get("parse", {})
    rows, roster_date = parse_roster(parsed.get("wikitext", {}).get("*", ""))
    return rows, roster_date, parsed.get("revid")


def wikidata_ids(page_titles: list[str]) -> dict[str, str]:
    matches: dict[str, str] = {}
    for start in range(0, len(page_titles), 50):
        batch = page_titles[start : start + 50]
        payload = fetch_json(
            WIKIPEDIA_API,
            {
                "action": "query",
                "titles": "|".join(batch),
                "prop": "pageprops",
                "ppprop": "wikibase_item",
                "redirects": "1",
                "format": "json",
                "formatversion": "2",
            },
        )
        matches.update(
            {
                page["title"]: page.get("pageprops", {}).get("wikibase_item")
                for page in payload.get("query", {}).get("pages", [])
                if page.get("pageprops", {}).get("wikibase_item")
            }
        )
    return matches


def wikidata_entities(entity_ids: list[str], props: str = "claims|labels|sitelinks") -> dict[str, Any]:
    entities: dict[str, Any] = {}
    for start in range(0, len(entity_ids), 50):
        batch = entity_ids[start : start + 50]
        if not batch:
            continue
        payload = fetch_json(
            WIKIDATA_API,
            {
                "action": "wbgetentities",
                "ids": "|".join(batch),
                "props": props,
                "languages": "en",
                "format": "json",
            },
        )
        entities.update(payload.get("entities", {}))
    return entities


def wikipedia_wikitext(page_titles: list[str]) -> dict[str, str]:
    pages: dict[str, str] = {}
    for start in range(0, len(page_titles), 50):
        payload = fetch_json(
            WIKIPEDIA_API,
            {
                "action": "query",
                "titles": "|".join(page_titles[start : start + 50]),
                "prop": "revisions",
                "rvprop": "content",
                "rvslots": "main",
                "redirects": "1",
                "format": "json",
                "formatversion": "2",
            },
        )
        for page in payload.get("query", {}).get("pages", []):
            revisions = page.get("revisions", [])
            if revisions:
                pages[page["title"]] = revisions[0].get("slots", {}).get("main", {}).get("content", "")
    return pages


def wikipedia_teams(wikitext: str) -> list[str]:
    match = re.search(
        r"\|[ \t]*teams[ \t]*=[ \t]*(.*?)(?=\n[ \t]*\|[ \t]*[A-Za-z_]+[ \t]*=|\n\}\})",
        wikitext,
        re.DOTALL,
    )
    if not match:
        return []
    teams: list[str] = []
    for link in re.finditer(r"\[\[([^|\]]+)(?:\|([^\]]+))?\]\]", match.group(1)):
        value = (link.group(2) or link.group(1)).strip()
        if value and value not in teams:
            teams.append(value)
    return teams


def wikipedia_birth_date(wikitext: str) -> str | None:
    match = re.search(
        r"\|[ \t]*birth_date[ \t]*=[ \t]*\{\{(?:birth date and age|birth-date and age)\|(?:mf=y\|)?(\d{4})\|(\d{1,2})\|(\d{1,2})",
        wikitext,
        re.IGNORECASE,
    )
    if not match:
        return None
    return f"{int(match.group(1)):04d}-{int(match.group(2)):02d}-{int(match.group(3)):02d}"


def wikipedia_birthplace(wikitext: str) -> str:
    return wikipedia_infobox_value(wikitext, "birth_place")


def wikipedia_infobox_value(wikitext: str, key: str) -> str:
    match = re.search(rf"\|[ \t]*{re.escape(key)}[ \t]*=[ \t]*([^\n]+)", wikitext, re.IGNORECASE)
    if not match:
        return ""
    value = re.sub(r"<ref[^>]*>.*?</ref>|<ref[^>]*/>", "", match.group(1), flags=re.IGNORECASE)
    value = re.sub(r"\[\[([^|\]]+)\|([^\]]+)\]\]", r"\2", value)
    value = re.sub(r"\[\[([^\]]+)\]\]", r"\1", value)
    value = re.sub(r"\{\{(?:USA|US)\}\}", "United States", value, flags=re.IGNORECASE)
    value = re.sub(r"\{\{[^}]+\}\}", "", value)
    value = re.sub(r"'{2,}", "", value)
    return html.unescape(value).strip(" ,")


def claim_values(entity: dict[str, Any], property_id: str) -> list[Any]:
    values: list[Any] = []
    for statement in entity.get("claims", {}).get(property_id, []):
        if statement.get("rank") == "deprecated":
            continue
        datavalue = statement.get("mainsnak", {}).get("datavalue")
        if datavalue:
            values.append(datavalue.get("value"))
    return values


def entity_ids_for(entity: dict[str, Any], property_id: str) -> list[str]:
    return [value["id"] for value in claim_values(entity, property_id) if isinstance(value, dict) and value.get("id")]


def first_string(entity: dict[str, Any], property_id: str) -> str | None:
    return next((value for value in claim_values(entity, property_id) if isinstance(value, str)), None)


def first_time(entity: dict[str, Any], property_id: str) -> str | None:
    for value in claim_values(entity, property_id):
        if isinstance(value, dict) and value.get("time"):
            match = re.match(r"^[+-](\d{4}-\d{2}-\d{2})", value["time"])
            if match:
                return match.group(1)
    return None


def quantity(entity: dict[str, Any], property_id: str) -> tuple[float, str] | None:
    for value in claim_values(entity, property_id):
        if isinstance(value, dict) and value.get("amount"):
            try:
                return float(value["amount"]), str(value.get("unit", ""))
            except (TypeError, ValueError):
                pass
    return None


def age_from_birth_date(value: str | None, today: date | None = None) -> int | None:
    if not value:
        return None
    try:
        born = date.fromisoformat(value)
    except ValueError:
        return None
    current = today or datetime.now(timezone.utc).date()
    return current.year - born.year - ((current.month, current.day) < (born.month, born.day))


def fallback_id(name: str) -> int:
    return FALLBACK_ID_BASE + int(hashlib.sha256(name.encode()).hexdigest()[:7], 16) % 100_000_000


def labels_for(ids: set[str]) -> dict[str, str]:
    entities = wikidata_entities(sorted(ids), props="labels")
    return {entity_id: row.get("labels", {}).get("en", {}).get("value", entity_id) for entity_id, row in entities.items()}


def height_text(entity: dict[str, Any]) -> str | None:
    row = quantity(entity, "P2048")
    if not row:
        return None
    amount, unit = row
    meters = amount if unit.endswith("Q11573") else amount / 100 if unit.endswith("Q174728") else None
    if meters is None:
        return None
    inches = round(meters / 0.0254)
    return f"{inches // 12}' {inches % 12}\""


def weight_pounds(entity: dict[str, Any]) -> int | None:
    row = quantity(entity, "P2067")
    if not row:
        return None
    amount, unit = row
    if unit.endswith("Q11570"):
        return round(amount * 2.2046226218)
    if unit.endswith("Q100995"):
        return round(amount)
    return None


def position_name(group: str, entity: dict[str, Any], labels: dict[str, str]) -> str:
    names = [labels.get(value) for value in entity_ids_for(entity, "P413")]
    cleaned = [name.replace("baseball ", "").title() for name in names if name]
    return cleaned[0] if cleaned else group


def player_row(
    team: dict[str, Any], roster: dict[str, Any], qid: str | None,
    entity: dict[str, Any], labels: dict[str, str], wikitext: str,
) -> dict[str, Any]:
    mlb_id = first_string(entity, "P3541")
    player_id = int(mlb_id) if mlb_id and mlb_id.isdigit() else fallback_id(roster["name"])
    birth_date = first_time(entity, "P569") or wikipedia_birth_date(wikitext)
    birthplace_ids = entity_ids_for(entity, "P19")
    college_ids = entity_ids_for(entity, "P69")
    team_ids = entity_ids_for(entity, "P54")
    teams = wikipedia_teams(wikitext) or [labels[value] for value in team_ids if value in labels]
    if team["full_name"] not in teams:
        teams.append(team["full_name"])
    wikipedia_title = entity.get("sitelinks", {}).get("enwiki", {}).get("title") or roster["page_title"]
    return {
        "id": player_id,
        "mlb_id": int(mlb_id) if mlb_id and mlb_id.isdigit() else None,
        "wikidata_id": qid,
        "slug": slugify(roster["name"], player_id),
        "name": roster["name"],
        "full_name": entity.get("labels", {}).get("en", {}).get("value", roster["name"]),
        "number": roster["number"],
        "position": {
            "name": position_name(roster["group"], entity, labels),
            "group": roster["group"],
            "abbreviation": roster["abbreviation"],
        },
        "roster_status": roster["status"],
        "is_active_roster": roster["active"],
        "birth_date": birth_date,
        "age": age_from_birth_date(birth_date),
        "birthplace": labels.get(birthplace_ids[0], "") if birthplace_ids else wikipedia_birthplace(wikitext),
        "height": height_text(entity),
        "weight": weight_pounds(entity),
        "bats": wikipedia_infobox_value(wikitext, "bats") or None,
        "throws": wikipedia_infobox_value(wikitext, "throws") or None,
        "debut_date": (
            f"{wikipedia_infobox_value(wikitext, 'debutdate')}, {wikipedia_infobox_value(wikitext, 'debutyear')}"
            if wikipedia_infobox_value(wikitext, "debutdate") and wikipedia_infobox_value(wikitext, "debutyear")
            else None
        ),
        "debut_team": wikipedia_infobox_value(wikitext, "debutteam") or None,
        "education": {
            "high_schools": [],
            "colleges": [{"name": labels[value]} for value in college_ids if value in labels],
        },
        "teams": teams,
        "source_url": f"https://www.wikidata.org/wiki/{qid}" if qid else None,
        "wikipedia_url": f"https://en.wikipedia.org/wiki/{quote(wikipedia_title.replace(' ', '_'))}",
    }


def build_feed(
    team: dict[str, Any], roster_template: str,
    roster_rows: list[dict[str, Any]], title_to_qid: dict[str, str],
    entities: dict[str, Any], labels: dict[str, str], page_text: dict[str, str],
    roster_date: str | None, roster_revision: int | None,
) -> dict[str, Any]:
    players = [
        player_row(team, row, title_to_qid.get(row["page_title"]), entities.get(title_to_qid.get(row["page_title"], ""), {}), labels, page_text.get(row["page_title"], ""))
        for row in roster_rows
    ]
    players.sort(key=lambda row: row["name"].split()[-1])
    if len({row["id"] for row in players}) != len(players):
        raise RuntimeError("Open player feed produced duplicate identity keys")
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "roster_as_of": roster_date,
        "team": {"id": team["mlb_id"], "name": team["full_name"]},
        "roster_type": "open-current-roster",
        "player_count": len(players),
        "active_count": sum(row["is_active_roster"] for row in players),
        "source": {
            "name": "Wikimedia, Retrosheet, and Chadwick Baseball Bureau",
            "attribution": "Facts: Wikidata (CC0) · Roster and team history: Wikipedia contributors · Career statistics: Retrosheet",
            "license": "Wikidata CC0 1.0; Wikipedia CC BY-SA 4.0; Chadwick ODC Attribution 1.0; Retrosheet commercial use with required credit",
            "wikidata_url": "https://www.wikidata.org/",
            "roster_url": f"https://en.wikipedia.org/wiki/{quote(roster_template.replace(' ', '_'))}",
            "roster_revision": roster_revision,
            "stats_url": "https://www.retrosheet.org/downloads/csvdownloads.html",
            "stats_through": RETROSHEET_STATS_THROUGH,
            "stats_attribution": RETROSHEET_NOTICE,
        },
        "players": players,
    }


def build_team_feed(
    team: dict[str, Any], cached_stats: dict[str, dict[str, Any]],
    people: list[dict[str, str]], indexed_mlb_people: dict[str, list[dict[str, Any]]],
    skip_new_career_stats: bool = False,
) -> dict[str, Any]:
    roster_template = f"Template:{team['full_name']} roster"
    roster_rows, roster_date, roster_revision = wikipedia_roster(roster_template)
    title_to_qid = wikidata_ids([row["page_title"] for row in roster_rows])
    entities = wikidata_entities(sorted(set(title_to_qid.values())))
    page_text = wikipedia_wikitext([row["page_title"] for row in roster_rows])
    linked_ids: set[str] = set()
    for entity in entities.values():
        for property_id in ("P19", "P69", "P54", "P413"):
            linked_ids.update(entity_ids_for(entity, property_id))
    labels = labels_for(linked_ids)
    feed = build_feed(
        team, roster_template, roster_rows, title_to_qid, entities, labels,
        page_text, roster_date, roster_revision,
    )
    resolve_mlb_ids(feed["players"], indexed_mlb_people)
    if len({player["id"] for player in feed["players"]}) != len(feed["players"]):
        raise RuntimeError("Official player identifier resolution produced a duplicate identity key")
    apply_primary_mlb_positions(feed["players"])
    resolve_retrosheet_ids(feed["players"], people)
    missing_ids = sorted({
        player["retrosheet_id"]
        for player in feed["players"]
        if player["retrosheet_id"] and player["retrosheet_id"] not in cached_stats
    })
    if skip_new_career_stats:
        cached_stats.update({player_id: unavailable_career_stats() for player_id in missing_ids})
    else:
        # Retrosheet's public server is intentionally treated gently; two parallel
        # lookups keep the all-team refresh practical without opening a burst of connections.
        with ThreadPoolExecutor(max_workers=2) as executor:
            cached_stats.update(zip(missing_ids, executor.map(career_stats, missing_ids)))
    for player in feed["players"]:
        retrosheet_id = player["retrosheet_id"]
        player["career_stats"] = cached_stats.get(retrosheet_id) or career_stats(retrosheet_id)
    return feed


def resolve_existing_feeds(teams: list[dict[str, Any]], indexed_mlb_people: dict[str, list[dict[str, Any]]]) -> None:
    """Migrate generated roster IDs without re-fetching unchanged roster templates."""
    for team in teams:
        path = output_path(team)
        feed = json.loads(path.read_text())
        resolve_mlb_ids(feed["players"], indexed_mlb_people)
        if len({player["id"] for player in feed["players"]}) != len(feed["players"]):
            raise RuntimeError("Official player identifier resolution produced a duplicate identity key")
        apply_primary_mlb_positions(feed["players"])
        contents = json.dumps(feed, indent=2, ensure_ascii=False) + "\n"
        path.write_text(contents)
        if team["api_key"] == "redsox":
            IOS_OUTPUT_PATH.write_text(contents)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--team", action="append", default=[],
        help="Team API key, abbreviation, or registry ID. Repeat to refresh several teams.",
    )
    parser.add_argument(
        "--skip-new-career-stats", action="store_true",
        help="Build rosters from cached stats when Retrosheet is temporarily unavailable.",
    )
    parser.add_argument(
        "--skip-new-career-details", action="store_true",
        help="Keep existing detailed career feeds instead of refreshing the current-season provider data.",
    )
    parser.add_argument(
        "--resolve-existing-identifiers", action="store_true",
        help="Resolve official IDs in current generated feeds without re-fetching roster templates.",
    )
    args = parser.parse_args()
    teams = [team_by_key(key) for key in args.team] if args.team else all_teams()
    if args.resolve_existing_identifiers:
        resolve_existing_feeds(teams, current_mlb_people())
        return
    cached_stats = cached_career_stats()
    people = chadwick_people()
    indexed_mlb_people = current_mlb_people()
    expected_career_ids: set[int] = set()
    for team in teams:
        feed = build_team_feed(team, cached_stats, people, indexed_mlb_people, args.skip_new_career_stats)
        contents = json.dumps(feed, indent=2, ensure_ascii=False) + "\n"
        path = output_path(team)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        if team["api_key"] == "redsox":
            IOS_OUTPUT_PATH.write_text(contents)
        write_detailed_careers(feed["players"], args.skip_new_career_details)
        expected_career_ids.update(player["id"] for player in feed["players"])
        print(f"Wrote {feed['player_count']} open-data player profiles for {team['full_name']}")
    if not args.team:
        for path in CAREER_OUTPUT_DIRECTORY.glob("*.json"):
            if path.stem.isdigit() and int(path.stem) not in expected_career_ids:
                path.unlink()


if __name__ == "__main__":
    main()
