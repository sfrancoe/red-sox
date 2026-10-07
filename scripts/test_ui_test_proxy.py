"""Verify UI tests cannot forward discovery or unexpected routes upstream."""
import http.client
import http.server
import threading
import unittest
from unittest.mock import MagicMock, patch

from ui_test_proxy import UIProxy


class UIProxyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), UIProxy)
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.worker.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.worker.join()

    def request(self, path: str) -> tuple[int, bytes]:
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port)
        try:
            connection.request('GET', path)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    @patch('ui_test_proxy.urllib.request.urlopen')
    def test_discovery_never_reaches_upstream(self, upstream) -> None:
        for query in ('', '?team=redsox', '?team=yankees&z=1'):
            status, body = self.request('/api/x-discovery' + query)
            self.assertEqual(status, 503)
            self.assertIn(b'Paid discovery disabled', body)
        upstream.assert_not_called()

    @patch('ui_test_proxy.urllib.request.urlopen')
    def test_unlisted_routes_never_reach_upstream(self, upstream) -> None:
        for path in ('/unknown', '/.netlify/functions/x-discovery', '/api/x-discovery/'):
            self.assertEqual(self.request(path)[0], 404)
        upstream.assert_not_called()

    @patch('ui_test_proxy.urllib.request.urlopen')
    def test_free_route_preserves_query_and_response(self, upstream) -> None:
        response = MagicMock(status=200, headers={'Content-Type': 'application/json'})
        response.read.return_value = b'{"schema":2}'
        upstream.return_value.__enter__.return_value = response
        path = '/api/mlb/game?team=redsox&gamePk=824708'
        self.assertEqual(self.request(path), (200, b'{"schema":2}'))
        upstream.assert_called_once_with('https://api.autumnlane.io' + path, timeout=20)


if __name__ == '__main__':
    unittest.main()
