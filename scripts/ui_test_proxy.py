#!/usr/bin/env python3
"""Run UI checks with a local API proxy that never forwards paid discovery calls."""
import http.server
import os
import subprocess
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request


class UIProxy(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        path = urllib.parse.urlsplit(self.path).path
        if path == '/api/x-discovery':
            self.send_response(503)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"error":"Paid discovery disabled during UI tests"}')
            return
        free_routes = {'/api/x-posts', '/api/postseason', '/api/hr-chase'}
        if path not in free_routes and not path.startswith(('/api/mlb/', '/api/data/')):
            self.send_error(404)
            return
        try:
            with urllib.request.urlopen('https://api.autumnlane.io' + self.path, timeout=20) as response:
                body = response.read()
                self.send_response(response.status)
                self.send_header('Content-Type', response.headers.get('Content-Type', 'application/json'))
                self.end_headers()
                self.wfile.write(body)
        except urllib.error.HTTPError as error:
            self.send_response(error.code)
            self.end_headers()
            self.wfile.write(error.read())
        except (OSError, urllib.error.URLError):
            self.send_error(502)

    def log_message(self, format: str, *args) -> None:
        pass


def main() -> int:
    if len(sys.argv) < 2:
        raise SystemExit('Usage: ui_test_proxy.py COMMAND [ARG ...]')
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), UIProxy)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        environment = {**os.environ, 'HUB_UI_API_ROOT': f'http://127.0.0.1:{server.server_port}'}
        return subprocess.call(sys.argv[1:], env=environment)
    finally:
        server.shutdown()
        server.server_close()
        worker.join()


if __name__ == '__main__':
    raise SystemExit(main())
