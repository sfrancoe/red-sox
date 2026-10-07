#!/usr/bin/env python3
"""Fetch configured team-news sources through Bing News RSS."""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sys
import ssl
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from http.client import IncompleteRead, RemoteDisconnected
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen
from xml.etree import ElementTree

from team_registry import data_directory, expansion_teams, team_by_key
from news_source_status import STATE_PATH, atomic_json, load_state, observe


FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
BING_NEWS = "https://www.bing.com/news/search"


class NewsSourceTransientError(RuntimeError):
    """Exhausted retries for a network/service or malformed RSS failure."""


class NoArticlesReturnedError(RuntimeError):
    """A valid source query had no matching articles at this refresh."""


def fetch_xml(url: str) -> ElementTree.Element:
    last_error: Exception | None = None
    for headers in ({}, {"User-Agent": FALLBACK_USER_AGENT}):
        for attempt in range(3):
            try:
                with urlopen(Request(url, headers=headers), timeout=30) as response:
                    return ElementTree.fromstring(response.read())
            # Body reads can disconnect after urlopen has returned successfully.
            # Keep this list narrow: arbitrary OSError/HTTPException/code failures
            # must still escape into immediate failure reporting.
            except (HTTPError, URLError, TimeoutError, ElementTree.ParseError,
                    ConnectionResetError, IncompleteRead, RemoteDisconnected) as exc:
                if isinstance(exc, HTTPError) and exc.code != 429 and not 500 <= exc.code <= 599:
                    raise  # Authentication, missing URL, configuration: immediate.
                if isinstance(exc, URLError) and isinstance(exc.reason, ssl.SSLCertVerificationError):
                    raise  # Broken trust/configuration is not a transient outage.
                last_error = exc
                if attempt < 2:
                    time.sleep(2**attempt)
    raise NewsSourceTransientError(f"Could not fetch news RSS: {last_error}")


def clean_text(value: str | None) -> str:
    without_tags = re.sub(r"<[^>]+>", " ", value or "")
    return re.sub(r"\s+", " ", html.unescape(without_tags)).strip()


def direct_url(value: str) -> str:
    value = safe_web_url(value)
    parsed = urlparse(value)
    host = parsed.hostname or ""
    if host == "bing.com" or host.endswith(".bing.com"):
        candidate = parse_qs(parsed.query).get("url", [""])[0]
        if candidate:
            return safe_web_url(candidate)
    return value


def safe_web_url(value: str) -> str:
    value = value.strip()
    try:
        parsed = urlparse(value)
        if parsed.scheme in {"http", "https"} and parsed.hostname:
            return value
    except ValueError:
        pass
    return ""


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
    if root.tag != "rss" or root.find("channel") is None:
        raise ValueError("News response is not an RSS channel")
    articles, seen = [], set()
    team_terms = {
        team["full_name"].lower(), team["short_name"].lower(),
        team["api_key"].lower(),
    }
    for item in root.findall("./channel/item"):
        article_url = direct_url(item.findtext("link") or "")
        article_host = (urlparse(article_url).hostname or "").removeprefix("www.")
        title = clean_text(item.findtext("title"))
        context = f"{title} {clean_text(item.findtext('description'))} {article_url}".lower()
        if (
            not title or not article_url or article_url in seen
            or not (article_host == source_host or article_host.endswith("." + source_host))
            or not any(term in context for term in team_terms)
        ):
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
        raise NoArticlesReturnedError(
            f"No {source['name']} articles returned for {team['full_name']}"
        )
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": source["name"], "source_url": source["url"], "articles": articles[:20],
    }


def fetch_team(team: dict[str, Any], state: dict[str, Any]) -> tuple[list[str], list[str], int, int]:
    failures, immediate = [], []
    escalated = attempted = 0
    output = data_directory(team)
    output.mkdir(parents=True, exist_ok=True)
    print(f"{team['full_name']} news:")
    for source in team["news_sources"]:
        attempted += 1
        try:
            feed = source_feed(team, source)
        except NoArticlesReturnedError as exc:
            # Search-index coverage can be briefly empty. Keep the prior verified
            # snapshot instead of failing the entire league refresh or overwriting it.
            print(f"  warning: {exc}; keeping the previous snapshot")
            continue
        except NewsSourceTransientError as exc:
            failure = f"{team['full_name']} / {source['name']}: {exc}"
            streak = observe(state, team, source, str(exc) or type(exc).__name__)
            escalated += streak >= 2
            failure += f" (consecutive eligible failures: {streak}; {'ALERT' if streak >= 2 else 'first failure, alert deferred'})"
            failures.append(failure)
            print(f"  {'ERROR' if streak >= 2 else 'WARNING'}: {failure}; keeping the previous snapshot", file=sys.stderr)
            continue
        except Exception as exc:
            # Unexpected code/configuration failures remain immediately actionable.
            failure = f"{team['full_name']} / {source['name']}: {exc}"
            immediate.append(failure)
            print(f"  ERROR: {failure}; keeping the previous snapshot", file=sys.stderr)
            continue
        observe(state, team, source)  # A verified success resets only this source.
        path = output / f"{source['key']}.json"
        try:
            current = json.loads(path.read_text())
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            current = None
        if current and current.get("articles") == feed["articles"]:
            print(f"  unchanged {path}")
            continue
        atomic_json(path, feed)
        print(f"  wrote {path}")
    return failures, immediate, escalated, attempted


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team", action="append", default=[])
    args = parser.parse_args()
    teams = [team_by_key(key) for key in args.team] if args.team else expansion_teams()
    state = load_state(STATE_PATH)
    original_state = json.dumps(state, sort_keys=True)
    # Validate identities before any fetch/write. Repeated identities would count
    # one refresh twice; source URL changes require an explicit state migration.
    identities = set()
    for team in teams:
        for source in team["news_sources"]:
            identity = f"{team['api_key']}/{source['key']}"
            if identity in identities:
                raise ValueError(f"Duplicate source: {identity}")
            identities.add(identity)
            previous = state["sources"].get(identity)
            if not source["url"].startswith("https://") or (previous and previous["url"] != source["url"]):
                raise ValueError(f"Invalid or changed source URL: {identity}")
    failures, immediate = [], []
    escalated = attempted = 0
    for team in teams:
        failed, fatal, alerts, count = fetch_team(team, state)
        failures.extend(failed)
        immediate.extend(fatal)
        escalated += alerts
        attempted += count
    if not attempted:
        raise ValueError("No news sources configured")
    outage = len(failures) == attempted
    if outage:
        immediate.append("Whole-update outage: every configured source failed")
    if json.dumps(state, sort_keys=True) != original_state:
        atomic_json(STATE_PATH, state)
    summary = (
        f"News refresh: {len(teams)} teams processed; {len(failures)} source failures; "
        f"{escalated} persistent source alerts; {len(immediate)} immediate failures.\n"
        "Healthy updates and source status are ready to publish together. "
        "Failed sources retain their previous snapshots.\n"
    )
    if failures or immediate:
        summary += "\n" + "\n".join(f"- {failure}" for failure in failures + immediate) + "\n"
    print(summary)
    if summary_path := os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(summary_path).open("a", encoding="utf-8") as handle:
            handle.write(summary)
    # Set this only after the complete fetch, writes, strict state persistence and
    # summary succeed. Integrity/I/O failures must not publish a partial batch.
    if output_path := os.environ.get("GITHUB_OUTPUT"):
        with Path(output_path).open("a", encoding="utf-8") as handle:
            handle.write("publish_ready=true\n")
    return 1 if escalated or immediate else 0


if __name__ == "__main__":
    sys.exit(main())
