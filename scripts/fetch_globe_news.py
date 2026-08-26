#!/usr/bin/env python3
"""Fetch Boston Globe Red Sox headline metadata for the news page."""

from __future__ import annotations

import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


SOURCE_URL = "https://www.bostonglobe.com/sports/baseball/redsox/"
OUTPUT_PATH = Path(__file__).resolve().parents[1] / "data" / "globe.json"
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
MAX_ARTICLES = 16


def fetch_page() -> str:
    """Fetch with normal request defaults, then one explicit fallback if needed."""
    last_error: Exception | None = None

    for attempt in range(3):
        try:
            with urlopen(SOURCE_URL, timeout=30) as response:
                page = response.read().decode("utf-8", errors="replace")
            if "Fusion.contentCache=" in page:
                return page
            last_error = RuntimeError("Globe page did not contain its story metadata")
            break
        except (HTTPError, URLError, TimeoutError) as exc:
            last_error = exc
            if attempt < 2:
                time.sleep(2**attempt)

    try:
        request = Request(SOURCE_URL, headers={"User-Agent": FALLBACK_USER_AGENT})
        with urlopen(request, timeout=30) as response:
            page = response.read().decode("utf-8", errors="replace")
        if "Fusion.contentCache=" not in page:
            raise RuntimeError("Globe page did not contain its story metadata")
        return page
    except (HTTPError, URLError, TimeoutError, RuntimeError) as exc:
        raise RuntimeError(f"Could not fetch Globe Red Sox headlines: {exc}") from last_error


def extract_assignment(page: str, name: str) -> Any:
    marker = f"{name}="
    try:
        start = page.index(marker) + len(marker)
    except ValueError as exc:
        raise RuntimeError(f"Missing {name} on Globe page") from exc

    try:
        value, _ = json.JSONDecoder().raw_decode(page[start:])
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Could not read {name} on Globe page") from exc
    return value


def walk(value: Any) -> Iterator[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def clean_text(value: Any) -> str:
    return re.sub(r"\s+", " ", value if isinstance(value, str) else "").strip()


def article_from_story(story: dict[str, Any]) -> dict[str, str] | None:
    if story.get("type") != "story":
        return None

    title = clean_text(story.get("headlines", {}).get("basic"))
    description = clean_text(story.get("description", {}).get("basic"))
    path = clean_text(story.get("website_url") or story.get("canonical_url"))
    published = clean_text(story.get("display_date") or story.get("publish_date"))
    category = clean_text(
        story.get("label", {}).get("overline_basic", {}).get("text")
        or story.get("taxonomy", {}).get("primary_section", {}).get("name")
    )
    primary_section = clean_text(
        story.get("taxonomy", {}).get("primary_section", {}).get("name")
    )

    if not title or not description or not re.match(r"^/\d{4}/\d{2}/\d{2}/", path):
        return None

    text = f"{title} {description}".lower()
    if primary_section.lower() != "red sox" and "red sox" not in text:
        return None

    return {
        "title": title,
        "description": description,
        "url": f"https://www.bostonglobe.com{path}",
        "published": published,
        "category": category or "Red Sox",
    }


def build_feed(page: str) -> dict[str, Any]:
    cache = extract_assignment(page, "Fusion.contentCache")
    articles: list[dict[str, str]] = []
    seen_urls: set[str] = set()

    for story in walk(cache):
        article = article_from_story(story)
        if article is None or article["url"] in seen_urls:
            continue
        seen_urls.add(article["url"])
        articles.append(article)
        if len(articles) == MAX_ARTICLES:
            break

    if not articles:
        raise RuntimeError("No Red Sox article metadata found on Globe page")

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "The Boston Globe",
        "source_url": SOURCE_URL,
        "articles": articles,
    }


def main() -> None:
    feed = build_feed(fetch_page())
    OUTPUT_PATH.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(feed['articles'])} Globe headlines to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
