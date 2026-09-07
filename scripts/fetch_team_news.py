#!/usr/bin/env python3
"""Fetch configured team-news sources through Bing News RSS."""

from __future__ import annotations

import argparse
import html
import json
import re
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen
from xml.etree import ElementTree

from team_registry import data_directory, expansion_teams, team_by_key


FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
BING_NEWS = "https://www.bing.com/news/search"


def fetch_xml(url: str) -> ElementTree.Element:
    last_error: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        for attempt in range(3):
            try:
                with urlopen(Request(url, headers=headers), timeout=30) as response:
                    return ElementTree.fromstring(response.read())
            except (HTTPError, URLError, TimeoutError, ElementTree.ParseError) as exc:
                last_error = exc
                if attempt < 2:
                    time.sleep(2**attempt)
    raise RuntimeError(f"Could not fetch news RSS: {last_error}")


def clean_text(value: str | None) -> str:
    without_tags = re.sub(r"<[^>]+>", " ", value or "")
    return re.sub(r"\s+", " ", html.unescape(without_tags)).strip()


def direct_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.netloc.endswith("bing.com"):
        candidate = parse_qs(parsed.query).get("url", [""])[0]
        if candidate.startswith("http"):
            return candidate
    return value


def published(value: str | None) -> str:
    try:
        return parsedate_to_datetime(value or "").astimezone(timezone.utc).isoformat()
    except (TypeError, ValueError):
        return ""


def source_feed(team: dict[str, Any], source: dict[str, str]) -> dict[str, Any]:
    source_host = urlparse(source["url"]).netloc.removeprefix("www.")
    query = f"site:{source_host} {team['full_name']}"
    url = BING_NEWS + "?" + urlencode({"q": query, "format": "rss"})
    root = fetch_xml(url)
    articles, seen = [], set()
    for item in root.findall("./channel/item"):
        article_url = direct_url(item.findtext("link") or "")
        article_host = urlparse(article_url).netloc.removeprefix("www.")
        title = clean_text(item.findtext("title"))
        if not title or source_host not in article_host or article_url in seen:
            continue
        seen.add(article_url)
        articles.append({
            "title": title,
            "description": clean_text(item.findtext("description")),
            "url": article_url,
            "published": published(item.findtext("pubDate")),
            "category": team["short_name"],
        })
    if not articles:
        raise RuntimeError(f"No {source['name']} articles returned for {team['full_name']}")
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": source["name"], "source_url": source["url"], "articles": articles[:20],
    }


def fetch_team(team: dict[str, Any]) -> None:
    output = data_directory(team)
    output.mkdir(parents=True, exist_ok=True)
    print(f"{team['full_name']} news:")
    for source in team["news_sources"]:
        feed = source_feed(team, source)
        path = output / f"{source['key']}.json"
        try:
            current = json.loads(path.read_text())
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            current = None
        if current and current.get("articles") == feed["articles"]:
            print(f"  unchanged {path}")
            continue
        path.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + "\n")
        print(f"  wrote {path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team", action="append", default=[])
    args = parser.parse_args()
    teams = [team_by_key(key) for key in args.team] if args.team else expansion_teams()
    for team in teams:
        fetch_team(team)


if __name__ == "__main__":
    main()
