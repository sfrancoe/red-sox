#!/usr/bin/env python3
"""Offline tests for direct-source newspaper adapters in the shared news fetcher."""

from __future__ import annotations

import io
import json
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

import fetch_team_news as news
import news_adapters
from team_registry import team_by_key


def source(team_key: str, source_key: str) -> tuple[dict, dict]:
    team = team_by_key(team_key)
    return team, next(item for item in team["news_sources"] if item["key"] == source_key)


class AdapterParserTests(unittest.TestCase):
    def test_nypost_keeps_team_filter_and_parses_current_markup(self):
        team, mets_post = source("mets", "nypost")
        payload = b'''<h3 class="story__headline headline headline--archive">
        <a href="https://nypost.com/2026/10/03/sports/mets-roster/" target="_self">Mets &amp; roster</a></h3>
        <h3 class="story__headline"><a href="https://nypost.com/2026/10/03/sports/yankees/">Yankees win</a></h3>'''
        articles = news_adapters.nypost(payload, mets_post["adapter"], team)
        self.assertEqual(len(articles), 1)
        self.assertEqual(articles[0]["title"], "Mets & roster")
        self.assertEqual(articles[0]["published"], "2026-10-03T00:00:00+00:00")
        self.assertEqual(articles[0]["category"], "Mets")

    def test_dailynews_reads_excerpt_and_time_near_each_headline(self):
        team, daily = source("yankees", "dailynews")
        payload = b'''<a class="article-title" href="https://www.nydailynews.com/2026/10/08/yankees-win/"
          title="Yankees even the series">x</a><div class="excerpt">Judge homers twice</div>
          <time class="date" datetime="2026-10-08T23:10:00-04:00">'''
        [article] = news_adapters.dailynews(payload, daily["adapter"], team)
        self.assertEqual(article["description"], "Judge homers twice")
        self.assertEqual(article["published"], "2026-10-09T03:10:00+00:00")

    def test_rss_applies_team_filter_and_excluded_phrases(self):
        team, athletic = source("yankees", "athletic")
        payload = b'''<rss><channel>
          <item><title>Yankees rally late</title><link>https://www.nytimes.com/athletic/1/</link>
            <pubDate>Thu, 08 Oct 2026 14:00:00 GMT</pubDate></item>
          <item><title>Dodgers clinch</title><link>https://www.nytimes.com/athletic/2/</link></item>
          <item><title>How a Red Sox folk hero beat the Yankees</title>
            <link>https://www.nytimes.com/athletic/3/</link></item>
        </channel></rss>'''
        articles = news_adapters.rss(payload, athletic["adapter"], team)
        self.assertEqual([article["title"] for article in articles], ["Yankees rally late"])
        self.assertEqual(articles[0]["published"], "2026-10-08T14:00:00+00:00")

    def test_fusion_reads_section_stories_newest_first(self):
        team, times = source("rays", "tampabay")
        cache = {"feed": [
            {"website_url": "/sports/rays/2026/10/07/older/", "headlines": {"basic": "Older"},
             "display_date": "2026-10-07T10:00:00Z"},
            {"website_url": "/news/elsewhere/", "headlines": {"basic": "Not Rays"}},
            {"website_url": "/sports/rays/2026/10/08/newer/", "headlines": {"basic": "Newer"},
             "subheadlines": {"basic": "Game 3 preview"}, "display_date": "2026-10-08T10:00:00Z"},
        ]}
        payload = f"<script>Fusion.contentCache={json.dumps(cache)};</script>".encode()
        articles = news_adapters.fusion(payload, times["adapter"], team)
        self.assertEqual([article["title"] for article in articles], ["Newer", "Older"])
        self.assertEqual(articles[0]["url"], "https://www.tampabay.com/sports/rays/2026/10/08/newer/")

    def test_fusion_without_content_cache_is_a_markup_failure(self):
        team, times = source("rays", "tampabay")
        with self.assertRaises(news_adapters.AdapterError):
            news_adapters.fusion(b"<html>redesigned</html>", times["adapter"], team)


class AdapterFetchTests(unittest.TestCase):
    def test_adapter_source_is_fetched_directly_and_labelled_from_the_registry(self):
        team, mets_post = source("mets", "nypost")
        payload = b'''<h3 class="story__headline"><a href="https://nypost.com/2026/10/03/sports/mets-a/">Mets a</a></h3>'''
        with patch.object(news, "fetch_page", return_value=payload) as fetch, \
                patch.object(news, "fetch_xml") as bing:
            feed = news.source_feed(team, mets_post)
        fetch.assert_called_once_with(mets_post["adapter"]["url"])
        bing.assert_not_called()
        self.assertEqual((feed["source"], feed["source_url"]), (mets_post["name"], mets_post["url"]))
        self.assertEqual(len(feed["articles"]), 1)

    def test_empty_publisher_page_counts_toward_the_failure_streak(self):
        team, mets_post = source("mets", "nypost")
        with patch.object(news, "fetch_page", return_value=b"<html></html>"):
            with self.assertRaises(news.NewsSourceTransientError):
                news.source_feed(team, mets_post)

    def test_refused_default_client_falls_back_to_approved_identity(self):
        refused = HTTPError("https://nypost.com/new-york-mets/", 403, "Forbidden", {}, None)
        with patch.object(news, "urlopen", side_effect=[refused, io.BytesIO(b"page")]) as request, \
                patch.object(news.time, "sleep"):
            self.assertEqual(news.fetch_page("https://nypost.com/new-york-mets/"), b"page")
        self.assertEqual(request.call_count, 2)
        self.assertEqual(request.call_args.args[0].get_header("User-agent"), news.FALLBACK_USER_AGENT)

    def test_every_adapter_names_a_known_parser_and_https_url(self):
        for team in news.shared_news_teams():
            for item in team["news_sources"]:
                adapter = item.get("adapter")
                if adapter:
                    with self.subTest(team=team["api_key"], source=item["key"]):
                        self.assertIn(adapter["kind"], news_adapters.PARSERS)
                        self.assertTrue(adapter["url"].startswith("https://"))


if __name__ == "__main__":
    unittest.main()
