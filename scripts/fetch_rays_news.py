#!/usr/bin/env python3
"""Fetch the Tampa Bay Times and Athletic feeds used by the Rays Hub app."""

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
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "data" / "rays"
FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
SOURCES = {
    "tampabay": {
        "name": "Tampa Bay Times",
        "url": "https://www.tampabay.com/sports/rays/",
        "kind": "fusion",
    },
    "athletic": {
        "name": "The Athletic",
        "url": "https://www.nytimes.com/athletic/rss/mlb/rays/",
        "kind": "rss",
    },
}


def fetch(url: str) -> bytes:
    last_error: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        for attempt in range(3):
            try:
                request = urllib.request.Request(url, headers=headers)
                with urllib.request.urlopen(request, timeout=30) as response:
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


def rss_articles(payload: bytes) -> list[dict[str, str]]:
    root = ET.fromstring(payload)
    articles = []
    seen = set()
    for item in root.findall(".//item"):
        title = clean(item.findtext("title"))
        description = clean(item.findtext("description"))
        url = clean(item.findtext("link"))
        if not title or not url or url in seen:
            continue
        if "rays" not in f"{title} {description} {url}".lower():
            continue
        seen.add(url)
        articles.append({
            "title": title,
            "description": description,
            "url": url,
            "published": iso_date(item.findtext("pubDate")),
            "category": clean(item.findtext("category")) or "Rays",
        })
    return articles[:20]


def walk(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def fusion_articles(payload: bytes) -> list[dict[str, str]]:
    page = payload.decode("utf-8", errors="replace")
    marker = "Fusion.contentCache="
    start = page.find(marker)
    if start < 0:
        raise RuntimeError("Tampa Bay Times page did not include Fusion content")
    cache, _ = json.JSONDecoder().raw_decode(page, start + len(marker))
    articles = []
    seen = set()
    for item in walk(cache):
        path = str(item.get("website_url") or "")
        headline = clean((item.get("headlines") or {}).get("basic"))
        if not path.startswith("/sports/rays/") or not headline:
            continue
        url = f"https://www.tampabay.com{path}"
        if url in seen:
            continue
        seen.add(url)
        articles.append({
            "title": headline,
            "description": clean((item.get("subheadlines") or {}).get("basic")),
            "url": url,
            "published": iso_date(str(item.get("display_date") or item.get("publish_date") or "")),
            "category": "Rays",
        })
    articles.sort(key=lambda article: article["published"], reverse=True)
    return articles[:20]


def write_feed(key: str) -> None:
    source = SOURCES[key]
    payload = fetch(str(source["url"]))
    articles = fusion_articles(payload) if source["kind"] == "fusion" else rss_articles(payload)
    if not articles:
        raise RuntimeError(f"No {source['name']} Rays articles were found")
    output = OUTPUT_DIR / f"{key}.json"
    feed = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source": source["name"],
        "source_url": source["url"],
        "articles": articles,
    }
    if output.exists() and json.loads(output.read_text()).get("articles") == articles:
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
