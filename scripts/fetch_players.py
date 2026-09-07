#!/usr/bin/env python3
"""Build the native Players directory from openly reusable Wikimedia data.

Wikidata's structured records are CC0. Wikipedia's current roster template is
used only to identify roster membership, uniform number, and broad position group.
No article prose or player photography is copied.
"""

from __future__ import annotations

import hashlib
import html
import csv
import io
import json
import re
import time
import unicodedata
import zipfile
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "data" / "players.json"
IOS_OUTPUT_PATH = ROOT / "ios" / "Hub Ball" / "Hub Ball" / "players.json"
WIKIPEDIA_API = "https://en.wikipedia.org/w/api.php"
WIKIDATA_API = "https://www.wikidata.org/w/api.php"
ROSTER_TEMPLATE = "Template:Boston Red Sox roster"
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
                    time.sleep(2**attempt)
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


def cached_career_stats() -> dict[str, dict[str, Any]]:
    if not OUTPUT_PATH.exists():
        return {}
    try:
        previous = json.loads(OUTPUT_PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return {
        player["retrosheet_id"]: player["career_stats"]
        for player in previous.get("players", [])
        if player.get("retrosheet_id")
        and player.get("career_stats", {}).get("through_season") == RETROSHEET_STATS_THROUGH
    }


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


def wikipedia_roster() -> tuple[list[dict[str, Any]], str | None, int | None]:
    payload = fetch_json(
        WIKIPEDIA_API,
        {"action": "parse", "page": ROSTER_TEMPLATE, "prop": "wikitext", "format": "json"},
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
    return 900_000_000 + int(hashlib.sha256(name.encode()).hexdigest()[:7], 16)


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


def player_row(roster: dict[str, Any], qid: str | None, entity: dict[str, Any], labels: dict[str, str], wikitext: str) -> dict[str, Any]:
    mlb_id = first_string(entity, "P3541")
    player_id = int(mlb_id) if mlb_id and mlb_id.isdigit() else fallback_id(roster["name"])
    birth_date = first_time(entity, "P569") or wikipedia_birth_date(wikitext)
    birthplace_ids = entity_ids_for(entity, "P19")
    college_ids = entity_ids_for(entity, "P69")
    team_ids = entity_ids_for(entity, "P54")
    teams = wikipedia_teams(wikitext) or [labels[value] for value in team_ids if value in labels]
    wikipedia_title = entity.get("sitelinks", {}).get("enwiki", {}).get("title") or roster["page_title"]
    return {
        "id": player_id,
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


def build_feed(roster_rows: list[dict[str, Any]], title_to_qid: dict[str, str], entities: dict[str, Any], labels: dict[str, str], page_text: dict[str, str], roster_date: str | None, roster_revision: int | None) -> dict[str, Any]:
    players = [
        player_row(row, title_to_qid.get(row["page_title"]), entities.get(title_to_qid.get(row["page_title"], ""), {}), labels, page_text.get(row["page_title"], ""))
        for row in roster_rows
    ]
    players.sort(key=lambda row: row["name"].split()[-1])
    if len({row["id"] for row in players}) != len(players):
        raise RuntimeError("Open player feed produced duplicate identity keys")
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "roster_as_of": roster_date,
        "team": {"id": 111, "name": "Boston"},
        "roster_type": "open-current-roster",
        "player_count": len(players),
        "active_count": sum(row["is_active_roster"] for row in players),
        "source": {
            "name": "Wikimedia, Retrosheet, and Chadwick Baseball Bureau",
            "attribution": "Facts: Wikidata (CC0) · Roster and team history: Wikipedia contributors · Career statistics: Retrosheet",
            "license": "Wikidata CC0 1.0; Wikipedia CC BY-SA 4.0; Chadwick ODC Attribution 1.0; Retrosheet commercial use with required credit",
            "wikidata_url": "https://www.wikidata.org/",
            "roster_url": "https://en.wikipedia.org/wiki/Template:Boston_Red_Sox_roster",
            "roster_revision": roster_revision,
            "stats_url": "https://www.retrosheet.org/downloads/csvdownloads.html",
            "stats_through": RETROSHEET_STATS_THROUGH,
            "stats_attribution": RETROSHEET_NOTICE,
        },
        "players": players,
    }


def main() -> None:
    cached_stats = cached_career_stats()
    roster_rows, roster_date, roster_revision = wikipedia_roster()
    title_to_qid = wikidata_ids([row["page_title"] for row in roster_rows])
    entities = wikidata_entities(sorted(set(title_to_qid.values())))
    page_text = wikipedia_wikitext([row["page_title"] for row in roster_rows])
    linked_ids: set[str] = set()
    for entity in entities.values():
        for property_id in ("P19", "P69", "P54", "P413"):
            linked_ids.update(entity_ids_for(entity, property_id))
    labels = labels_for(linked_ids)
    feed = build_feed(roster_rows, title_to_qid, entities, labels, page_text, roster_date, roster_revision)
    people = chadwick_people()
    resolve_retrosheet_ids(feed["players"], people)
    for player in feed["players"]:
        retrosheet_id = player["retrosheet_id"]
        player["career_stats"] = cached_stats.get(retrosheet_id) or career_stats(retrosheet_id)
    contents = json.dumps(feed, indent=2, ensure_ascii=False) + "\n"
    for path in (OUTPUT_PATH, IOS_OUTPUT_PATH):
        path.write_text(contents)
    print(f"Wrote {feed['player_count']} open-data player profiles to both snapshots")


if __name__ == "__main__":
    main()
