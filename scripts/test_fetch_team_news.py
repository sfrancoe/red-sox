"""Offline regression tests; never modify the repository's generated data."""

import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import fetch_team_news as news


class NewsRefreshTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.teams = [
            {"full_name": name, "news_sources": [
                {"key": "first", "name": "First"},
                {"key": "second", "name": "Second"},
            ]}
            for name in ("Team A", "Team B")
        ]
        self.feed = {"generated_at": "new", "articles": [{"title": "New article"}]}

    def run_refresh(self, results):
        summary = self.root / "summary.md"
        with (
            patch.object(news, "expansion_teams", return_value=self.teams),
            patch.object(news, "data_directory", side_effect=lambda team: self.root / team["full_name"]),
            patch.object(news, "source_feed", side_effect=results) as fetch,
            patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": str(summary)}),
            patch("sys.argv", ["fetch_team_news.py"]),
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            status = news.main()
        return status, fetch.call_count, summary.read_text()

    def test_broken_source_preserves_snapshot_and_other_teams_publish(self):
        previous = self.root / "Team A" / "first.json"
        previous.parent.mkdir()
        previous.write_text('{"articles": [{"title": "Last good article"}]}\n')
        before = previous.read_bytes()
        status, calls, summary = self.run_refresh([
            RuntimeError("Malformed RSS"), self.feed, self.feed, self.feed,
        ])
        self.assertEqual((status, calls), (1, 4))
        self.assertEqual(previous.read_bytes(), before)
        self.assertEqual(json.loads((self.root / "Team A" / "second.json").read_text()), self.feed)
        self.assertTrue((self.root / "Team B" / "second.json").exists())
        self.assertIn("Team A / First: Malformed RSS", summary)
        self.assertIn("1 source failures", summary)

    def test_total_outage_processes_all_sources_and_returns_failure(self):
        status, calls, summary = self.run_refresh([TimeoutError("Timed out")] * 4)
        self.assertEqual((status, calls), (1, 4))
        self.assertIn("4 source failures", summary)
        self.assertEqual(list(self.root.rglob("*.json")), [])

    def test_empty_search_keeps_existing_feed_without_failing_refresh(self):
        previous = self.root / "Team A" / "first.json"
        previous.parent.mkdir()
        previous.write_text('{"articles": [{"title": "Previous"}]}\n')
        before = previous.read_bytes()
        status, calls, _ = self.run_refresh([
            news.NoArticlesReturnedError("No matches"), self.feed, self.feed, self.feed,
        ])
        self.assertEqual((status, calls), (0, 4))
        self.assertEqual(previous.read_bytes(), before)

    def test_unchanged_articles_do_not_rewrite_timestamp(self):
        previous = self.root / "Team A" / "first.json"
        previous.parent.mkdir()
        previous.write_text(json.dumps({**self.feed, "generated_at": "old"}))
        before = previous.read_bytes()
        status, _, _ = self.run_refresh([self.feed] * 4)
        self.assertEqual(status, 0)
        self.assertEqual(previous.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
