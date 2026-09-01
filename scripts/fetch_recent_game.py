#!/usr/bin/env python3
"""Fetch the most recent completed Red Sox game and build a compact recap."""

from __future__ import annotations

import json
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo


BOS = 111
ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "data" / "recent-game.json"
SCHEDULE_API = (
    "https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId={team}"
    "&startDate={start}&endDate={end}&gameType=R"
)
LIVE_API = "https://statsapi.mlb.com/api/v1.1/game/{game_pk}/feed/live"
CONTENT_API = "https://statsapi.mlb.com/api/v1/game/{game_pk}/content"
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
EASTERN = ZoneInfo("America/New_York")


def fetch_json(url: str, required: bool = True) -> dict[str, Any]:
    """Use normal request defaults first, then the approved fallback UA."""
    last_error: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        for attempt in range(3):
            try:
                request = Request(url, headers=headers)
                with urlopen(request, timeout=30) as response:
                    return json.load(response)
            except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
                last_error = exc
                if attempt < 2:
                    time.sleep(2**attempt)
        if headers:
            break
    if required:
        raise RuntimeError(f"Could not fetch {url}: {last_error}")
    return {}


def latest_final_game(today) -> int:
    start = today - timedelta(days=14)
    url = SCHEDULE_API.format(team=BOS, start=start.isoformat(), end=today.isoformat())
    payload = fetch_json(url)
    finals = []
    for date_entry in payload.get("dates", []):
        for game in date_entry.get("games", []):
            if (game.get("status") or {}).get("abstractGameState") == "Final":
                finals.append(game)
    if not finals:
        raise RuntimeError("No completed Red Sox game found in the past 14 days")
    finals.sort(key=lambda game: (game.get("gameDate") or "", game.get("gamePk") or 0))
    return int(finals[-1]["gamePk"])


def record(team: dict[str, Any]) -> str:
    league = (team.get("record") or {}).get("leagueRecord") or {}
    wins, losses = league.get("wins"), league.get("losses")
    return f"{wins}-{losses}" if wins is not None and losses is not None else "—"


def ordinal(value: int) -> str:
    if 10 < value % 100 < 14:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(value % 10, "th")
    return f"{value}{suffix}"


def player_rows(team_box: dict[str, Any], role: str) -> list[dict[str, Any]]:
    players = team_box.get("players") or {}
    ids = team_box.get("batters" if role == "batting" else "pitchers") or []
    rows = []
    for order, player_id in enumerate(ids):
        player = players.get(f"ID{player_id}") or {}
        stats = (player.get("stats") or {}).get(role) or {}
        if role == "batting" and not stats.get("plateAppearances"):
            continue
        if role == "pitching" and not stats.get("gamesPitched"):
            continue
        base = {
            "name": (player.get("person") or {}).get("fullName") or "Player",
            "position": (player.get("position") or {}).get("abbreviation") or "",
            "note": stats.get("note") or "",
            "order": order,
        }
        if role == "batting":
            base.update({key: stats.get(key, 0) for key in (
                "atBats", "runs", "hits", "rbi", "baseOnBalls", "strikeOuts",
                "leftOnBase", "homeRuns"
            )})
            season_batting = (player.get("seasonStats") or {}).get("batting") or {}
            base["average"] = season_batting.get("avg") or ".---"
            base["season_home_runs"] = int(season_batting.get("homeRuns") or 0)
        else:
            base.update({key: stats.get(key, 0) for key in (
                "inningsPitched", "hits", "runs", "earnedRuns", "baseOnBalls",
                "strikeOuts", "homeRuns", "numberOfPitches"
            )})
        rows.append(base)
    return rows


def team_payload(side: str, game_data: dict[str, Any], live_data: dict[str, Any]) -> dict[str, Any]:
    team = game_data["teams"][side]
    box = live_data["boxscore"]["teams"][side]
    totals = live_data["linescore"]["teams"][side]
    return {
        "side": side,
        "id": team.get("id"),
        "name": team.get("name"),
        "club_name": team.get("teamName") or team.get("clubName") or team.get("name"),
        "abbreviation": team.get("abbreviation"),
        "record": record(team),
        "runs": totals.get("runs", 0),
        "hits": totals.get("hits", 0),
        "errors": totals.get("errors", 0),
        "left_on_base": totals.get("leftOnBase", 0),
        "batting": player_rows(box, "batting"),
        "pitching": player_rows(box, "pitching"),
        "team_batting": (box.get("teamStats") or {}).get("batting") or {},
    }


def decision(live_data: dict[str, Any], key: str) -> str:
    return ((live_data.get("decisions") or {}).get(key) or {}).get("fullName") or ""


def possessive(name: str) -> str:
    return f"{name}’" if name.endswith("s") else f"{name}’s"


def scoring_action(play: dict[str, Any]) -> str:
    batter = play.get("batter") or "Boston"
    event = str(play.get("event") or "scoring play").lower()
    event = {
        "sac fly": "sacrifice fly",
        "field error": "error",
    }.get(event, event)
    runs = int(play.get("rbi") or 0)
    run_label = {2: "two-run ", 3: "three-run ", 4: "grand slam "}.get(runs, "")
    if runs == 4 and event == "home run":
        event = ""
    return f"{possessive(batter)} {run_label}{event}".strip()


