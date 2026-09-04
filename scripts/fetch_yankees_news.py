#!/usr/bin/env python3
"""Fetch the four Yankees newspaper feeds used by the Yankees Hub app."""

from __future__ import annotations

import argparse
import html
import json
import re
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "data" / "yankees"
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
SOURCES = {
    "nytimes": {
        "name": "The New York Times",
        "url": "https://www.nytimes.com/svc/collections/v1/publish/http%3A%2F%2Fwww.nytimes.com%2Ftopic%2Forganization%2Fnew-york-yankees/rss.xml",
        "kind": "rss",
        "category": "Yankees",
    },
    "nypost": {
        "name": "New York Post",
        "url": "https://nypost.com/sports/yankees/",
        "kind": "nypost",
        "category": "Yankees",
    },
    "dailynews": {
        "name": "New York Daily News",
        "url": "https://www.nydailynews.com/sports/mlb/new-york-yankees/",
        "kind": "html",
        "category": "Yankees",
    },
    "athletic": {
        "name": "The Athletic",
        "url": "https://www.nytimes.com/athletic/rss/mlb/yankees/",
        "kind": "rss",
        "category": "Yankees",
        "require_yankees": True,
        "exclude_phrases": ("red sox folk hero",),
    },
}


def fetch(url: str) -> bytes:
    """Use the normal request first, then the repo-approved fallback user agent."""
    last_error: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        for attempt in range(3):
            try:
                with urllib.request.urlopen(
                    urllib.request.Request(url, headers=headers), timeout=30
                ) as response:
                    return response.read()
            except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
                last_error = exc
                if attempt < 2:
                    time.sleep(2**attempt)
    raise RuntimeError(f"Could not fetch {url}: {last_error}")


def clean(value: str | None) -> str:
    text = re.sub(r"<[^>]+>", " ", value or "")
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def iso_date(value: str | None) -> str:
    raw = clean(value)
    if not raw:
        return ""
    try:
        parsed = parsedate_to_datetime(raw)
    except (TypeError, ValueError, OverflowError):
        try:
            parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            return raw
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat(timespec="seconds")


def rss_articles(
    payload: bytes,
    category: str,
    require_yankees: bool = False,
    exclude_phrases: tuple[str, ...] = (),
) -> list[dict[str, str]]:
    root = ET.fromstring(payload)
    articles: list[dict[str, str]] = []
    seen: set[str] = set()
    for item in root.findall(".//item"):
        title = clean(item.findtext("title"))
        url = clean(item.findtext("link"))
        if not title or not url or url in seen:
            continue
        seen.add(url)
        description = clean(item.findtext("description"))
        if require_yankees and "yankee" not in f"{title} {description} {url}".lower():
            continue
        if any(phrase in title.lower() for phrase in exclude_phrases):
            continue
        published = iso_date(item.findtext("pubDate") or item.findtext("date"))
        item_category = clean(item.findtext("category")) or category
        articles.append({
            "title": title,
            "description": description,
            "url": url,
            "published": published,
            "category": item_category,
        })
    return articles[:20]


def daily_news_articles(payload: bytes, category: str) -> list[dict[str, str]]:
    page = payload.decode("utf-8", errors="replace")
    anchor = re.compile(
        r'<a\s+class="article-title"\s+href="([^"]+)"\s+title="([^"]+)"',
        re.IGNORECASE,
    )
    articles: list[dict[str, str]] = []
    seen: set[str] = set()
    for match in anchor.finditer(page):
        url, title = clean(match.group(1)), clean(match.group(2))
        if (
            not title
            or not url
            or url in seen
            or "yankee" not in f"{url} {title}".lower()
        ):
            continue
        seen.add(url)
        nearby = page[match.end():match.end() + 5000]
        excerpt_match = re.search(
            r'<div\s+class="excerpt"[^>]*>(.*?)</div>', nearby,
            re.IGNORECASE | re.DOTALL,
        )
        time_match = re.search(r'<time[^>]+datetime="([^"]+)"', nearby, re.IGNORECASE)
        articles.append({
            "title": title,
            "description": clean(excerpt_match.group(1) if excerpt_match else ""),
            "url": url,
            "published": iso_date(time_match.group(1) if time_match else ""),
            "category": category,
        })
    return articles[:20]


def ny_post_articles(payload: bytes, category: str) -> list[dict[str, str]]:
    page = payload.decode("utf-8", errors="replace")
    headline = re.compile(
        r'<h[23][^>]*class="[^"]*story__headline[^"]*"[^>]*>\s*'
        r'<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>',
        re.IGNORECASE | re.DOTALL,
    )
    articles: list[dict[str, str]] = []
    seen: set[str] = set()
    for match in headline.finditer(page):
        url, title = clean(match.group(1)), clean(match.group(2))
        if "yankee" not in f"{url} {title}".lower() or url in seen:
            continue
        seen.add(url)
        date_match = re.search(r"/(20\d\d)/(\d\d)/(\d\d)/", url)
        published = ""
        if date_match:
            published = datetime(
                *(int(part) for part in date_match.groups()), tzinfo=timezone.utc
            ).isoformat(timespec="seconds")
        articles.append({
            "title": title,
            "description": "",
            "url": url,
            "published": published,
            "category": category,
        })
    return articles[:20]


def write_feed(key: str) -> None:
    source = SOURCES[key]
    payload = fetch(str(source["url"]))
    parsers = {
        "rss": rss_articles,
        "html": daily_news_articles,
        "nypost": ny_post_articles,
    }
    parser = parsers[str(source["kind"])]
    if source["kind"] == "rss":
        articles = parser(
            payload,
            str(source["category"]),
            bool(source.get("require_yankees")),
            tuple(source.get("exclude_phrases", ())),
        )
    else:
        articles = parser(payload, str(source["category"]))
    if not articles:
        raise RuntimeError(f"No {source['name']} Yankees articles were found")

    output = OUTPUT_DIR / f"{key}.json"
    feed = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source": source["name"],
        "source_url": source["url"],
        "articles": articles,
    }
    if output.exists():
        previous = json.loads(output.read_text())
        if previous.get("articles") == articles:
            print(f"No {source['name']} changes; kept {output}")
            return
    output.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(articles)} {source['name']} articles to {output}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("sources", nargs="*")
    args = parser.parse_args()
    unknown = set(args.sources) - set(SOURCES)
    if unknown:
        parser.error(f"unknown source: {', '.join(sorted(unknown))}")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for key in args.sources or list(SOURCES):
        write_feed(key)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
