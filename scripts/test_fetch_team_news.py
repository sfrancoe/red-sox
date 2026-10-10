"""Offline regression tests; never modify the repository's generated data."""

import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch

import fetch_team_news as news


class NewsRefreshTests(unittest.TestCase):
    def test_article_urls_require_absolute_web_addresses(self):
        for value in ("/sports/x.html", "mailto:a@b.c", "", "http-not-a-url", "https://[broken"):
            self.assertEqual(news.direct_url(value), "")
        self.assertEqual(news.direct_url(" https://example.com/story "), "https://example.com/story")
        self.assertEqual(news.direct_url("https://bing.com/news?url=mailto%3Aa%40b.c"), "")
        self.assertEqual(news.direct_url("https://bing.com/news?url=https%3A%2F%2Fexample.com%2Fa"), "https://example.com/a")

    def test_source_host_must_match_exactly_or_be_a_subdomain(self):
        from xml.etree import ElementTree
        root = ElementTree.fromstring('''<rss><channel>
          <item><title>Red Sox news</title><link>https://example.com.evil.test/a</link></item>
          <item><title>Red Sox news</title><link>javascript://example.com/a</link></item>
          <item><title>Red Sox news</title><link>https://sports.example.com/a</link></item>
        </channel></rss>''')
        team = {"full_name": "Boston Red Sox", "short_name": "Red Sox", "api_key": "redsox"}
        with patch.object(news, "fetch_xml", return_value=root):
            feed = news.source_feed(team, {"name": "Example", "url": "https://example.com"})
        self.assertEqual([article["url"] for article in feed["articles"]], ["https://sports.example.com/a"])

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.teams = [
            {"full_name": name, "api_key": name, "news_sources": [
                {"key": "first", "name": "First", "url": "https://first.example"},
                {"key": "second", "name": "Second", "url": "https://second.example"},
            ]}
            for name in ("Team A", "Team B")
        ]
        self.state_path = self.root / "state.json"
        self.state_path.write_text('{"version": 1, "sources": {}}')
        self.feed = {"generated_at": "new", "articles": [{"title": "New article"}]}

    def run_refresh(self, results):
        summary = self.root / "summary.md"
        with (
            patch.object(news, "STATE_PATH", self.state_path),
            patch.object(news, "all_teams", return_value=self.teams),
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
            news.NewsSourceTransientError("Malformed RSS"), self.feed, self.feed, self.feed,
        ])
        self.assertEqual((status, calls), (0, 4))
        self.assertEqual(previous.read_bytes(), before)
        self.assertEqual(json.loads((self.root / "Team A" / "second.json").read_text()), self.feed)
        self.assertTrue((self.root / "Team B" / "second.json").exists())
        self.assertIn("Team A / First: Malformed RSS", summary)
        self.assertIn("1 source failures", summary)

    def test_total_outage_processes_all_sources_and_returns_failure(self):
        status, calls, summary = self.run_refresh([news.NewsSourceTransientError("Timed out")] * 4)
        self.assertEqual((status, calls), (1, 4))
        self.assertIn("4 source failures", summary)
        self.assertEqual(list(self.root.glob("Team*/*.json")), [])

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

    def test_second_failure_alerts_and_recovery_resets(self):
        error = news.NewsSourceTransientError("Malformed RSS")
        self.assertEqual(self.run_refresh([error, self.feed, self.feed, self.feed])[0], 0)
        status, _, summary = self.run_refresh([error, self.feed, self.feed, self.feed])
        self.assertEqual(status, 1)
        self.assertIn("consecutive eligible failures: 2; ALERT", summary)
        self.assertEqual(self.run_refresh([self.feed] * 4)[0], 0)
        self.assertEqual(self.run_refresh([error, self.feed, self.feed, self.feed])[0], 0)
        self.assertEqual(json.loads(self.state_path.read_text())["sources"]["Team A/first"]["streak"], 1)

    def test_alternating_sources_do_not_share_streak(self):
        error = news.NewsSourceTransientError("Network")
        for results in ([error, self.feed, self.feed, self.feed], [self.feed, error, self.feed, self.feed], [error, self.feed, self.feed, self.feed]):
            self.assertEqual(self.run_refresh(results)[0], 0)

    def test_empty_query_is_ineligible_and_does_not_clear_failure(self):
        error = news.NewsSourceTransientError("Network")
        self.run_refresh([error, self.feed, self.feed, self.feed])
        self.assertEqual(self.run_refresh([news.NoArticlesReturnedError("Empty"), self.feed, self.feed, self.feed])[0], 0)
        self.assertEqual(self.run_refresh([error, self.feed, self.feed, self.feed])[0], 1)

    def test_unexpected_code_error_is_immediate(self):
        status, _, summary = self.run_refresh([KeyError("bad configuration"), self.feed, self.feed, self.feed])
        self.assertEqual(status, 1)
        self.assertIn("1 immediate failures", summary)
        self.assertNotIn("Team A/first", json.loads(self.state_path.read_text())["sources"])

    def test_missing_or_corrupt_state_stops_before_any_fetch(self):
        for raw in (None, "broken", '{"version": 2, "sources": {}}', '{"version": 1, "sources": {"x": {"url": "https://x", "streak": true, "last_error": "x"}}}'):
            if raw is None:
                self.state_path.unlink()
            else:
                self.state_path.write_text(raw)
            with self.assertRaises((FileNotFoundError, ValueError)):
                self.run_refresh([self.feed] * 4)
            self.assertFalse((self.root / "Team A").exists())

    def test_duplicate_source_or_url_change_fails_before_fetch(self):
        self.run_refresh([self.feed] * 4)
        before = self.state_path.read_bytes()
        self.teams[0]["news_sources"][0]["url"] = "https://changed.example"
        with self.assertRaises(ValueError):
            self.run_refresh([self.feed] * 4)
        self.assertEqual(self.state_path.read_bytes(), before)
        self.teams[0]["news_sources"][0]["url"] = "https://first.example"
        self.teams.append(self.teams[0])
        with self.assertRaises(ValueError):
            self.run_refresh([self.feed] * 6)

    def test_write_failure_leaves_old_state_and_no_publication_marker(self):
        output = self.root / "output"
        before = self.state_path.read_bytes()
        with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output)}), patch.object(news, "atomic_json", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                self.run_refresh([self.feed] * 4)
        self.assertEqual(self.state_path.read_bytes(), before)
        self.assertFalse(output.exists())

    def test_complete_partial_batch_is_publication_ready(self):
        output = self.root / "output"
        with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output)}):
            self.run_refresh([news.NewsSourceTransientError("Network"), self.feed, self.feed, self.feed])
        self.assertEqual(output.read_text(), "publish_ready=true\n")

    def test_healthy_status_does_not_churn(self):
        self.run_refresh([self.feed] * 4)
        before = self.state_path.read_bytes()
        with patch.object(news, "atomic_json", wraps=news.atomic_json) as write:
            self.run_refresh([self.feed] * 4)
        write.assert_not_called()
        self.assertEqual(self.state_path.read_bytes(), before)

    def test_wrong_response_shape_is_immediate(self):
        from xml.etree import ElementTree
        team = {"full_name": "Team A", "short_name": "A", "api_key": "a"}
        with patch.object(news, "fetch_xml", return_value=ElementTree.fromstring("<html/>")):
            with self.assertRaisesRegex(ValueError, "not an RSS"):
                news.source_feed(team, {"url": "https://first.example", "name": "First"})

    def test_certificate_configuration_error_is_immediate(self):
        import ssl
        from urllib.error import URLError
        with patch.object(news, "urlopen", side_effect=URLError(ssl.SSLCertVerificationError("bad trust"))) as fetch:
            with self.assertRaises(URLError):
                news.fetch_xml("https://example.com")
            self.assertEqual(fetch.call_count, 1)

    def test_body_disconnect_retries_and_then_recovers(self):
        from http.client import IncompleteRead, RemoteDisconnected
        for error in (ConnectionResetError("reset"), IncompleteRead(b"partial", 100), RemoteDisconnected("closed")):
            with self.subTest(error=type(error).__name__):
                response = MagicMock()
                response.__enter__.return_value = response
                response.read.side_effect = [error, b"<rss><channel/></rss>"]
                with patch.object(news, "urlopen", return_value=response) as fetch, patch.object(news.time, "sleep"):
                    root = news.fetch_xml("https://example.com")
                self.assertEqual(root.tag, "rss")
                self.assertEqual(fetch.call_count, 2)
                self.assertEqual(response.read.call_count, 2)

    def test_exhausted_body_disconnect_uses_source_streak_and_last_good(self):
        from http.client import IncompleteRead, RemoteDisconnected
        previous = self.root / "Team A" / "first.json"
        previous.parent.mkdir()
        previous.write_text('{"articles": [{"title": "Last good"}]}')
        before = previous.read_bytes()
        for error in (ConnectionResetError("reset"), IncompleteRead(b"partial", 100), RemoteDisconnected("closed")):
            with self.subTest(error=type(error).__name__):
                self.state_path.write_text('{"version": 1, "sources": {}}')
                response = MagicMock()
                response.__enter__.return_value = response
                response.read.side_effect = error

                def fetch_source(team, source):
                    if team["full_name"] == "Team A" and source["key"] == "first":
                        return news.fetch_xml("https://example.com")
                    return self.feed

                with patch.object(news, "urlopen", return_value=response) as fetch, patch.object(news.time, "sleep"):
                    status, _, summary = self.run_refresh(fetch_source)
                    self.assertEqual(status, 0)
                    self.assertIn("first failure, alert deferred", summary)
                    status, _, summary = self.run_refresh(fetch_source)
                    self.assertEqual(status, 1)
                    self.assertIn("consecutive eligible failures: 2; ALERT", summary)
                self.assertEqual(fetch.call_count, 12)
                self.assertEqual(response.read.call_count, 12)
                self.assertEqual(previous.read_bytes(), before)
                self.assertTrue((self.root / "Team B" / "second.json").exists())

    def test_body_read_trust_code_and_integrity_errors_do_not_retry(self):
        import ssl
        from http.client import BadStatusLine
        for error in (ssl.SSLCertVerificationError("bad trust"), OSError("disk/config error"), RuntimeError("code error"), BadStatusLine("invalid status")):
            with self.subTest(error=type(error).__name__):
                response = MagicMock()
                response.__enter__.return_value = response
                response.read.side_effect = error
                with patch.object(news, "urlopen", return_value=response) as fetch, patch.object(news.time, "sleep"):
                    with self.assertRaises(type(error)):
                        news.fetch_xml("https://example.com")
                self.assertEqual(fetch.call_count, 1)
                self.assertEqual(response.read.call_count, 1)

    def test_rss_retries_classify_transient_vs_configuration(self):
        from urllib.error import HTTPError
        from xml.etree import ElementTree
        for error in (HTTPError("url", 503, "Unavailable", {}, None), ElementTree.ParseError("bad XML"), TimeoutError("slow")):
            with patch.object(news, "urlopen", side_effect=error) as fetch, patch.object(news.time, "sleep"):
                with self.assertRaises(news.NewsSourceTransientError):
                    news.fetch_xml("https://example.com")
                self.assertEqual(fetch.call_count, 6)
        with patch.object(news, "urlopen", side_effect=HTTPError("url", 403, "Forbidden", {}, None)) as fetch:
            with self.assertRaises(HTTPError):
                news.fetch_xml("https://example.com")
            self.assertEqual(fetch.call_count, 1)


if __name__ == "__main__":
    unittest.main()
