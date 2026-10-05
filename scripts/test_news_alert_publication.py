"""Offline Git transaction tests of the actual expansion-news publish commands."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from news_source_status import atomic_json

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / '.github/workflows/refresh-mlb-team-news.yml'
STATUS = '.github/news-status/expansion.json'


def git(directory, *args):
    return subprocess.run(['git', '-C', str(directory), *args], text=True, capture_output=True, check=True).stdout.strip()


class PublicationTests(unittest.TestCase):
    def test_atomic_replace_failure_preserves_previous_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'feed.json'
            path.write_text('{"articles": ["last good"]}')
            before = path.read_bytes()
            with patch('news_source_status.os.replace', side_effect=OSError('disk error')):
                with self.assertRaises(OSError):
                    atomic_json(path, {'articles': ['new']})
            self.assertEqual(path.read_bytes(), before)
            self.assertEqual(list(Path(directory).iterdir()), [path])

    def test_atomic_data_status_publication_and_rejected_race(self):
        workflow = WORKFLOW.read_text()
        start = workflow.index('          git config', workflow.index('- name: Commit if news changed'))
        end = workflow.index('      - name: Report incomplete refresh', start)
        commands = '\n'.join(line[10:] for line in workflow[start:end].splitlines())
        self.assertIn("if: steps.news.outputs.publish_ready == 'true'", workflow)
        self.assertIn('git pull --ff-only origin main', workflow)
        self.assertNotIn('--rebase', workflow)
        self.assertIn('group: site-data-writes', workflow)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            remote, writer, racer = (root / name for name in ('remote.git', 'writer', 'racer'))
            git(root, 'init', '--bare', '--initial-branch=main', str(remote))
            git(root, 'clone', str(remote), str(writer))
            git(writer, 'config', 'user.name', 'Offline test')
            git(writer, 'config', 'user.email', 'offline@example.invalid')
            (writer / 'data').mkdir()
            (writer / Path(STATUS).parent).mkdir(parents=True)
            (writer / STATUS).write_text('{"version": 1, "sources": {}}')
            (writer / 'data/failed.json').write_text('last good')
            (writer / 'data/healthy.json').write_text('old')
            git(writer, 'add', '.')
            git(writer, 'commit', '-m', 'fixture')
            git(writer, 'push', 'origin', 'main')
            (writer / STATUS).write_text('{"version": 1, "sources": {"failed": 1}}')
            (writer / 'data/healthy.json').write_text('new')
            result = subprocess.run(['bash', '-e', '-c', commands], cwd=writer, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(git(remote, 'show', 'main:data/failed.json'), 'last good')
            self.assertEqual(git(remote, 'show', 'main:data/healthy.json'), 'new')
            self.assertEqual(json.loads(git(remote, 'show', f'main:{STATUS}'))['sources']['failed'], 1)
            git(root, 'clone', str(remote), str(racer))
            git(racer, 'config', 'user.name', 'Offline racer')
            git(racer, 'config', 'user.email', 'offline@example.invalid')
            (racer / 'unrelated').write_text('racing main update')
            git(racer, 'add', '.')
            git(racer, 'commit', '-m', 'race')
            git(racer, 'push', 'origin', 'main')
            published = git(remote, 'rev-parse', 'main')
            (writer / STATUS).write_text('{"version": 1, "sources": {"failed": 2}}')
            (writer / 'data/healthy.json').write_text('stale batch')
            result = subprocess.run(['bash', '-e', '-c', commands], cwd=writer, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('rejected', result.stderr)
            self.assertEqual(git(remote, 'rev-parse', 'main'), published)
            self.assertEqual(git(remote, 'show', 'main:data/healthy.json'), 'new')
            self.assertEqual(json.loads(git(remote, 'show', f'main:{STATUS}'))['sources']['failed'], 1)


if __name__ == '__main__':
    unittest.main()
