"""Read publication times from public publisher metadata, never search-index dates."""

from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from html.parser import HTMLParser
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
PUBLICATION_FIELDS = ("article:published_time", "parsely-pub-date", "datepublished")


def timestamp(value: str) -> datetime | None:
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
        # A timezone-free date is not enough evidence to assign an exact time.
        return result.astimezone(timezone.utc) if result.tzinfo else None
    except (AttributeError, TypeError, ValueError):
        return None


class PublicationMetadata(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.meta: dict[str, str] = {}
        self.json_ld: list[str] = []
        self.script: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if tag == "meta":
            key = str(attributes.get("property") or attributes.get("name") or attributes.get("itemprop") or "").lower()
            if key in PUBLICATION_FIELDS:
                self.meta.setdefault(key, attributes.get("content") or "")
        if tag == "script" and (attributes.get("type") or "").lower() == "application/ld+json":
            self.script = []

    def handle_data(self, data: str) -> None:
        if self.script is not None:
            self.script.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "script" and self.script is not None:
            self.json_ld.append("".join(self.script))
            self.script = None


def article_nodes(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, list):
        return [node for child in value for node in article_nodes(child)]
    if not isinstance(value, dict):
        return []
    kinds = value.get("@type", [])
    if isinstance(kinds, str):
        kinds = [kinds]
    if not isinstance(kinds, list):
        return []
    if any(isinstance(kind, str) and kind in {"Article", "NewsArticle", "ReportageNewsArticle", "BlogPosting"} for kind in kinds):
        return [value]
    # Do not pick dates out of related-story lists, videos, or breadcrumbs.
    return article_nodes(value.get("@graph", []))


def publication_from_html(html: str, url: str) -> str | None:
    parser = PublicationMetadata()
    parser.feed(html)
    for key in PUBLICATION_FIELDS:
        if date := timestamp(parser.meta.get(key, "")):
            return date.isoformat()
    for raw in parser.json_ld:
        try:
            nodes = article_nodes(json.loads(raw))
        except (TypeError, ValueError):
            continue
        for node in nodes:
            article_url = node.get("url") or node.get("URL")
            if isinstance(article_url, str) and urlsplit(article_url).path.rstrip("/") != urlsplit(url).path.rstrip("/"):
                continue
            if date := timestamp(node.get("datePublished", "")):
                return date.isoformat()
    return None


def fetch_publication(url: str) -> str | None:
    error: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        for attempt in range(2 if not headers else 1):
            try:
                with urlopen(Request(url, headers=headers), timeout=12) as response:
                    html = response.read(4 * 1024 * 1024).decode(response.headers.get_content_charset() or "utf-8", "replace")
                if published := publication_from_html(html, url):
                    return published
                break  # Missing metadata / an overlay: try the retrieval fallback once.
            except HTTPError as exc:
                error = exc
                if exc.code in {401, 402, 404, 410}:
                    raise
                if exc.code not in {429, 500, 502, 503, 504}:
                    break
                if attempt == 0 and not headers:
                    time.sleep(0.5)
            except (URLError, TimeoutError) as exc:
                error = exc
                if attempt == 0 and not headers:
                    time.sleep(0.5)
    if error:
        raise RuntimeError(f"Publisher publication time unavailable: {error}")
    return None
