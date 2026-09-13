import unittest
from unittest.mock import patch
import app_store_preflight as preflight


class EndpointTests(unittest.TestCase):
    def check(self, url, payload):
        with patch.object(preflight, 'discovered_urls', return_value=[url]), patch.object(preflight, 'fetch_url', return_value=(200, payload)):
            return preflight.check_live_endpoints()[0]

    def test_editorial_article_is_html(self):
        url = next(iter(preflight.EDITORIAL_LINKS))
        self.assertEqual(self.check(url, b'<html><head><title>Brewers</title></head></html>').status, 'PASS')
        self.assertEqual(self.check(url, b'not a page').status, 'FAIL')

    def test_data_endpoint_still_requires_json(self):
        url = 'https://red-sox.netlify.app/api/data/seasons.json'
        self.assertEqual(self.check(url, b'<html><title>Error</title></html>').status, 'FAIL')
        self.assertEqual(self.check(url, b'{"2026": {}}').status, 'PASS')


if __name__ == '__main__':
    unittest.main()
