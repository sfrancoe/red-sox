#!/usr/bin/env python3
"""Offline regression coverage for the pitching policy, transport and publication."""
import io
import json
import tempfile
import unittest
from datetime import date, datetime, timezone, timedelta
from email.utils import format_datetime
from pathlib import Path
from urllib.error import HTTPError, URLError
from unittest.mock import patch

import refresh_pitching as pitching
from team_registry import all_teams


class Clock:
    def __init__(self):
        self.now = 1000.0
        self.sleeps = []

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds


def limited(value=None):
    return HTTPError('https://www.fangraphs.com/test', 429, 'limited',
                     {} if value is None else {'Retry-After': value}, None)


class PitchingTests(unittest.TestCase):
    def setUp(self):
        self.policy = pitching.load_policy()
        self.clock = Clock()
        self.patches = [patch.object(pitching.time, 'monotonic', self.clock.monotonic),
                        patch.object(pitching.time, 'sleep', self.clock.sleep)]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    def test_season_boundaries(self):
        for day, allowed in [('2026-10-01', True), ('2026-10-31', True),
                             ('2026-11-01', False), ('2026-12-31', False),
                             ('2027-01-01', False), ('2027-10-05', False)]:
            self.assertEqual(pitching.refresh_allowed(self.policy, date.fromisoformat(day)), allowed)

    def test_frozen_has_no_network_or_writes(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(pitching, 'FanGraphsClient') as client:
            root = Path(directory)
            path = root / 'sentinel'
            path.write_bytes(b'last good')
            self.assertEqual(pitching.refresh(all_teams(), self.policy, root, date(2027, 1, 1)), [])
            client.assert_not_called()
            self.assertEqual(path.read_bytes(), b'last good')
            self.assertEqual(list(root.iterdir()), [path])

    def test_request_spacing_includes_transient_retry(self):
        starts = []
        outcomes = [URLError('temporary'), b'[]', b'[]']
        def respond(*args, **kwargs):
            starts.append(self.clock.now)
            outcome = outcomes.pop(0)
            if isinstance(outcome, Exception):
                raise outcome
            return io.BytesIO(outcome)
        with patch.object(pitching, 'urlopen', side_effect=respond):
            client = pitching.FanGraphsClient()
            client.get('https://www.fangraphs.com/a')
            client.get('https://www.fangraphs.com/b')
        self.assertEqual(starts, [1000, 1010, 1020])

    def test_full_retry_after_and_fallback(self):
        for header, delay in [('720', 720), (None, 300), ('garbage', 300), ('-1', 300), ('NaN', 300), ('Infinity', 300), ('-Infinity', 300)]:
            self.clock.now = 1000
            with patch.object(pitching, 'urlopen', side_effect=[limited(header), io.BytesIO(b'[]')]) as request:
                client = pitching.FanGraphsClient()
                with self.assertRaises(pitching.RateLimited):
                    client.get('https://www.fangraphs.com/a')
                self.assertEqual(request.call_count, 1)  # Never immediate/fallback-UA retry on 429.
                client.get('https://www.fangraphs.com/b')
                self.assertEqual(self.clock.now, 1000 + delay)

    def test_http_date_retry_after(self):
        now = datetime(2026, 10, 5, tzinfo=timezone.utc)
        with patch.object(pitching, 'datetime') as dt, patch.object(pitching, 'urlopen', side_effect=[
            limited(format_datetime(now + timedelta(seconds=900), usegmt=True)), io.BytesIO(b'[]')
        ]):
            dt.now.return_value = now
            client = pitching.FanGraphsClient()
            with self.assertRaises(pitching.RateLimited):
                client.get('https://www.fangraphs.com/a')
            client.get('https://www.fangraphs.com/b')
        self.assertEqual(self.clock.now, 1900)

    def test_over_budget_retry_after_does_not_request_early(self):
        with patch.object(pitching, 'urlopen', side_effect=limited('3600')) as request:
            client = pitching.FanGraphsClient(budget=1800)
            with self.assertRaises(pitching.RateLimited):
                client.get('https://www.fangraphs.com/a')
            with self.assertRaisesRegex(RuntimeError, 'budget'):
                client.get('https://www.fangraphs.com/b')
            self.assertEqual(request.call_count, 1)
            self.assertEqual(self.clock.sleeps, [])

    def test_cache_shared_all_teams_and_deferred_retry(self):
        teams = all_teams()
        projections = [{'xMLBAMID': 1}]
        calls = []
        attempts = {}
        def build(team, shared, season, client):
            self.assertIs(shared, projections)
            self.assertEqual(season, 2026)
            key = team['api_key']
            calls.append(key)
            attempts[key] = attempts.get(key, 0) + 1
            if key == 'giants' and attempts[key] == 1:
                raise pitching.RateLimited('429')
            return {'season': season, 'pitchers': [key]}
        with tempfile.TemporaryDirectory() as directory, patch.object(pitching.FanGraphsClient, 'get', return_value=projections) as get, patch.object(pitching, 'build_team', side_effect=build):
            self.assertEqual(pitching.refresh(teams, self.policy, Path(directory), date(2026, 10, 5)), [])
            get.assert_called_once_with(self.policy['projections_url'])
            self.assertEqual(calls[:-1], [team['api_key'] for team in teams])
            self.assertEqual(calls[-1], 'giants')
            self.assertEqual(len(list(Path(directory).rglob('pitching.json'))), 30)

    def test_partial_failure_keeps_last_good_and_reports(self):
        teams = [all_teams()[0], next(t for t in all_teams() if t['api_key'] == 'giants')]
        attempts = []
        def build(team, *args):
            attempts.append(team['api_key'])
            if team['api_key'] == 'giants':
                raise pitching.RateLimited('429')
            return {'season': 2026, 'pitchers': ['healthy']}
        with tempfile.TemporaryDirectory() as directory, patch.object(pitching.FanGraphsClient, 'get', return_value=[{}]), patch.object(pitching, 'build_team', side_effect=build), patch('sys.stderr', new_callable=io.StringIO) as errors:
            root = Path(directory)
            failed_path = pitching.output_path(teams[1], root)
            failed_path.parent.mkdir(parents=True)
            failed_path.write_bytes(b'last-good-giants')
            self.assertEqual(pitching.refresh(teams, self.policy, root, date(2026, 10, 5)), ['giants'])
            self.assertEqual(failed_path.read_bytes(), b'last-good-giants')
            self.assertIn('healthy', pitching.output_path(teams[0], root).read_text())
            self.assertIn('giants', errors.getvalue())
            self.assertEqual(attempts, ['redsox', 'giants', 'giants'])

    def test_shared_projection_failure_keeps_every_snapshot(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(pitching.FanGraphsClient, 'get', side_effect=pitching.RateLimited('429')) as get:
            root = Path(directory)
            self.assertEqual(pitching.refresh(all_teams(), self.policy, root, date(2026, 10, 5)), [t['api_key'] for t in all_teams()])
            self.assertEqual(get.call_count, 2)
            self.assertEqual(list(root.iterdir()), [])

    def test_force_uses_configured_season_after_new_year(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(pitching.FanGraphsClient, 'get', return_value=[{}]), patch.object(pitching, 'build_team', return_value={'season': 2026}) as build:
            self.assertEqual(pitching.refresh([all_teams()[0]], self.policy, Path(directory), date(2027, 1, 1), force=True), [])
            self.assertEqual(build.call_args.args[2], 2026)

    def test_generic_builder_equals_current_shape(self):
        import fetch_team_data
        import fetch_pitching
        team = all_teams()[0]
        projections = [{'xMLBAMID': 123, 'WAR': 3, 'IP': 160}]
        actual = {'data': [{'xMLBAMID': 123, 'PlayerName': 'Pitcher', 'IP': '100.2', 'WAR': 4}]}
        standings = {'records': [{'teamRecords': [{'team': {'id': 111}, 'wins': 90, 'losses': 72}]}]}
        expected = fetch_pitching.build_feed(projections, actual, standings, 2026)
        actual = fetch_team_data.build_pitching_feed(team, projections, actual, standings, 2026)
        expected.pop('generated_at'); actual.pop('generated_at')
        self.assertEqual(actual, expected)

    def test_all_real_builders_share_transport_and_projection_response(self):
        teams = all_teams()
        starts = []
        urls = []
        projections = [{"xMLBAMID": 123, "WAR": 3, "IP": 160}]
        actual = {"data": [{"xMLBAMID": 123, "PlayerName": "Pitcher", "IP": "100.2", "WAR": 4}]}
        standings = {"records": [{"teamRecords": [
            {"team": {"id": team["mlb_id"]}, "wins": 90, "losses": 72} for team in teams
        ]}]}
        def respond(request, **kwargs):
            urls.append(request.full_url)
            starts.append(self.clock.now)
            return io.BytesIO(json.dumps(projections if '/projections?' in request.full_url else actual).encode())
        with tempfile.TemporaryDirectory() as directory, patch.object(pitching, 'urlopen', side_effect=respond), patch.object(pitching, 'fetch_json', return_value=standings):
            root = Path(directory)
            self.assertEqual(pitching.refresh(teams, self.policy, root, date(2026, 10, 5)), [])
            self.assertEqual(len(urls), 31)
            self.assertEqual(sum('/projections?' in url for url in urls), 1)
            self.assertTrue(all(b - a >= 10 for a, b in zip(starts, starts[1:])))
            for team in teams:
                feed = json.loads(pitching.output_path(team, root).read_text())
                self.assertEqual(feed['season'], 2026)
                self.assertEqual(feed['team'], team['full_name'])
                self.assertEqual(feed['pitchers'][0]['forecast']['war'], 3)

    def test_atomic_write_failure_preserves_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'pitching.json'
            path.write_bytes(b'last-good')
            with patch.object(pitching.json, 'dumps', side_effect=ValueError('serialization failed')):
                with self.assertRaises(ValueError):
                    pitching.write_snapshot(path, {'season': 2026})
            self.assertEqual(path.read_bytes(), b'last-good')
            self.assertEqual(list(Path(directory).iterdir()), [path])

    def test_unchanged_snapshot_retains_timestamp(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'pitching.json'
            path.write_text('{"generated_at":"old","season":2026}')
            original = path.read_bytes()
            pitching.write_snapshot(path, {'generated_at': 'new', 'season': 2026})
            self.assertEqual(path.read_bytes(), original)

    def test_workflow_weekly_october_short_publication_lock(self):
        workflow = (pitching.ROOT / '.github/workflows/refresh-mlb-pitching.yml').read_text()
        self.assertIn("cron: '55 12 * 10 1'", workflow)
        fetch, publish = workflow.split('\n  publish:')
        self.assertNotIn('group: site-data-writes', fetch)
        self.assertIn('group: site-data-writes', publish)
        self.assertIn("needs.fetch.outputs.outcome == 'failure'", publish)
        self.assertIn("steps.guarded.outcome == 'failure'", publish)
        self.assertNotIn('git pull --rebase', publish)
        self.assertIn('git push origin HEAD:main', publish)
        self.assertIn('pitching_publication.py apply', publish)
        self.assertIn('pitching_publication.py stage', fetch)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        import pitching_publication
        self.publication = pitching_publication
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / 'repo'
        self.artifact = Path(self.directory.name) / 'artifact'
        self.teams = all_teams()[:2]
        self.original = {}
        for relative in self.publication.GUARDS:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(pitching.load_policy() if 'pitching-refresh' in relative else {}))
        for team in self.teams:
            path = pitching.output_path(team, self.root)
            path.parent.mkdir(parents=True, exist_ok=True)
            old = json.dumps({'season': 2026, 'pitchers': ['original']}).encode()
            self.original[path.relative_to(self.root).as_posix()] = old
            path.write_text(json.dumps({'season': 2026, 'pitchers': ['fetched']}))
        self.team_patch = patch.object(self.publication, 'all_teams', return_value=self.teams)
        self.team_patch.start()
        self.addCleanup(self.team_patch.stop)
        with patch.object(self.publication, 'source_bytes', side_effect=lambda root, path: self.original[path]):
            self.publication.stage(self.root, self.artifact)
        # Publication starts from source main, not the fetch working tree.
        for relative, payload in self.original.items():
            (self.root / relative).write_bytes(payload)

    def test_matching_sources_publish(self):
        self.assertEqual(self.publication.apply(self.root, self.artifact), [])
        self.assertEqual(len((self.artifact / 'accepted-paths').read_text().splitlines()), 2)
        for team in self.teams:
            self.assertEqual(json.loads(pitching.output_path(team, self.root).read_text())['pitchers'], ['fetched'])

    def test_newer_snapshot_preserved_while_independent_healthy_publishes(self):
        newer = pitching.output_path(self.teams[0], self.root)
        newer.write_text('{"season":2026,"pitchers":["corrected-on-main"]}')
        original_bytes = newer.read_bytes()
        errors = self.publication.apply(self.root, self.artifact)
        self.assertEqual(len(errors), 1)
        self.assertIn('changed during fetch', errors[0])
        self.assertEqual(newer.read_bytes(), original_bytes)
        healthy = pitching.output_path(self.teams[1], self.root)
        self.assertEqual(json.loads(healthy.read_text())['pitchers'], ['fetched'])
        self.assertEqual((self.artifact / 'accepted-paths').read_text().splitlines(), [healthy.relative_to(self.root).as_posix()])

    def test_policy_or_registry_change_rejects_all(self):
        for relative in self.publication.GUARDS:
            with self.subTest(relative=relative):
                path = self.root / relative
                old = path.read_bytes()
                path.write_bytes(old + b' ')
                self.assertIn('rejected all', self.publication.apply(self.root, self.artifact)[0])
                self.assertEqual((self.artifact / 'accepted-paths').read_text(), '')
                for original_path, payload in self.original.items():
                    self.assertEqual((self.root / original_path).read_bytes(), payload)
                path.write_bytes(old)

    def test_wrong_artifact_season_rejected(self):
        manifest_path = self.artifact / 'manifest.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['season'] = 2027
        manifest_path.write_text(json.dumps(manifest))
        self.assertIn('season', self.publication.apply(self.root, self.artifact)[0])
        self.assertEqual((self.artifact / 'accepted-paths').read_text(), '')

    def test_wrong_feed_season_and_digest_preserve_originals(self):
        manifest = json.loads((self.artifact / 'manifest.json').read_text())
        for entry in manifest['files']:
            (self.artifact / entry['path']).write_text('{"season":2027}')
        self.assertEqual(len(self.publication.apply(self.root, self.artifact)), 2)
        for relative, payload in self.original.items():
            self.assertEqual((self.root / relative).read_bytes(), payload)

    def test_offline_ci_runs_pitching_regressions(self):
        workflow = (pitching.ROOT / '.github/workflows/validate-refresh.yml').read_text()
        offline = workflow.split('  live:')[0]
        self.assertIn("python3 -m unittest discover -s scripts -p 'test_pitching_refresh.py'", offline)
        self.assertIn("'scripts/pitching_publication.py'", offline)
        self.assertIn("'config/pitching-refresh.json'", offline)


if __name__ == '__main__':
    unittest.main()
