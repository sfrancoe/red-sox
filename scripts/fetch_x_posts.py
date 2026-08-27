#!/usr/bin/env python3
"""Fetch and filter the public Red Sox X list for team-relevant posts."""

from __future__ import annotations

import json
import re
import time
from datetime import datetime, timedelta, timezone
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


LIST_ID = "1431748439818346496"
SOURCE_URL = (
    "https://syndication.twitter.com/srv/timeline-list/"
    f"list-id/{LIST_ID}?lang=en&theme=light&showHeader=false&hideBorder=true"
)
ROSTER_URL = (
    "https://statsapi.mlb.com/api/v1/teams/111/roster"
    "?rosterType=fullSeason&season={year}&hydrate=person"
)
OUTPUT_PATH = Path(__file__).resolve().parents[1] / "data" / "x-posts.json"
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
MAX_RECENT_POSTS = 24
MAX_POPULAR_POSTS = 12

TEAM_TERMS = (
    "red sox", "redsox", "#redsox", "@redsox", "bosox", "fenway",
    "woo sox", "woosox", "worcester red sox", "portland sea dogs",
    "portland seadogs", "red stockings", "sox prospects", "soxprospects",
)
RED_SOX_LINK_TERMS = (
    "redsox.com", "mlb.com/redsox", "bostonglobe.com/sports/baseball/redsox",
    "bostonherald.com/sports/mlb/boston-red-sox", "masslive.com/redsox",
    "beyondthemonster", "overthemonster", "bosoxinjection", "soxprospects",
    "thepeskyreport", "sawxstack",
)
NON_REDSOX_TERMS = (
    "white sox", "chicago sox", "patriots", "#patriots", "#nfl", "football",
    "celtics", "#nba", "basketball", "bruins", "#nhl", "hockey",
)
COMMON_SURNAMES = {
    "anderson", "anthony", "campbell", "gray", "harris", "hill", "miller",
    "scott", "short", "story", "walker", "west", "white", "young",
}


class NextDataParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.reading = False
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "script" and dict(attrs).get("id") == "__NEXT_DATA__":
            self.reading = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "script" and self.reading:
            self.reading = False

    def handle_data(self, data: str) -> None:
        if self.reading:
            self.parts.append(data)


def fetch_bytes(url: str, expect: str) -> bytes:
    """Use normal request defaults first, then the approved fallback UA."""
    last_error: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        for attempt in range(3):
            try:
                request = Request(url, headers=headers)
                with urlopen(request, timeout=30) as response:
                    body = response.read()
                if expect.encode() not in body:
                    raise RuntimeError(f"response did not contain {expect}")
                return body
            except (HTTPError, URLError, TimeoutError, RuntimeError) as exc:
                last_error = exc
                if attempt < 2:
                    time.sleep(2**attempt)
        if headers:
            break
    raise RuntimeError(f"Could not fetch {url}: {last_error}")


def fetch_list_entries() -> list[dict[str, Any]]:
    parser = NextDataParser()
    parser.feed(fetch_bytes(SOURCE_URL, "__NEXT_DATA__").decode("utf-8", errors="replace"))
    if not parser.parts:
        raise RuntimeError("X list response did not contain timeline data")
    payload = json.loads("".join(parser.parts))
    return payload["props"]["pageProps"]["timeline"]["entries"]


def fetch_roster_terms() -> set[str]:
    year = datetime.now(timezone.utc).year
    payload = json.loads(fetch_bytes(ROSTER_URL.format(year=year), '"roster"').decode())
    terms: set[str] = set()
    for row in payload.get("roster", []):
        name = str(row.get("person", {}).get("fullName") or "").strip().lower()
        if not name:
            continue
        terms.add(name)
        surname = re.split(r"[\s-]+", name)[-1]
        if len(surname) >= 5 and surname not in COMMON_SURNAMES:
            terms.add(surname)
    return terms


def clean_text(value: Any) -> str:
    text = value if isinstance(value, str) else ""
    return re.sub(r"\s+", " ", unescape(text)).strip()


def published_iso(value: Any) -> str:
    raw = clean_text(value)
    try:
        return datetime.strptime(raw, "%a %b %d %H:%M:%S %z %Y").isoformat()
    except ValueError:
        return raw


