#!/usr/bin/env python3
"""Fetch real Red Sox game-by-game results from the MLB Stats API.

Writes data/seasons.json (the shape the chart engine expects) and data/meta.json.

The MLB Stats API is free and needs no key. Each game carries the team's running
`leagueRecord`, so one call per season gives the full W/L path.

Uses only the standard library so CI needs no dependencies.

    python3 scripts/fetch_seasons.py            # default seasons
    python3 scripts/fetch_seasons.py 2023 2024  # specific seasons
"""
from __future__ import annotations

import json
import pathlib
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

BOS = 111  # MLB team id, Boston Red Sox
SEASONS = [2023, 2024, 2025, 2026]
API = ("https://statsapi.mlb.com/api/v1/schedule"
       "?sportId=1&teamId={team}&season={season}&gameType=R")
ROOT = pathlib.Path(__file__).resolve().parent.parent
CHECKPOINT = 108  # the game the whole story hangs on

# The premise this project is built on. If real data ever disagrees, say so loudly
# rather than quietly shipping a graphic that claims something untrue.
EXPECTED_AT_CHECKPOINT = "57-51"


def fetch_json(url: str, attempts: int = 4) -> dict:
    """GET with retry + backoff. Raises on final failure."""
    last = None
    for i in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "red-sox-records/1.0"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            last = e
            if i < attempts - 1:
                wait = 2 ** i
                print(f"    retry {i+1}/{attempts-1} after {wait}s ({e})", file=sys.stderr)
                time.sleep(wait)
    raise RuntimeError(f"failed to fetch {url}: {last}")


# A game only counts if it was actually played to a result. Beware: MLB marks
# postponed and cancelled games with abstractGameState "Final" too, and those carry
# no winner — counting them is how you end up with a 167-game season.
PLAYED_STATES = {"Final", "Completed Early", "Game Over"}


def season_games(year: int) -> list[dict]:
    """Return completed regular-season games in order, each with the BOS view."""
    payload = fetch_json(API.format(team=BOS, season=year))
    rows, skipped = [], {}
    for date in payload.get("dates", []):
        for g in date.get("games", []):
            st = g.get("status", {})
            detailed = st.get("detailedState", "")
            if st.get("codedGameState") not in ("F", "O") or detailed not in PLAYED_STATES:
                skipped[detailed or "unknown"] = skipped.get(detailed or "unknown", 0) + 1
                continue
            teams = g.get("teams", {})
            for side in ("home", "away"):
                t = teams.get(side, {})
                if t.get("team", {}).get("id") != BOS:
                    continue
                rec = t.get("leagueRecord", {})
                if rec.get("wins") is None or rec.get("losses") is None:
                    continue
                rows.append({
                    "date": g.get("officialDate", ""),
                    # gamePk keeps doubleheaders in the order they were played
                    "pk": g.get("gamePk", 0),
                    "wins": rec["wins"],
                    "losses": rec["losses"],
                })
    rows.sort(key=lambda r: (r["date"], r["pk"]))
    if skipped:
        detail = ", ".join(f"{k}×{v}" for k, v in sorted(skipped.items()))
        print(f"    skipped {sum(skipped.values())} non-played entries ({detail})")
    return rows


def build_season(year: int) -> dict:
    print(f"  {year}: fetching…")
    rows = season_games(year)
    if not rows:
        raise RuntimeError(f"{year}: no completed games returned")

    # Derive each result from the API's own running record rather than from an
    # isWinner flag: if the record did not move, the game did not count, whatever
    # its status said. This makes the totals self-correcting by construction.
    diff, seq = [], []
    w = l = 0
    for r in rows:
        rw, rl = r["wins"], r["losses"]
        if rw == w and rl == l:
            continue                      # record unchanged — not a counted game
        seq.append("W" if rw > w else "L")
        w, l = rw, rl
        diff.append(w - l)

    played = len(diff)
    api_w, api_l = rows[-1]["wins"], rows[-1]["losses"]
    if (w, l) != (api_w, api_l):
        print(f"    WARNING {year}: computed {w}-{l} but API reports {api_w}-{api_l}",
              file=sys.stderr)
    if played != w + l:
        print(f"    WARNING {year}: {played} games but record totals {w + l}", file=sys.stderr)
    if played > 162:
        print(f"    WARNING {year}: {played} games exceeds a 162-game season", file=sys.stderr)
    # A season is still in progress if it hasn't reached a full 162-game slate.
    in_progress = played < 162
    out = {
        "diff": diff,
        "seq": "".join(seq),
        "record": f"{w}-{l}",
        "end_game": played,
        "in_progress": in_progress,
        "last_game_date": rows[-1]["date"],
    }

    note = " (in progress)" if in_progress else ""
    print(f"    {played} games · {w}-{l}{note} · through {rows[-1]['date']}")
    if played >= CHECKPOINT:
        d = diff[CHECKPOINT - 1]
        cw = (CHECKPOINT + d) // 2
        cl = CHECKPOINT - cw
        out["checkpoint_record"] = f"{cw}-{cl}"
        flag = "OK" if out["checkpoint_record"] == EXPECTED_AT_CHECKPOINT else "MISMATCH"
        print(f"    after game {CHECKPOINT}: {out['checkpoint_record']}  [{flag}]")
    return out


def main() -> int:
    years = [int(a) for a in sys.argv[1:]] or SEASONS
    print(f"Fetching Red Sox seasons {years} from MLB Stats API")

    seasons = {}
    for y in years:
        seasons[str(y)] = build_season(y)

    # Headline check: is the premise of the graphic still true?
    checks = {y: s.get("checkpoint_record") for y, s in seasons.items() if s.get("checkpoint_record")}
    all_match = checks and all(v == EXPECTED_AT_CHECKPOINT for v in checks.values())
    print("\n" + "=" * 58)
    print(f"CHECKPOINT (game {CHECKPOINT}): " +
          " · ".join(f"{y} {v}" for y, v in sorted(checks.items())))
    print(f"PREMISE ({EXPECTED_AT_CHECKPOINT} every season): "
          f"{'CONFIRMED' if all_match else 'DOES NOT HOLD — review the story copy'}")
    print("=" * 58 + "\n")

    (ROOT / "data").mkdir(exist_ok=True)
    (ROOT / "data/seasons.json").write_text(json.dumps(seasons, indent=1) + "\n")

    meta = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source": "MLB Stats API (statsapi.mlb.com)",
        "team_id": BOS,
        "seasons": {y: {"record": s["record"], "games": s["end_game"],
                        "in_progress": s["in_progress"],
                        "checkpoint_record": s.get("checkpoint_record")}
                    for y, s in seasons.items()},
        "checkpoint_game": CHECKPOINT,
        "premise_holds": bool(all_match),
    }
    (ROOT / "data/meta.json").write_text(json.dumps(meta, indent=1) + "\n")
    print("Wrote data/seasons.json and data/meta.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
