"""Direct-source newspaper parsers for the shared news fetcher.

A registry news source with an `adapter` is fetched from the publisher directly
instead of through Bing News search:

    {"key": "nypost", "name": "NY Post", "url": "<public section page>",
     "adapter": {"kind": "nypost", "url": "<page or feed to fetch>",
                 "match": "yankee", "exclude_phrases": [...], "path_prefix": "..."}}

`kind` picks the parser below. `match` (optional) keeps only articles whose
title, description or URL contains that lowercase term. `exclude_phrases`
(optional) drops titles containing any phrase. `path_prefix` scopes Fusion
pages to one section. Parsers return at most 20 articles in the shared shape.
"""

from __future__ import annotations

import html
import json
import re
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any, Callable, Iterator


MAX_ARTICLES = 20


class AdapterError(RuntimeError):
    """The page or feed no longer has the markup this parser expects."""


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


def matches(adapter: dict[str, Any], *fields: str) -> bool:
    term = str(adapter.get("match") or "").lower()
    return not term or term in " ".join(fields).lower()


def excluded(adapter: dict[str, Any], title: str) -> bool:
    return any(phrase in title.lower() for phrase in adapter.get("exclude_phrases") or ())


def rss(payload: bytes, adapter: dict[str, Any], team: dict[str, Any]) -> list[dict[str, str]]:
    try:
        root = ET.fromstring(payload)
    except ET.ParseError as exc:
        raise AdapterError(f"Feed is not valid XML: {exc}") from exc
    articles: list[dict[str, str]] = []
    seen: set[str] = set()
    for item in root.findall(".//item"):
        title, url = clean(item.findtext("title")), clean(item.findtext("link"))
        description = clean(item.findtext("description"))
        if (
            not title or not url or url in seen
            or not matches(adapter, title, description, url) or excluded(adapter, title)
        ):
            continue
        seen.add(url)
        articles.append({
            "title": title, "description": description, "url": url,
            "published": iso_date(item.findtext("pubDate") or item.findtext("date")),
            "category": clean(item.findtext("category")) or team["short_name"],
        })
    return articles[:MAX_ARTICLES]


def dailynews(payload: bytes, adapter: dict[str, Any], team: dict[str, Any]) -> list[dict[str, str]]:
    page = payload.decode("utf-8", errors="replace")
    anchor = re.compile(r'<a\s+class="article-title"\s+href="([^"]+)"\s+title="([^"]+)"',
                        re.IGNORECASE)
    articles: list[dict[str, str]] = []
    seen: set[str] = set()
    for match in anchor.finditer(page):
        url, title = clean(match.group(1)), clean(match.group(2))
        if not title or not url or url in seen or not matches(adapter, url, title):
            continue
        seen.add(url)
        nearby = page[match.end():match.end() + 5000]
        excerpt = re.search(r'<div\s+class="excerpt"[^>]*>(.*?)</div>', nearby,
                            re.IGNORECASE | re.DOTALL)
        stamp = re.search(r'<time[^>]+datetime="([^"]+)"', nearby, re.IGNORECASE)
        articles.append({
            "title": title, "description": clean(excerpt.group(1) if excerpt else ""),
            "url": url, "published": iso_date(stamp.group(1) if stamp else ""),
            "category": team["short_name"],
        })
    return articles[:MAX_ARTICLES]


def nypost(payload: bytes, adapter: dict[str, Any], team: dict[str, Any]) -> list[dict[str, str]]:
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
        if not matches(adapter, url, title) or url in seen:
            continue
        seen.add(url)
        day = re.search(r"/(20\d\d)/(\d\d)/(\d\d)/", url)
        published = (
            datetime(*(int(part) for part in day.groups()), tzinfo=timezone.utc)
            .isoformat(timespec="seconds") if day else ""
        )
        articles.append({
            "title": title, "description": "", "url": url, "published": published,
            "category": team["short_name"],
        })
    return articles[:MAX_ARTICLES]


def walk(value: Any) -> Iterator[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def fusion(payload: bytes, adapter: dict[str, Any], team: dict[str, Any]) -> list[dict[str, str]]:
    """Arc XP / Fusion pages embed their stories as `Fusion.contentCache=` JSON."""
    page = payload.decode("utf-8", errors="replace")
    marker = "Fusion.contentCache="
    start = page.find(marker)
    if start < 0:
        raise AdapterError("Page did not include Fusion content")
    cache, _ = json.JSONDecoder().raw_decode(page, start + len(marker))
    origin = re.match(r"https://[^/]+", adapter["url"]).group(0)
    prefix = adapter.get("path_prefix") or "/"
    articles: list[dict[str, str]] = []
    seen: set[str] = set()
    for item in walk(cache):
        path = str(item.get("website_url") or "")
        title = clean((item.get("headlines") or {}).get("basic"))
        if not path.startswith(prefix) or not title:
            continue
        url = origin + path
        if url in seen:
            continue
        seen.add(url)
        description = clean((item.get("subheadlines") or {}).get("basic"))
        if not matches(adapter, title, description, url) or excluded(adapter, title):
            continue
        articles.append({
            "title": title, "description": description, "url": url,
            "published": iso_date(str(item.get("display_date") or item.get("publish_date") or "")),
            "category": team["short_name"],
        })
    articles.sort(key=lambda article: article["published"], reverse=True)
    return articles[:MAX_ARTICLES]


PARSERS: dict[str, Callable[[bytes, dict[str, Any], dict[str, Any]], list[dict[str, str]]]] = {
    "rss": rss, "dailynews": dailynews, "nypost": nypost, "fusion": fusion,
}
