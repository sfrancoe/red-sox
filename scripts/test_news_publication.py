"""Publisher publication-time extraction without network requests."""

import unittest
from unittest.mock import patch

from news_publication import publication_from_html, timestamp, fetch_publication


class PublicationTests(unittest.TestCase):
    url = "https://example.com/story/"

    def test_original_publication_not_modified_or_search_time(self):
        html = '''<meta property="article:modified_time" content="2026-09-30T04:55:39+00:00">
        <meta property="article:published_time" content="2026-09-30T04:14:46+00:00">'''
        self.assertEqual(publication_from_html(html, self.url), "2026-09-30T04:14:46+00:00")

    def test_json_ld_graph_and_offset(self):
        html = '''<script type="application/ld+json">{"@graph":[
            {"@type":"VideoObject","datePublished":"2026-09-28T00:00:00Z"},
            {"@type":"NewsArticle","url":"https://example.com/story/",
             "datePublished":"2026-09-30T00:14:46-04:00"}]}</script>'''
        self.assertEqual(publication_from_html(html, self.url), "2026-09-30T04:14:46+00:00")

    def test_unknown_and_ambiguous_times_stay_unknown(self):
        for html in [
            '<meta name="sailthru.date" content="2026-09-30 00:14:46">',
            '<meta property="article:published_time" content="2026-09-30T00:14:46">',
            '<meta property="article:modified_time" content="2026-09-30T04:55:39Z">',
            '<script type="application/ld+json">bad json</script>',
            '<script>var datePublished = "2026-09-30T04:55:39Z";</script>',
        ]:
            self.assertIsNone(publication_from_html(html, self.url))
        self.assertIsNone(timestamp("2026-09-30"))

    def test_related_article_is_not_selected(self):
        html = '''<script type="application/ld+json">{"@type":"NewsArticle",
            "url":"https://example.com/other-story/","datePublished":"2026-09-30T04:14:46Z"}</script>'''
        self.assertIsNone(publication_from_html(html, self.url))

    def test_normal_user_agent_then_single_fallback(self):
        from urllib.error import HTTPError
        with patch("news_publication.urlopen", side_effect=HTTPError(self.url, 403, "Blocked", {}, None)) as request:
            with self.assertRaises(RuntimeError):
                fetch_publication(self.url)
        self.assertEqual(request.call_count, 2)
        self.assertIsNone(request.call_args_list[0].args[0].get_header("User-agent"))
        self.assertEqual(request.call_args_list[1].args[0].get_header("User-agent"),
                         "OpenAI File Downloader, XaiImageApiFetch/1.0")


if __name__ == "__main__":
    unittest.main()
