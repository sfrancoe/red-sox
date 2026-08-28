#!/usr/bin/env python3
"""Fetch Red Sox headline metadata from RSS-based news sources."""

from __future__ import annotations

import argparse
import json
import re
import time
from datetime import timezone
from email.utils import parsedate_to_datetime
from html import unescape
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parents[1]
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
MAX_ARTICLES = 16
SOURCES = {
    "athletic": {
        "feed_url": "https://www.nytimes.com/athletic/rss/mlb/redsox/",
        "source": "The Athletic",
        "source_url": "https://www.nytimes.com/athletic/mlb/team/redsox/",
        "output": ROOT / "data" / "athletic.json",
        "category": "Boston Red Sox",
        "url_prefix": "https://www.nytimes.com/athletic/",
    },
    "masslive": {
        "feed_url": "https://www.masslive.com/arc/outboundfeeds/rss/category/redsox/?outputType=xml",
        "source": "MassLive",
        "source_url": "https://www.masslive.com/#section__sports",
        "output": ROOT / "data" / "masslive.json",
        "category": "Red Sox",
        "url_prefix": "https://www.masslive.com/",
    },
}


def fetch_feed(url: str) -> bytes:
    """Fetch normally with retries, then use the approved fallback user agent."""
    last_error: Exception | None = None

    for attempt in range(3):
        try:
            with urlopen(url, timeout=30) as response:
                payload = response.read()
            if payload:
                return payload
            last_error = RuntimeError("RSS feed was empty")
            break
        except (HTTPError, URLError, TimeoutError) as exc:
            last_error = exc
            if attempt < 2:
                time.sleep(2**attempt)

    try:
        request = Request(url, headers={"User-Agent": FALLBACK_USER_AGENT})
        with urlopen(request, timeout=30) as response:
            payload = response.read()
        if not payload:
            raise RuntimeError("RSS feed was empty")
        return payload
    except (HTTPError, URLError, TimeoutError, RuntimeError) as exc:
        raise RuntimeError(f"Could not fetch RSS headlines: {exc}") from last_error


def clean_html(value: Any) -> str:
    text = value if isinstance(value, str) else ""
    text = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", unescape(text)).strip()


def child_text(item: ElementTree.Element, name: str) -> str:
    child = item.find(name)
    return child.text.strip() if child is not None and child.text else ""


def iso_date(value: str) -> str:
    if not value:
        return ""
    try:
        return parsedate_to_datetime(value).astimezone(timezone.utc).isoformat()
    except (TypeError, ValueError):
        return value


def build_feed(payload: bytes, config: dict[str, Any]) -> dict[str, Any]:
    try:
        root = ElementTree.fromstring(payload)
    except ElementTree.ParseError as exc:
        raise RuntimeError("RSS feed was not valid XML") from exc

    articles: list[dict[str, str]] = []
    seen_urls: set[str] = set()
    for item in root.findall("./channel/item"):
        title = clean_html(child_text(item, "title"))
        # MassLive occasionally concatenates its internal `season` label onto
        # a title in the RSS payload (for example, `seasonState of the Sox`).
        title = re.sub(r"^season(?=[A-Z])", "", title)
        description = clean_html(child_text(item, "description"))
        url = child_text(item, "link")
        published = iso_date(child_text(item, "pubDate"))
        if not title or not description or not url.startswith(config["url_prefix"]):
            continue
        if url in seen_urls:
            continue
        seen_urls.add(url)
        articles.append({
            "title": title,
            "description": description,
            "url": url,
            "published": published,
            "category": config["category"],
        })
        if len(articles) == MAX_ARTICLES:
            break

    if not articles:
        raise RuntimeError(f"No article metadata found for {config['source']}")

    latest = max((article["published"] for article in articles), default="")
    return {
        "generated_at": latest,
        "source": config["source"],
        "source_url": config["source_url"],
        "articles": articles,
    }


def feed_changed(feed: dict[str, Any], output_path: Path) -> bool:
    try:
        current = json.loads(output_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return True

    keys = ("source", "source_url", "articles")
    return any(current.get(key) != feed.get(key) for key in keys)


def refresh(source_key: str) -> None:
    config = SOURCES[source_key]
    output_path = config["output"]
    feed = build_feed(fetch_feed(config["feed_url"]), config)
    if not feed_changed(feed, output_path):
        print(f"No {config['source']} headline changes; kept {output_path}")
        return

    output_path.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(feed['articles'])} {config['source']} headlines to {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("sources", nargs="+", choices=SOURCES, help="RSS sources to refresh")
    args = parser.parse_args()
    for source_key in args.sources:
        refresh(source_key)


if __name__ == "__main__":
    main()
