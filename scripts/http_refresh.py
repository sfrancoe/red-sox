"""Polite, bounded retries for public refresh providers (stdlib only)."""

from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

FALLBACK_USER_AGENT = "OpenAI File Downloader, XaiImageApiFetch/1.0"
_last_fangraphs_request = 0.0


def retry_delay(error: Exception, attempt: int) -> float:
    if not isinstance(error, HTTPError) or error.code != 429:
        return 2**attempt
    value = error.headers.get("Retry-After", "") if error.headers else ""
    try:
        delay = float(value)
    except ValueError:
        try:
            delay = (parsedate_to_datetime(value) - datetime.now(timezone.utc)).total_seconds()
        except (TypeError, ValueError, OverflowError):
            delay = 0
    # Bound each wait so a provider cannot consume the entire workflow timeout.
    return min(180, max(delay, 30 * 2**attempt))


def fetch_json(url: str, timeout: int = 45) -> Any:
    """Retry transient failures; try the approved UA once after normal defaults."""
    global _last_fangraphs_request
    last_error: Exception | None = None
    for attempt, headers in enumerate(({}, {}, {}, {"User-Agent": FALLBACK_USER_AGENT})):
        if urlparse(url).hostname == "www.fangraphs.com":
            wait = 1.0 - (time.monotonic() - _last_fangraphs_request)
            if wait > 0:
                time.sleep(wait)
            _last_fangraphs_request = time.monotonic()
        try:
            with urlopen(Request(url, headers=headers), timeout=timeout) as response:
                return json.load(response)
        except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
            last_error = exc
            if attempt < 3:
                time.sleep(retry_delay(exc, attempt))
    raise RuntimeError(f"Could not fetch {url}: {last_error}") from last_error
