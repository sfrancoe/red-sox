#!/usr/bin/env python3
"""Fetch Boston Herald Red Sox headline metadata for the Herald page."""

from __future__ import annotations

import json
import re
import time
from datetime import datetime, timezone
from html import unescape
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


SOURCE_URL = "https://www.bostonherald.com/sports/mlb/boston-red-sox/"
API_URL = "https://www.bostonherald.com/wp-json/wp/v2/posts"
OUTPUT_PATH = Path(__file__).resolve().parents[1] / "data" / "herald.json"
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
RED_SOX_CATEGORY_ID = 11890
MAX_ARTICLES = 16


def request_url() -> str:
    fields = "link,date_gmt,title,excerpt"
    query = urlencode({
        "categories": RED_SOX_CATEGORY_ID,
        "per_page": MAX_ARTICLES,
        "orderby": "date",
        "order": "desc",
        "_fields": fields,
    })
    return f"{API_URL}?{query}"


def fetch_posts() -> list[dict[str, Any]]:
    """Fetch normally with retries, then use the approved fallback user agent."""
    url = request_url()
    last_error: Exception | None = None

    for attempt in range(3):
        try:
            with urlopen(url, timeout=30) as response:
                payload = json.load(response)
            if isinstance(payload, list) and payload:
                return payload
            last_error = RuntimeError("Herald API returned no posts")
            break
        except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
            last_error = exc
            if attempt < 2:
                time.sleep(2**attempt)

    try:
        request = Request(url, headers={"User-Agent": FALLBACK_USER_AGENT})
        with urlopen(request, timeout=30) as response:
            payload = json.load(response)
        if not isinstance(payload, list) or not payload:
            raise RuntimeError("Herald API returned no posts")
        return payload
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError, RuntimeError) as exc:
        raise RuntimeError(f"Could not fetch Boston Herald headlines: {exc}") from last_error


def clean_html(value: Any) -> str:
    text = value if isinstance(value, str) else ""
    text = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", unescape(text)).strip()


def build_feed(posts: list[dict[str, Any]]) -> dict[str, Any]:
    articles: list[dict[str, str]] = []
    seen_urls: set[str] = set()

    for post in posts:
        title = clean_html(post.get("title", {}).get("rendered"))
        description = clean_html(post.get("excerpt", {}).get("rendered"))
        url = post.get("link") if isinstance(post.get("link"), str) else ""
        published = post.get("date_gmt") if isinstance(post.get("date_gmt"), str) else ""
        if not title or not description or not url.startswith("https://www.bostonherald.com/"):
            continue
        if url in seen_urls:
            continue
        seen_urls.add(url)
        articles.append({
            "title": title,
            "description": description,
            "url": url,
            "published": f"{published}Z" if published else "",
            "category": "Boston Red Sox",
        })

    if not articles:
        raise RuntimeError("No Boston Herald Red Sox article metadata found")

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "The Boston Herald",
        "source_url": SOURCE_URL,
        "articles": articles,
    }


def feed_changed(feed: dict[str, Any]) -> bool:
    """Return whether publishable feed content differs from the saved file."""
    try:
        current = json.loads(OUTPUT_PATH.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return True

    keys = ("source", "source_url", "articles")
    return any(current.get(key) != feed.get(key) for key in keys)


def main() -> None:
    feed = build_feed(fetch_posts())
    if not feed_changed(feed):
        print(f"No Herald headline changes; kept {OUTPUT_PATH}")
        return

    OUTPUT_PATH.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(feed['articles'])} Herald headlines to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
