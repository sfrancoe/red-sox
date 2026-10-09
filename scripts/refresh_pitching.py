#!/usr/bin/env python3
"""One policy-controlled, paced Above the Forecast refresh for all MLB teams."""
from __future__ import annotations

import argparse
import importlib
import json
import math
import sys
import tempfile
import time
from datetime import date, datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from http_refresh import FALLBACK_USER_AGENT, fetch_json
from team_registry import all_teams, team_by_key

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "config" / "pitching-refresh.json"
# Boston's pitching still comes from its own script (root data path); every
# other team uses the shared fetch_team_data builder.
LEGACY = {"redsox": "fetch_pitching"}


def load_policy() -> dict[str, Any]:
    policy = json.loads(POLICY.read_text())
    if policy["season"] != policy["projection_season"]:
        raise RuntimeError("Projection season must match the configured actual season")
    if date.fromisoformat(policy["refresh_until"]).year != policy["season"]:
        raise RuntimeError("Refresh end date must belong to the configured season")
    if policy["request_spacing_seconds"] < 10 or policy["budget_seconds"] <= 45:
        raise RuntimeError("Pitching requires at least 10-second spacing and a usable budget")
    return policy


def refresh_allowed(policy: dict[str, Any], today: date) -> bool:
    return today.year == policy["season"] and today <= date.fromisoformat(policy["refresh_until"])


def output_path(team: dict[str, Any], root: Path = ROOT) -> Path:
    return root / "data" / ("" if team["legacy_root_data"] else team["data_directory"]) / "pitching.json"


class RateLimited(RuntimeError):
    pass


class FanGraphsClient:
    """Pace every attempt; never shorten a provider's requested cooldown."""
    def __init__(self, spacing: float = 10, budget: float = 1800) -> None:
        self.spacing = spacing
        self.deadline = time.monotonic() + budget
        self.next_request = time.monotonic()

    def get(self, url: str) -> Any:
        for attempt in range(2):
            now = time.monotonic()
            wait = max(0, self.next_request - now)
            if now + wait + 45 > self.deadline:
                raise RuntimeError("FanGraphs cooldown/request exceeds remaining refresh budget")
            if wait:
                time.sleep(wait)
            self.next_request = time.monotonic() + self.spacing
            try:
                headers = {} if attempt == 0 else {"User-Agent": FALLBACK_USER_AGENT}
                with urlopen(Request(url, headers=headers), timeout=45) as response:
                    return json.load(response)
            except HTTPError as exc:
                if exc.code == 429:
                    value = exc.headers.get("Retry-After", "") if exc.headers else ""
                    try:
                        delay = float(value)
                        if not math.isfinite(delay) or delay < 0:
                            raise ValueError("Invalid Retry-After seconds")
                    except ValueError:
                        try:
                            delay = max(0, (parsedate_to_datetime(value) - datetime.now(timezone.utc)).total_seconds())
                        except (TypeError, ValueError, OverflowError):
                            delay = 300
                    self.next_request = max(self.next_request, time.monotonic() + delay)
                    raise RateLimited(f"HTTP 429 for {url}; cooldown {delay:.0f}s") from exc
                if exc.code not in (403, 500, 502, 503, 504) or attempt:
                    raise RuntimeError(f"FanGraphs request failed: {exc}") from exc
            except (URLError, TimeoutError, json.JSONDecodeError) as exc:
                if attempt:
                    raise RuntimeError(f"FanGraphs request failed: {exc}") from exc
        raise RuntimeError("FanGraphs request exhausted retries")


def build_team(team: dict[str, Any], projections: list, season: int, client: FanGraphsClient) -> dict:
    module = importlib.import_module(LEGACY.get(team["api_key"], "fetch_team_data"))
    actual = client.get(module.ACTUAL_API.format(season=season, team=team["fangraphs_id"]))
    league = 103 if team["league"] == "AL" else 104
    standings = fetch_json(module.STANDINGS_API.format(league=league, season=season))
    if not isinstance(actual, dict) or not isinstance(actual.get("data"), list):
        raise RuntimeError("FanGraphs returned invalid actuals")
    if not all(isinstance(row, dict) for row in actual["data"]) or not isinstance(standings, dict):
        raise RuntimeError("Invalid actuals or MLB standings response")
    if team["api_key"] in LEGACY:
        return module.build_feed(projections, actual, standings, season)
    return module.build_pitching_feed(team, projections, actual, standings, season)


def write_snapshot(path: Path, feed: dict[str, Any]) -> None:
    """Only replace a last-good file after a complete JSON write succeeds."""
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        current = json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        current = {}
    if all(current.get(key) == value for key, value in feed.items() if key != "generated_at"):
        print(f"Unchanged {path}")
        return
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print(f"Wrote {path}")


def refresh(teams: list[dict], policy: dict, root: Path = ROOT, today: date | None = None,
            force: bool = False) -> list[str]:
    if not force and not refresh_allowed(policy, today or datetime.now(timezone.utc).date()):
        print(f"Pitching season {policy['season']} is frozen; retained all snapshots")
        return []
    client = FanGraphsClient(policy["request_spacing_seconds"], policy["budget_seconds"])
    try:
        try:
            projections = client.get(policy["projections_url"])
        except RateLimited:
            projections = client.get(policy["projections_url"])  # One deferred retry, same cooldown.
        if not isinstance(projections, list) or not projections or not all(isinstance(row, dict) for row in projections):
            raise RuntimeError("FanGraphs returned empty or invalid projections")
    except RuntimeError as exc:
        print(f"ERROR: shared projections failed; retained all snapshots: {exc}", file=sys.stderr)
        return [team["api_key"] for team in teams]
    failed: dict[str, str] = {}
    deferred = []

    def attempt(team: dict, retry: bool = False) -> None:
        key = team["api_key"]
        try:
            feed = build_team(team, projections, policy["season"], client)
            write_snapshot(output_path(team, root), feed)
            failed.pop(key, None)
        except RateLimited as exc:
            failed[key] = str(exc)
            if not retry:
                deferred.append(team)
        except (RuntimeError, ValueError, KeyError, StopIteration, TypeError, OSError) as exc:
            failed[key] = str(exc)

    for team in teams:
        attempt(team)
    for team in deferred:
        attempt(team, retry=True)
    for key, error in failed.items():
        print(f"ERROR: {key}: {error}; retained last-good snapshot", file=sys.stderr)
    return list(failed)


def main(default_teams: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--team", action="append", default=[])
    parser.add_argument("--force", action="store_true", help="Explicitly refresh the configured season after freeze")
    args = parser.parse_args()
    keys = args.team or default_teams
    teams = [team_by_key(key) for key in keys] if keys else all_teams()
    failed = refresh(teams, load_policy(), force=args.force)
    if failed:
        raise SystemExit("Incomplete pitching refresh: " + ", ".join(failed))


if __name__ == "__main__":
    main()
