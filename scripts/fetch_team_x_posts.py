#!/usr/bin/env python3
"""Generate official-team X snapshots for Hub Ball's resilient feed fallback."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from fetch_x_posts import NextDataParser, fetch_bytes, post_from_tweet
from team_registry import ROOT, all_teams, team_by_key


MAX_RECENT_POSTS = 24
MAX_POPULAR_POSTS = 12


def source_url(team: dict[str, Any]) -> str:
    return f"https://x.com/{team['x_handle']}"


def timeline_url(team: dict[str, Any]) -> str:
    return (
        "https://syndication.twitter.com/srv/timeline-profile/screen-name/"
        f"{team['x_handle']}?lang=en&theme=light&showHeader=false&hideBorder=true"
    )


def output_path(team: dict[str, Any]) -> Path:
    if team["api_key"] == "redsox":
        return ROOT / "data" / "x-posts.json"
    return ROOT / "data" / team["data_directory"] / "x-posts.json"


def fetch_entries(team: dict[str, Any]) -> list[dict[str, Any]]:
    parser = NextDataParser()
    body = fetch_bytes(timeline_url(team), "__NEXT_DATA__")
    parser.feed(body.decode("utf-8", errors="replace"))
    if not parser.parts:
        raise RuntimeError("X profile response did not contain timeline data")
    payload = json.loads("".join(parser.parts))
    return payload["props"]["pageProps"]["timeline"]["entries"]


def build_feed(team: dict[str, Any], entries: list[dict[str, Any]]) -> dict[str, Any]:
    posts: list[dict[str, Any]] = []
    seen: set[str] = set()
    for entry in entries:
        tweet = (entry.get("content") or {}).get("tweet") or {}
        post = post_from_tweet(tweet)
        if post is None or not post["id"] or post["id"] in seen:
            continue
        seen.add(post["id"])
        posts.append(post)
    if not posts:
        raise RuntimeError(f"The @{team['x_handle']} profile returned no usable X posts")

    posts.sort(key=lambda post: post["published"], reverse=True)
    cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
    popular = []
    for post in posts:
        try:
            if datetime.fromisoformat(post["published"]) >= cutoff:
                popular.append(post)
        except (TypeError, ValueError):
            continue
    popular.sort(key=lambda post: (post["likes"], post["published"]), reverse=True)
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "X",
        "source_url": source_url(team),
        "recent": posts[:MAX_RECENT_POSTS],
        "popular": popular[:MAX_POPULAR_POSTS],
    }


def write_feed(path: Path, feed: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(feed['recent'])} official-team X posts to {path}")


def install_artifacts(directory: Path) -> None:
    for team in all_teams():
        if team["api_key"] == "redsox":
            continue
        artifact = directory / f"{team['api_key']}.json"
        feed = json.loads(artifact.read_text())
        if feed.get("source") != "X" or not feed.get("recent"):
            raise RuntimeError(f"Invalid X snapshot artifact: {artifact}")
        write_feed(output_path(team), feed)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team", help="Registry key for one official team profile")
    parser.add_argument("--output", type=Path, help="Optional artifact output path")
    parser.add_argument("--install-artifacts", type=Path)
    args = parser.parse_args()
    if args.install_artifacts:
        if args.team or args.output:
            parser.error("--install-artifacts cannot be combined with fetch options")
        install_artifacts(args.install_artifacts)
        return
    if not args.team:
        parser.error("--team is required when fetching")
    team = team_by_key(args.team)
    write_feed(args.output or output_path(team), build_feed(team, fetch_entries(team)))


if __name__ == "__main__":
    main()
