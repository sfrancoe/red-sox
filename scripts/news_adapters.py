"""Direct-source newspaper parsers for the shared news fetcher.

A registry news source with an `adapter` is fetched from the publisher directly
instead of through Bing News search:

    {"key": "nypost", "name": "NY Post", "url": "<public section page>",
     "adapter": {"kind": "nypost", "url": "<page, feed or API to fetch>", ...}}

`kind` picks the parser below. Optional settings:
  source_name      masthead label shown in the app (defaults to the source name)
  match            keep articles whose title/description/URL contain this term
  exclude_phrases  drop titles containing any of these phrases
  url_prefix       keep only article links starting with this prefix
  require_description  drop articles without a description
  category         label every article with this category
  strip_title_prefix   regex removed from the start of titles
  max              article cap (default 20)
  path_prefix      (fusion) section path to keep
  section          (arc_stories) primary section name that qualifies a story
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


def cap(adapter: dict[str, Any]) -> int:
    return int(adapter.get("max") or MAX_ARTICLES)


class AdapterError(RuntimeError):
    """The page or feed no longer has the markup this parser expects."""


def clean(value: str | None) -> str:
    text = re.sub(r"<[^>]+>", " ", value or "")
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def plain(value: Any) -> str:
    """Collapse whitespace only, for JSON fields that already hold plain text."""
    return re.sub(r"\s+", " ", value if isinstance(value, str) else "").strip()


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
    strip = adapter.get("strip_title_prefix")
    prefix = adapter.get("url_prefix") or ""
    articles: list[dict[str, str]] = []
    seen: set[str] = set()
    for item in root.findall(".//item"):
        title, url = clean(item.findtext("title")), clean(item.findtext("link"))
        if strip:
            title = re.sub(strip, "", title)
        description = clean(item.findtext("description"))
        if (
            not title or not url or url in seen or not url.startswith(prefix)
            or (adapter.get("require_description") and not description)
            or not matches(adapter, title, description, url) or excluded(adapter, title)
        ):
            continue
        seen.add(url)
        articles.append({
            "title": title, "description": description, "url": url,
            "published": iso_date(item.findtext("pubDate") or item.findtext("date")),
            "category": adapter.get("category") or clean(item.findtext("category"))
            or team["short_name"],
        })
        if len(articles) == cap(adapter):
            break
    return articles


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
    return articles[:cap(adapter)]


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
    return articles[:cap(adapter)]


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
    return articles[:cap(adapter)]


def arc_stories(payload: bytes, adapter: dict[str, Any], team: dict[str, Any]) -> list[dict[str, str]]:
    """Arc XP story pages (Boston Globe): dated story URLs in the section or naming the team."""
    page = payload.decode("utf-8", errors="replace")
    marker = "Fusion.contentCache="
    start = page.find(marker)
    if start < 0:
        raise AdapterError("Page did not include Fusion content")
    cache, _ = json.JSONDecoder().raw_decode(page, start + len(marker))
    origin = re.match(r"https://[^/]+", adapter["url"]).group(0)
    section = str(adapter.get("section") or team["short_name"]).lower()
    articles: list[dict[str, str]] = []
    seen: set[str] = set()
    for story in walk(cache):
        if story.get("type") != "story":
            continue
        taxonomy = story.get("taxonomy") or {}
        primary = plain((taxonomy.get("primary_section") or {}).get("name"))
        title = plain((story.get("headlines") or {}).get("basic"))
        description = plain((story.get("description") or {}).get("basic"))
        path = plain(story.get("website_url") or story.get("canonical_url"))
        if not title or not description or not re.match(r"^/\d{4}/\d{2}/\d{2}/", path):
            continue
        if primary.lower() != section and section not in f"{title} {description}".lower():
            continue
        url = origin + path
        if url in seen:
            continue
        seen.add(url)
        overline = plain(((story.get("label") or {}).get("overline_basic") or {}).get("text"))
        articles.append({
            "title": title, "description": description, "url": url,
            "published": plain(story.get("display_date") or story.get("publish_date")),
            "category": overline or primary or team["short_name"],
        })
        if len(articles) == cap(adapter):
            break
    return articles


def wordpress(payload: bytes, adapter: dict[str, Any], team: dict[str, Any]) -> list[dict[str, str]]:
    """WordPress REST posts (`/wp-json/wp/v2/posts?...&_fields=link,date_gmt,title,excerpt`)."""
    try:
        posts = json.loads(payload)
    except json.JSONDecodeError as exc:
        raise AdapterError(f"Posts API did not return JSON: {exc}") from exc
    if not isinstance(posts, list):
        raise AdapterError("Posts API did not return a list")
    prefix = adapter.get("url_prefix") or ""
    articles: list[dict[str, str]] = []
    seen: set[str] = set()
    for post in posts:
        if not isinstance(post, dict):
            continue
        title = clean((post.get("title") or {}).get("rendered"))
        description = clean((post.get("excerpt") or {}).get("rendered"))
        url = post.get("link") if isinstance(post.get("link"), str) else ""
        published = post.get("date_gmt") if isinstance(post.get("date_gmt"), str) else ""
        if not title or not description or not url.startswith(prefix) or url in seen:
            continue
        seen.add(url)
        articles.append({
            "title": title, "description": description, "url": url,
            "published": f"{published}Z" if published else "",
            "category": adapter.get("category") or team["full_name"],
        })
        if len(articles) == cap(adapter):
            break
    return articles


PARSERS: dict[str, Callable[[bytes, dict[str, Any], dict[str, Any]], list[dict[str, str]]]] = {
    "rss": rss, "dailynews": dailynews, "nypost": nypost, "fusion": fusion,
    "arc_stories": arc_stories, "wordpress": wordpress,
}