def tweet_context(tweet: dict[str, Any]) -> str:
    parts = [tweet.get("full_text"), tweet.get("text")]
    for key in ("quoted_status", "retweeted_status"):
        nested = tweet.get(key) or {}
        parts.extend((nested.get("full_text"), nested.get("text")))
    for item in (tweet, tweet.get("quoted_status") or {}, tweet.get("retweeted_status") or {}):
        entities = item.get("entities") or {}
        for url in entities.get("urls", []):
            parts.extend((url.get("expanded_url"), url.get("display_url")))
        for media in (item.get("extended_entities") or {}).get("media", []):
            parts.append(media.get("ext_alt_text"))
    return clean_text(" ".join(part for part in parts if isinstance(part, str))).lower()


def relevant(tweet: dict[str, Any], roster_terms: set[str]) -> bool:
    context = tweet_context(tweet)
    if any(term in context for term in TEAM_TERMS + RED_SOX_LINK_TERMS):
        return True
    if any(term in context for term in NON_REDSOX_TERMS):
        return False
    return any(re.search(rf"(?<!\w){re.escape(term)}(?!\w)", context) for term in roster_terms)


def media_url(tweet: dict[str, Any]) -> str:
    media = (tweet.get("extended_entities") or {}).get("media", [])
    if not media:
        return ""
    return clean_text(media[0].get("media_url_https"))


def post_from_tweet(tweet: dict[str, Any]) -> dict[str, Any] | None:
    text = clean_text(tweet.get("full_text") or tweet.get("text"))
    user = tweet.get("user") or {}
    handle = clean_text(user.get("screen_name"))
    permalink = clean_text(tweet.get("permalink"))
    if not text or not handle or not permalink:
        return None

    quoted = tweet.get("quoted_status") or {}
    quoted_user = quoted.get("user") or {}
    return {
        "id": clean_text(tweet.get("id_str")),
        "text": text,
        "url": f"https://x.com{permalink}",
        "published": published_iso(tweet.get("created_at")),
        "likes": int(tweet.get("favorite_count") or 0),
        "author": clean_text(user.get("name")) or handle,
        "handle": handle,
        "avatar": clean_text(user.get("profile_image_url_https")),
        "media": media_url(tweet),
        "quoted_text": clean_text(quoted.get("full_text") or quoted.get("text")),
        "quoted_author": clean_text(quoted_user.get("name")),
        "quoted_handle": clean_text(quoted_user.get("screen_name")),
    }


def build_feed(entries: list[dict[str, Any]], roster_terms: set[str]) -> dict[str, Any]:
    posts: list[dict[str, Any]] = []
    seen: set[str] = set()
    for entry in entries:
        tweet = (entry.get("content") or {}).get("tweet") or {}
        if not tweet or not relevant(tweet, roster_terms):
            continue
        post = post_from_tweet(tweet)
        if post is None or post["id"] in seen:
            continue
        seen.add(post["id"])
        posts.append(post)
    if not posts:
        raise RuntimeError("The Red Sox relevance filter removed every X post")

    posts.sort(key=lambda post: post["published"], reverse=True)
    cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
    popular = []
    for post in posts:
        try:
            published = datetime.fromisoformat(post["published"])
        except (TypeError, ValueError):
            continue
        if published >= cutoff:
            popular.append(post)
    popular.sort(key=lambda post: (post["likes"], post["published"]), reverse=True)

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "X",
        "source_url": f"https://x.com/i/lists/{LIST_ID}",
        "recent": posts[:MAX_RECENT_POSTS],
        "popular": popular[:MAX_POPULAR_POSTS],
    }


def feed_changed(feed: dict[str, Any]) -> bool:
    try:
        current = json.loads(OUTPUT_PATH.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return True
    return any(current.get(key) != feed.get(key) for key in ("recent", "popular"))


def main() -> None:
    entries = fetch_list_entries()
    feed = build_feed(entries, fetch_roster_terms())
    if not feed_changed(feed):
        print(f"No filtered X post changes; kept {OUTPUT_PATH}")
        return
    OUTPUT_PATH.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    print(
        f"Wrote {len(feed['recent'])} recent and {len(feed['popular'])} popular "
        f"Red Sox X posts to {OUTPUT_PATH}"
    )


if __name__ == "__main__":
    main()
