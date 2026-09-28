#!/usr/bin/env python3
"""Build a fresh, trusted news feed for the current postseason field."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlsplit, urlunsplit

from team_registry import ROOT, all_teams
from fetch_team_news import source_feed


DEFAULT_WINDOW_HOURS = 12
MAX_ARTICLES = 40
BLOCKED_TITLE_PHRASES = (
    "best things to do",
    "how to buy",
    "how to watch",
    "live stream",
    "streaming guide",
    "tickets for",
    "where to buy",
)


def parse_timestamp(value: str) -> datetime | None:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)
    except (AttributeError, TypeError, ValueError):
        return None


def canonical_url(value: str) -> str:
    parts = urlsplit(value)
    if parts.scheme not in {"http", "https"} or not parts.netloc:
        return ""
    return urlunsplit((parts.scheme.lower(), parts.netloc.lower(), parts.path.rstrip("/"), "", ""))


def normalized_title(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def feed_path(team: dict[str, Any], source: dict[str, str], data_root: Path) -> Path:
    team_path = data_root / team["data_directory"] / f"{source['key']}.json"
    if team_path.exists() or not team.get("legacy_root_data"):
        return team_path
    return data_root / f"{source['key']}.json"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def load_cached_source(
    _team: dict[str, Any], _source: dict[str, str], path: Path
) -> dict[str, Any]:
    return load_json(path)


def fetch_live_source(
    team: dict[str, Any], source: dict[str, str], _path: Path
) -> dict[str, Any]:
    return source_feed(team, source)


def build_feed(
    season: int,
    history: dict[str, Any],
    registry: list[dict[str, Any]],
    data_root: Path,
    now: datetime,
    window_hours: int = DEFAULT_WINDOW_HOURS,
    loader: Callable[[dict[str, Any], dict[str, str], Path], dict[str, Any]] = load_cached_source,
) -> tuple[dict[str, Any], list[str]]:
    if history.get("schemaVersion") != 1 or history.get("season") != season:
        raise ValueError(f"Postseason history snapshot does not describe {season}")

    teams_by_id = {team["mlb_id"]: team for team in registry}
    postseason_teams = history.get("teams", [])
    cutoff = now.astimezone(timezone.utc) - timedelta(hours=window_hours)
    candidates: list[dict[str, Any]] = []
    warnings: list[str] = []

    for postseason_team in postseason_teams:
        team_id = postseason_team.get("teamId")
        team = teams_by_id.get(team_id)
        if not team:
            warnings.append(f"No configured team found for MLB team {team_id}")
            continue
        for source in team.get("news_sources", []):
            path = feed_path(team, source, data_root)
            try:
                source_payload = loader(team, source, path)
            except Exception as exc:
                warnings.append(f"{team['full_name']} / {source['name']}: {exc}")
                continue
            for article in source_payload.get("articles", []):
                title = str(article.get("title", "")).strip()
                published = parse_timestamp(article.get("published", ""))
                article_url = str(article.get("url", "")).strip()
                url_key = canonical_url(article_url)
                if (
                    not title or not published or published < cutoff or published > now
                    or not url_key
                    or any(phrase in title.lower() for phrase in BLOCKED_TITLE_PHRASES)
                ):
                    continue
                candidates.append({
                    "title": title,
                    "description": str(article.get("description", "")).strip(),
                    "url": article_url,
                    "published": published.isoformat(),
                    "source": str(source_payload.get("source") or source["name"]),
                    "teamId": team_id,
                    "teamName": team["full_name"],
                    "teamAbbreviation": team["abbreviation"],
                    "league": team["league"],
                })

    candidates.sort(key=lambda article: article["published"], reverse=True)
    articles: list[dict[str, Any]] = []
    seen_urls: set[str] = set()
    seen_titles: set[str] = set()
    for article in candidates:
        title_key = normalized_title(article["title"])
        url_key = canonical_url(article["url"])
        if url_key in seen_urls or title_key in seen_titles:
            continue
        seen_urls.add(url_key)
        seen_titles.add(title_key)
        articles.append(article)
        if len(articles) == MAX_ARTICLES:
            break

    covered_team_ids = {article["teamId"] for article in articles}
    return ({
        "schemaVersion": 1,
        "season": season,
        "generatedAt": now.astimezone(timezone.utc).isoformat(),
        "windowHours": window_hours,
        "source": "Configured team newspapers and The Athletic via Bing News RSS",
        "sourceURL": "https://www.bing.com/news/search",
        "teamCount": len(postseason_teams),
        "coveredTeamCount": len(covered_team_ids),
        "articles": articles,
    }, warnings)


def write_if_changed(path: Path, feed: dict[str, Any]) -> bool:
    try:
        current = json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        current = None
    if current and current.get("articles") == feed["articles"]:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--season", type=int, default=datetime.now(timezone.utc).year)
    parser.add_argument("--hours", type=int, default=DEFAULT_WINDOW_HOURS)
    parser.add_argument(
        "--cached", action="store_true",
        help="Aggregate committed source snapshots instead of fetching live RSS.",
    )
    args = parser.parse_args()
    if args.hours <= 0:
        parser.error("--hours must be positive")

    history_path = ROOT / "data" / "postseason-history" / f"{args.season}.json"
    output_path = ROOT / "data" / "postseason-news" / f"{args.season}.json"
    try:
        history = load_json(history_path)
        feed, warnings = build_feed(
            args.season,
            history,
            all_teams(),
            ROOT / "data",
            datetime.now(timezone.utc),
            args.hours,
            load_cached_source if args.cached else fetch_live_source,
        )
    except (FileNotFoundError, json.JSONDecodeError, OSError, ValueError) as exc:
        print(f"ERROR: Could not build postseason news: {exc}", file=sys.stderr)
        return 1

    changed = write_if_changed(output_path, feed)
    action = "wrote" if changed else "unchanged"
    print(
        f"Postseason news: {action} {output_path}; "
        f"{len(feed['articles'])} articles across "
        f"{feed['coveredTeamCount']}/{feed['teamCount']} teams."
    )
    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
