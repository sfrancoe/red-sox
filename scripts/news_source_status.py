"""Versioned, strict source streak state published together with expansion news."""

from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile
from typing import Any

STATE_PATH = Path(__file__).resolve().parents[1] / ".github" / "news-status" / "expansion.json"


def atomic_json(path: Path, value: Any) -> None:
    """A failed write cannot truncate an existing last-good snapshot."""
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def load_state(path: Path) -> dict[str, Any]:
    # The empty versioned seed ships with the code. Missing/corrupt state is an
    # integrity failure, never an excuse to silently forgive a previous failure.
    state = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(state, dict) or set(state) != {"version", "sources"} or type(state["version"]) is not int or state["version"] != 1 or not isinstance(state["sources"], dict):
        raise ValueError("Invalid expansion news status schema")
    for key, entry in state["sources"].items():
        if not isinstance(key, str) or not isinstance(entry, dict) or set(entry) != {"url", "streak", "last_error"}:
            raise ValueError("Invalid source status entry")
        if not isinstance(entry["url"], str) or not entry["url"].startswith("https://") or type(entry["streak"]) is not int or entry["streak"] < 0 or not isinstance(entry["last_error"], str):
            raise ValueError("Invalid source status values")
        if bool(entry["streak"]) != bool(entry["last_error"]):
            raise ValueError("Inconsistent source streak/error")
    return state


def observe(state: dict[str, Any], team: dict[str, Any], source: dict[str, str], error: str = "") -> int:
    key = f"{team['api_key']}/{source['key']}"
    previous = state["sources"].get(key)
    if previous and previous["url"] != source["url"]:
        raise ValueError(f"Source URL changed for {key}; explicitly migrate its status")
    streak = (previous["streak"] if previous else 0) + 1 if error else 0
    state["sources"][key] = {"url": source["url"], "streak": streak, "last_error": error}
    return streak