def build_summary(boston: dict[str, Any], opponent: dict[str, Any], venue: str,
                  scoring: list[dict[str, Any]]) -> str:
    br, oruns = boston["runs"], opponent["runs"]
    score = f"{br}–{oruns}"
    opponent_name = opponent["club_name"]
    annotated = []
    away_score = home_score = 0
    for play in scoring:
        before_boston = away_score if boston["side"] == "away" else home_score
        before_opponent = home_score if boston["side"] == "away" else away_score
        away_score = int(play.get("away_score") or 0)
        home_score = int(play.get("home_score") or 0)
        after_boston = away_score if boston["side"] == "away" else home_score
        after_opponent = home_score if boston["side"] == "away" else away_score
        annotated.append({
            **play,
            "before_boston": before_boston,
            "before_opponent": before_opponent,
            "after_boston": after_boston,
            "after_opponent": after_opponent,
        })

    if br > oruns:
        largest_deficit = max(
            (play["after_opponent"] - play["after_boston"] for play in annotated),
            default=0,
        )
        deficit_index = max(
            range(len(annotated)),
            key=lambda index: annotated[index]["after_opponent"] - annotated[index]["after_boston"],
            default=0,
        )
        go_ahead = [
            play for play in annotated
            if play["after_boston"] > play["before_boston"]
            and play["before_boston"] <= play["before_opponent"]
            and play["after_boston"] > play["after_opponent"]
        ]
        winning_play = go_ahead[-1] if go_ahead else None
        walkoff = (
            winning_play is not None
            and boston["side"] == "home"
            and int(winning_play.get("inning_num") or 0) >= 9
            and winning_play is annotated[-1]
        )

        if walkoff:
            first = (
                f"{winning_play.get('batter') or 'Boston'} delivered a walk-off "
                f"{str(winning_play.get('event') or 'hit').lower()} in the "
                f"{ordinal(int(winning_play['inning_num']))} inning as the Red Sox rallied past "
                f"the {opponent_name}, {score}, at {venue}."
            )
        elif largest_deficit >= 2:
            first = (
                f"The Red Sox erased a {largest_deficit}-run deficit to beat the "
                f"{opponent_name}, {score}, at {venue}."
            )
        elif oruns == 0:
            first = f"The Red Sox shut out the {opponent_name}, {score}, at {venue}."
        else:
            first = f"The Red Sox beat the {opponent_name}, {score}, at {venue}."

        details = []
        if largest_deficit >= 2 and annotated:
            low_point = annotated[deficit_index]
            rally_play = next((
                play for play in annotated[deficit_index + 1:]
                if play["after_boston"] > play["before_boston"]
            ), None)
            if rally_play:
                remaining = rally_play["after_opponent"] - rally_play["after_boston"]
                effect = (
                    "tied the game" if remaining == 0
                    else "put Boston ahead" if remaining < 0
                    else f"cut the deficit to {'one' if remaining == 1 else remaining}"
                )
                details.append(
                    f"Boston trailed {low_point['after_opponent']}–{low_point['after_boston']} before "
                    f"{scoring_action(rally_play)} in the {ordinal(int(rally_play['inning_num']))} "
                    f"{effect}."
                )

        tying_play = next((
            play for play in annotated[deficit_index + 1:]
            if play["after_boston"] > play["before_boston"]
            and play["before_boston"] < play["before_opponent"]
            and play["after_boston"] == play["after_opponent"]
        ), None)
        if walkoff and tying_play and tying_play is not winning_play:
            innings_later = int(winning_play["inning_num"]) - int(tying_play["inning_num"])
            timing = "one inning later" if innings_later == 1 else "later"
            details.append(
                f"{scoring_action(tying_play)} tied it in the "
                f"{ordinal(int(tying_play['inning_num']))}, and "
                f"{winning_play.get('batter') or 'Boston'} completed the comeback "
                f"{timing}."
            )
        return " ".join([first, *details])

    largest_lead = max(
        (play["after_boston"] - play["after_opponent"] for play in annotated),
        default=0,
    )
    if br == 0:
        first = f"The Red Sox were shut out by the {opponent_name}, {oruns}–{br}, at {venue}."
    elif largest_lead >= 2:
        first = (
            f"The Red Sox couldn’t hold a {largest_lead}-run lead and fell to the "
            f"{opponent_name}, {oruns}–{br}, at {venue}."
        )
    else:
        first = f"The Red Sox fell to the {opponent_name}, {oruns}–{br}, at {venue}."
    return first


