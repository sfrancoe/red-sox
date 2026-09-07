#!/usr/bin/env python3
"""Validate official-team X snapshot generation without network access."""

from datetime import datetime, timezone

from fetch_team_x_posts import build_feed, output_path, source_url
from team_registry import team_by_key


orioles = team_by_key("orioles")
entry = {
    "content": {
        "tweet": {
            "id_str": "123",
            "full_text": "A team-specific update from Baltimore.",
            "created_at": datetime.now(timezone.utc).strftime("%a %b %d %H:%M:%S %z %Y"),
            "favorite_count": 42,
            "permalink": "/Orioles/status/123",
            "user": {"name": "Baltimore Orioles", "screen_name": "Orioles"},
        }
    }
}
off_team = {"content": {"tweet": {**entry["content"]["tweet"], "id_str": "456", "user": {"name": "Boston Red Sox", "screen_name": "RedSox"}}}}
feed = build_feed(orioles, [entry, entry, off_team])
assert source_url(orioles) == "https://x.com/Orioles"
assert output_path(orioles).as_posix().endswith("/data/orioles/x-posts.json")
assert feed["source"] == "X"
assert [post["id"] for post in feed["recent"]] == ["123"]
assert [post["id"] for post in feed["popular"]] == ["123"]
assert output_path(team_by_key("redsox")).as_posix().endswith("/data/x-posts.json")
print("Official-team X snapshot generation: OK")
