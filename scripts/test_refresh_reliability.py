"""Offline regressions for recurring refresh failures; no generated files changed."""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError

import fetch_players as players
import http_refresh as http


class RefreshReliabilityTests(unittest.TestCase):
    def test_static_player_release_reads_only_the_requested_player(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            archive.writestr('players/other001_b.csv', 'gid,stattype,gametype,b_h,b_ab\nBOS202501010,value,regular,99,99\n')
            archive.writestr('players/abrew002_b.csv', 'gid,stattype,gametype,b_h,b_ab\nBOS202501010,value,regular,2,4\nBOS202601010,value,regular,99,99\n')
        with zipfile.ZipFile(buffer) as archive, patch.object(players, 'retrosheet_archive', return_value=archive):
            stats = players.career_stats('abrew002')
            self.assertEqual(stats['batting']['hits'], 2)
            self.assertEqual(stats['batting']['average'], .5)
            self.assertEqual(players.career_stats('newp001')['status'], 'not_in_2025_release')
            self.assertEqual(players.career_stats(None)['status'], 'not_in_2025_release')

    def test_static_archive_is_downloaded_once_and_reused_from_disk(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            archive.writestr('abrew002_b.csv', 'gid,stattype,gametype\n')
        with tempfile.TemporaryDirectory() as directory, patch.dict('os.environ', {'RETROSHEET_CACHE_DIR': directory}), patch.object(players, 'urlopen', return_value=io.BytesIO(buffer.getvalue())) as request:
            players.retrosheet_archive.cache_clear()
            archive = players.retrosheet_archive()
            self.assertEqual(request.call_count, 1)
            self.assertIs(players.retrosheet_archive(), archive)
            archive.close()
            players.retrosheet_archive.cache_clear()
            archive = players.retrosheet_archive()
            self.assertEqual(request.call_count, 1)
            self.assertIn('abrew002_b.csv', archive.namelist())
            archive.close()
            players.retrosheet_archive.cache_clear()

    def test_invalid_archive_does_not_poison_the_disk_cache(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict('os.environ', {'RETROSHEET_CACHE_DIR': directory}), patch.object(players, 'urlopen', side_effect=lambda *a, **k: io.BytesIO(b'<html>error</html>')), patch.object(players.time, 'sleep'):
            players.retrosheet_archive.cache_clear()
            with self.assertRaises(RuntimeError):
                players.retrosheet_archive()
            self.assertEqual(list(Path(directory).iterdir()), [])
            players.retrosheet_archive.cache_clear()

    def test_rate_limit_honors_retry_after_and_retries(self):
        error = HTTPError('https://www.fangraphs.com/api/test', 429, 'rate limited', {'Retry-After': '60'}, None)
        with patch.object(http, 'urlopen', side_effect=[error, io.BytesIO(b'{"data":[1]}')]) as request, patch.object(http.time, 'sleep') as sleep:
            result = http.fetch_json('https://www.fangraphs.com/api/test')
        self.assertEqual(result, {'data': [1]})
        self.assertEqual(request.call_count, 2)
        self.assertIn(unittest.mock.call(60), sleep.call_args_list)
        self.assertNotIn('User-agent', request.call_args_list[0].args[0].headers)

    def test_invalid_response_fails_after_bounded_retries(self):
        with patch.object(http, 'urlopen', side_effect=lambda *a, **k: io.BytesIO(b'<html>overlay</html>')) as request, patch.object(http.time, 'sleep'):
            with self.assertRaises(RuntimeError):
                http.fetch_json('https://example.org/feed')
        self.assertEqual(request.call_count, 4)
        self.assertEqual(request.call_args.args[0].headers['User-agent'], http.FALLBACK_USER_AGENT)

    def test_game_refresh_has_no_player_provider_dependency(self):
        workflow = (players.ROOT / '.github/workflows/refresh-schedule.yml').read_text()
        self.assertNotIn('fetch_players.py', workflow)
        self.assertNotIn('data/players.json', workflow)
        self.assertIn('fetch_standings.py', workflow)


if __name__ == '__main__':
    unittest.main()
