#!/usr/bin/env python3
"""Save a small, reviewable MLB/BR source fixture before changing rankings.

This is intentionally a probe, not the production generator.  It records the
shape returned by the two upstream sources (including MLB person ids, team
rows, and Baseball Reference provider ids) so a source change is visible in
review.  Run it for a current and a traded-player season before publishing data.
"""
from __future__ import annotations

import argparse
import gzip
import json
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
MLB = "https://statsapi.mlb.com/api/v1/stats"
WAR = "https://www.baseball-reference.com/data/war_daily_bat.txt"


def get(url: str) -> bytes:
    # Default headers first.  The fallback is solely for bot-specific failures.
    last: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        try:
            with urlopen(Request(url, headers=headers), timeout=60) as response:
                raw = response.read()
                return gzip.decompress(raw) if response.headers.get("Content-Encoding") == "gzip" else raw
        except Exception as exc:  # network errors are reported with the URL below
            last = exc
    raise RuntimeError(f"Could not retrieve {url}: {last}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--season", type=int, default=2026)
    parser.add_argument("--output", type=Path, default=ROOT / "scripts/fixtures")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    query = (f"{MLB}?stats=season&group=hitting&season={args.season}&gameType=R"
             "&playerPool=ALL&leagueId=103&hydrate=person,team&limit=1000")
    mlb = json.loads(get(query))
    splits = (mlb.get("stats") or [{}])[0].get("splits") or []
    fixture = {
        "season": args.season, "request": query,
        "returned_splits": len(splits),
        "first_rows": splits[:5],
        "notes": "Inspect aggregate/stint behavior and person.id before enabling a season.",
    }
    (args.output / f"league-leaders-mlb-{args.season}.json").write_text(json.dumps(fixture, indent=2) + "\n")
    war_lines = get(WAR).decode("utf-8", errors="replace").splitlines()
    (args.output / f"league-leaders-bwar-{args.season}.txt").write_text("\n".join(war_lines[:6]) + "\n")
    print(f"Saved fixtures for {args.season}; MLB population: {len(splits)}")


if __name__ == "__main__":
    main()
