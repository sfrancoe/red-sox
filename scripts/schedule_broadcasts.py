"""Small, stable broadcast projection for native schedule consumers."""

from __future__ import annotations

from typing import Any


def television_broadcasts(game: dict[str, Any]) -> list[dict[str, Any]]:
    """Keep English-language TV/streaming metadata from an MLB schedule game."""
    broadcasts = []
    for entry in game.get("broadcasts") or []:
        if entry.get("type") != "TV" or entry.get("language") not in (None, "", "en"):
            continue
        name = str(entry.get("name") or "").strip()
        if not name:
            continue
        availability = entry.get("availability") or {}
        broadcasts.append({
            "name": name,
            "is_national": bool(entry.get("isNational")),
            "home_away": str(entry.get("homeAway") or ""),
            "availability": str(availability.get("availabilityCode") or ""),
            "available_for_streaming": bool(entry.get("availableForStreaming")),
        })
    return broadcasts