def interesting_facts(boston: dict[str, Any], opponent: dict[str, Any], innings_count: int) -> list[str]:
    facts = []
    if innings_count > 9:
        facts.append(f"The game went {innings_count} innings.")
    if boston["runs"] == 0:
        facts.append(f"The Red Sox were held scoreless despite putting {boston['hits']} hits on the board.")
    elif opponent["runs"] == 0:
        facts.append(f"Red Sox pitchers combined for a {innings_count}-inning shutout.")

    earned = sum(int(row.get("earnedRuns") or 0) for row in boston["pitching"])
    unearned = max(0, opponent["runs"] - earned)
    if boston["errors"] >= 2:
        detail = f"; {unearned} opponent runs were unearned" if unearned else ""
        facts.append(f"The Red Sox committed {boston['errors']} errors{detail}.")

    opponent_batting = opponent.get("team_batting") or {}
    steals = int(opponent_batting.get("stolenBases") or 0)
    caught = int(opponent_batting.get("caughtStealing") or 0)
    if steals >= 3:
        facts.append(f"The {opponent['club_name']} went {steals}-for-{steals + caught} on stolen-base attempts.")

    top_hitter = max(boston["batting"], key=lambda row: int(row.get("hits") or 0), default=None)
    if top_hitter and int(top_hitter.get("hits") or 0) >= 2:
        facts.append(
            f"{top_hitter['name']} collected {top_hitter['hits']} of the Red Sox’s {boston['hits']} hits."
        )

    homers = [row for row in boston["batting"] if int(row.get("homeRuns") or 0)]
    if homers:
        names = ", ".join(
            f"{row['name']} ({row['season_home_runs']})" for row in homers
        )
        total = sum(int(row["homeRuns"]) for row in homers)
        facts.append(f"The Red Sox hit {total} home run{'s' if total != 1 else ''}: {names}.")

    starter = boston["pitching"][0] if boston["pitching"] else None
    if starter:
        earned_runs = int(starter["earnedRuns"] or 0)
        facts.append(
            f"{starter['name']} worked {starter['inningsPitched']} innings, allowed "
            f"{earned_runs} earned run{'s' if earned_runs != 1 else ''}, and struck out {starter['strikeOuts']}."
        )
    return facts[:5]


def recap_metadata(content: dict[str, Any]) -> dict[str, str]:
    recap = (((content.get("editorial") or {}).get("recap") or {}).get("mlb") or {})
    slug = str(recap.get("slug") or "").strip()
    return {
        "headline": str(recap.get("headline") or "").strip(),
        "url": f"https://www.mlb.com/news/{slug}" if slug else "",
    }


def build_feed(live: dict[str, Any], content: dict[str, Any]) -> dict[str, Any]:
    game_data = live["gameData"]
    live_data = live["liveData"]
    game_info = game_data.get("gameInfo") or {}
    away = team_payload("away", game_data, live_data)
    home = team_payload("home", game_data, live_data)
    boston = away if away["id"] == BOS else home
    opponent = home if boston is away else away
    innings = live_data["linescore"].get("innings") or []
    venue = (game_data.get("venue") or {}).get("name") or "the ballpark"

    scoring = []
    all_plays = (live_data.get("plays") or {}).get("allPlays") or []
    for index in (live_data.get("plays") or {}).get("scoringPlays") or []:
        play = all_plays[index]
        about, result = play.get("about") or {}, play.get("result") or {}
        matchup = play.get("matchup") or {}
        scoring.append({
            "inning": f"{about.get('halfInning', '').title()} {about.get('inning', '')}",
            "inning_num": about.get("inning", 0),
            "half": about.get("halfInning", ""),
            "batter": (matchup.get("batter") or {}).get("fullName") or "",
            "event": result.get("event") or "",
            "rbi": result.get("rbi", 0),
            "description": result.get("description") or result.get("event") or "Scoring play",
            "away_score": result.get("awayScore", 0),
            "home_score": result.get("homeScore", 0),
        })

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "MLB Stats API",
        "game_pk": live.get("gamePk"),
        "game_date": (game_data.get("datetime") or {}).get("dateTime") or "",
        "venue": venue,
        "game_duration_minutes": game_info.get("gameDurationMinutes"),
        "attendance": game_info.get("attendance"),
        "innings_count": len(innings),
        "result": "Win" if boston["runs"] > opponent["runs"] else "Loss",
        "summary": build_summary(boston, opponent, venue, scoring),
        "facts": interesting_facts(boston, opponent, len(innings)),
        "decisions": {
            "winner": decision(live_data, "winner"),
            "loser": decision(live_data, "loser"),
            "save": decision(live_data, "save"),
        },
        "away": away,
        "home": home,
        "innings": innings,
        "scoring_plays": scoring,
        "official_recap": recap_metadata(content),
        "gameday_url": f"https://www.mlb.com/gameday/{live.get('gamePk')}",
    }


def feed_changed(feed: dict[str, Any]) -> bool:
    try:
        current = json.loads(OUTPUT_PATH.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return True
    keys = tuple(key for key in feed if key != "generated_at")
    return any(current.get(key) != feed.get(key) for key in keys)


def main() -> None:
    today = datetime.now(EASTERN).date()
    game_pk = latest_final_game(today)
    live = fetch_json(LIVE_API.format(game_pk=game_pk))
    content = fetch_json(CONTENT_API.format(game_pk=game_pk), required=False)
    feed = build_feed(live, content)
    if not feed_changed(feed):
        print(f"No recent game changes; kept {OUTPUT_PATH}")
        return
    OUTPUT_PATH.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote recent game {game_pk} to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
