#!/usr/bin/env python3
"""Generate official-team X snapshots for Hub Ball's resilient feed fallback."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

from fetch_x_posts import NextDataParser, fetch_bytes, post_from_tweet
from team_registry import ROOT, all_teams, team_by_key


MAX_RECENT_POSTS = 24
MAX_POPULAR_POSTS = 12
MLB_CLUBS_LIST_URL = (
    "https://syndication.twitter.com/srv/timeline-list/"
    "screen-name/MLB/slug/clubs?lang=en&theme=light&showHeader=false&hideBorder=true"
)


def source_url(team: dict[str, Any]) -> str:
    return f"https://x.com/{team['x_handle']}"


def output_path(team: dict[str, Any]) -> Path:
    if team["api_key"] == "redsox":
        return ROOT / "data" / "x-posts.json"
    return ROOT / "data" / team["data_directory"] / "x-posts.json"


def fetch_entries() -> list[dict[str, Any]]:
    parser = NextDataParser()
    body = fetch_bytes(MLB_CLUBS_LIST_URL, "__NEXT_DATA__")
    parser.feed(body.decode("utf-8", errors="replace"))
    if not parser.parts:
        raise RuntimeError("X profile response did not contain timeline data")
    payload = json.loads("".join(parser.parts))
    return payload["props"]["pageProps"]["timeline"]["entries"]


class ParagraphParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.in_paragraph = False
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "p":
            self.in_paragraph = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "p":
            self.in_paragraph = False

    def handle_data(self, data: str) -> None:
        if self.in_paragraph:
            self.parts.append(data)


def seed_post(team: dict[str, Any]) -> dict[str, Any]:
    url = team.get("x_seed_post_url")
    if not url:
        raise RuntimeError(f"The MLB clubs list has no current @{team['x_handle']} post")
    endpoint = "https://publish.twitter.com/oembed?" + urlencode({
        "url": url, "omit_script": "true", "dnt": "true",
    })
    payload = json.loads(fetch_bytes(endpoint, '"provider_name"').decode())
    author_url = str(payload.get("author_url") or "")
    if author_url.rstrip("/").split("/")[-1].lower() != team["x_handle"].lower():
        raise RuntimeError(f"Seed post author does not match @{team['x_handle']}")
    parser = ParagraphParser()
    parser.feed(str(payload.get("html") or ""))
    text = re.sub(r"\s+", " ", "".join(parser.parts)).strip()
    match = re.search(r"/status/(\d+)", url)
    if not text or not match:
        raise RuntimeError(f"Seed post is incomplete for @{team['x_handle']}")
    post_id = match.group(1)
    timestamp_ms = (int(post_id) >> 22) + 1288834974657
    published = datetime.fromtimestamp(timestamp_ms / 1000, timezone.utc).isoformat()
    return {
        "id": post_id, "text": text, "url": url, "published": published,
        "likes": 0, "author": str(payload.get("author_name") or team["full_name"]),
        "handle": team["x_handle"], "avatar": "", "media": "",
        "quoted_text": "", "quoted_author": "", "quoted_handle": "",
    }


def existing_feed_is_usable(path: Path, team: dict[str, Any]) -> bool:
    try:
        feed = json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return False
    recent = feed.get("recent")
    if feed.get("source") != "X" or not isinstance(recent, list) or not recent:
        return False
    return all(
        isinstance(post, dict)
        and post.get("id")
        and post.get("text")
        and str(post.get("handle") or "").lower() == team["x_handle"].lower()
        for post in recent
    )


def build_feed(
    team: dict[str, Any],
    entries: list[dict[str, Any]],
    fallback_path: Path | None = None,
) -> dict[str, Any] | None:
    posts: list[dict[str, Any]] = []
    seen: set[str] = set()
    for entry in entries:
        tweet = (entry.get("content") or {}).get("tweet") or {}
        handle = str((tweet.get("user") or {}).get("screen_name") or "")
        if handle.lower() != team["x_handle"].lower():
            continue
        post = post_from_tweet(tweet)
        if post is None or not post["id"] or post["id"] in seen:
            continue
        seen.add(post["id"])
        posts.append(post)
    if not posts and fallback_path is not None and existing_feed_is_usable(fallback_path, team):
        print(
            f"WARNING: The MLB clubs list has no current @{team['x_handle']} post; "
            f"kept the existing snapshot at {fallback_path}"
        )
        return None
    if not posts:
        posts.append(seed_post(team))

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
    try:
        current = json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        current = {}
    stable_keys = ("source", "source_url", "recent", "popular")
    if all(current.get(key) == feed.get(key) for key in stable_keys):
        print(f"No official-team X post changes; kept {path}")
        return
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
    parser.add_argument("--all", action="store_true", help="Generate every non-Red-Sox snapshot")
    parser.add_argument("--output", type=Path, help="Optional artifact output path")
    parser.add_argument("--install-artifacts", type=Path)
    args = parser.parse_args()
    if args.install_artifacts:
        if args.team or args.output or args.all:
            parser.error("--install-artifacts cannot be combined with fetch options")
        install_artifacts(args.install_artifacts)
        return
    if args.all:
        if args.team or args.output:
            parser.error("--all cannot be combined with --team or --output")
        entries = fetch_entries()
        for team in all_teams():
            if team["api_key"] != "redsox":
                path = output_path(team)
                feed = build_feed(team, entries, fallback_path=path)
                if feed is not None:
                    write_feed(path, feed)
        return
    if not args.team:
        parser.error("--team or --all is required when fetching")
    team = team_by_key(args.team)
    path = args.output or output_path(team)
    feed = build_feed(team, fetch_entries(), fallback_path=path)
    if feed is not None:
        write_feed(path, feed)


if __name__ == "__main__":
    main()
