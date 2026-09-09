#!/usr/bin/env python3
"""Validate Yankees team feeds consumed by the multi-team Hub Ball app."""

from __future__ import annotations

import json
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "yankees"


def load(name: str):
    return json.loads((DATA / f"{name}.json").read_text())


def main() -> None:
    schedule = load("schedule")
    assert schedule["team"] == "Yankees"
    assert schedule["games"]
    assert all(game["game_pk"] for game in schedule["games"])

    recent = load("recent-game")
    assert 147 in {recent["away"]["id"], recent["home"]["id"]}
    assert "Yankees" in recent["summary"]
    assert recent["innings"] and recent["away"]["batting"] and recent["home"]["batting"]

    standings = load("standings")
    teams = [team for division in standings["divisions"] for team in division["teams"]]
    favorites = [team for team in teams if team["is_favorite"]]
    assert len(favorites) == 1 and favorites[0]["id"] == 147

    pitching = load("pitching")
    assert pitching["team"] == "New York Yankees"
    assert pitching["pitchers"] and pitching["games_played"] > 0
    assert all(pitcher["id"] and pitcher["name"] for pitcher in pitching["pitchers"])

    seasons = load("seasons")
    current = seasons[max(seasons)]
    assert current["war_leaders"] and current["batting_leaders"] and current["pitching_leaders"]
    assert len(current["diff"]) == len(current["seq"]) == current["end_game"]

    domains = {
        "nytimes": "nytimes.com",
        "nypost": "nypost.com",
        "dailynews": "nydailynews.com",
        "athletic": "nytimes.com",
    }
    for source, expected_domain in domains.items():
        feed = load(source)
        assert feed["articles"], source
        urls = [article["url"] for article in feed["articles"]]
        assert len(urls) == len(set(urls)), f"duplicate {source} article"
        assert all(expected_domain in urlparse(url).netloc for url in urls), source
        assert all(article["title"] for article in feed["articles"]), source
        if source in {"nypost", "dailynews", "athletic"}:
            assert all("yankee" in f"{article['title']} {article['url']}".lower()
                       for article in feed["articles"])
        if source == "athletic":
            assert all("red sox folk hero" not in article["title"].lower()
                       for article in feed["articles"])

    print("Hub Ball Yankees feeds and team identity: OK")


if __name__ == "__main__":
    main()
