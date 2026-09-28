"""Offline regression tests for the generated postseason news feed."""

import json
from datetime import datetime, timezone
from pathlib import Path
import tempfile
import unittest

import fetch_postseason_news as news


NOW = datetime(2026, 9, 28, 16, 0, tzinfo=timezone.utc)


class PostseasonNewsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data_root = Path(self.temp.name)
        self.history = {
            "schemaVersion": 1,
            "season": 2026,
            "teams": [
                {"teamId": 111, "name": "Boston Red Sox"},
                {"teamId": 117, "name": "Houston Astros"},
            ],
        }
        self.registry = [
            {
                "mlb_id": 111, "full_name": "Boston Red Sox", "short_name": "Red Sox",
                "abbreviation": "BOS", "league": "AL", "data_directory": "redsox",
                "legacy_root_data": True,
                "news_sources": [{"key": "globe", "name": "Globe"}],
            },
            {
                "mlb_id": 117, "full_name": "Houston Astros", "short_name": "Astros",
                "abbreviation": "HOU", "league": "AL", "data_directory": "astros",
                "legacy_root_data": False,
                "news_sources": [{"key": "chronicle", "name": "Chronicle"}],
            },
        ]

    def write_feed(self, path: Path, articles: list[dict], source: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"source": source, "articles": articles}))

    def test_filters_window_noise_and_duplicates(self):
        shared = {
            "title": "Astros set their Wild Card rotation",
            "description": "Houston prepares for October.",
            "published": "2026-09-28T15:00:00+00:00",
            "url": "https://example.com/astros?utm_source=feed",
        }
        self.write_feed(self.data_root / "globe.json", [
            {
                "title": "Red Sox announce Game 1 starter",
                "description": "Boston opens the Wild Card Series.",
                "published": "2026-09-28T14:00:00Z",
                "url": "https://example.com/red-sox",
            },
            {
                "title": "Where to buy Red Sox playoff tickets",
                "description": "Shopping guide",
                "published": "2026-09-28T15:30:00Z",
                "url": "https://example.com/tickets",
            },
            {
                "title": "Yesterday's recap",
                "description": "Old",
                "published": "2026-09-27T03:00:00Z",
                "url": "https://example.com/old",
            },
        ], "Globe")
        self.write_feed(self.data_root / "astros" / "chronicle.json", [
            shared,
            {**shared, "url": "https://example.com/astros#comments"},
        ], "Chronicle")

        feed, warnings = news.build_feed(
            2026, self.history, self.registry, self.data_root, NOW
        )

        self.assertEqual(warnings, [])
        self.assertEqual([article["title"] for article in feed["articles"]], [
            "Astros set their Wild Card rotation",
            "Red Sox announce Game 1 starter",
        ])
        self.assertEqual(feed["teamCount"], 2)
        self.assertEqual(feed["coveredTeamCount"], 2)
        self.assertIn("?utm_source=feed", feed["articles"][0]["url"])

    def test_missing_source_warns_without_losing_healthy_articles(self):
        self.write_feed(self.data_root / "globe.json", [{
            "title": "Red Sox roster set",
            "description": "The club announced its roster.",
            "published": "2026-09-28T15:00:00Z",
            "url": "https://example.com/roster",
        }], "Globe")

        feed, warnings = news.build_feed(
            2026, self.history, self.registry, self.data_root, NOW
        )

        self.assertEqual(len(feed["articles"]), 1)
        self.assertEqual(len(warnings), 1)
        self.assertIn("Houston Astros / Chronicle", warnings[0])

    def test_unchanged_articles_preserve_existing_generation_time(self):
        path = self.data_root / "postseason-news.json"
        current = {"generatedAt": "old", "articles": [{"url": "https://example.com"}]}
        path.write_text(json.dumps(current))
        changed = news.write_if_changed(path, {
            "generatedAt": "new", "articles": current["articles"],
        })
        self.assertFalse(changed)
        self.assertEqual(json.loads(path.read_text())["generatedAt"], "old")


if __name__ == "__main__":
    unittest.main()
