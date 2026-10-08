"""Content integrity, source reconciliation, publication and rollback regressions."""
import copy
import json
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from build_stadium_story import build
from preview_stories import preview_server
from publish_story import rollback, stage
from story_content import CATALOG_LIMIT, PAYLOAD_LIMIT, decode, digest, encoded, entry_path, validate_catalog, validate_payload, validate_tree

ROOT = Path(__file__).resolve().parents[1]


class StoryContentTests(unittest.TestCase):
    def setUp(self):
        self.source = json.loads((ROOT / 'docs/stories/stadium-story-source.json').read_text())
        self.story = build(self.source)

    def test_original_source_reconciliation_and_complete_passport(self):
        self.assertEqual([(p['distance'], p['event']) for p in self.source['plays']], [(356, 'Flyout'), (340, 'Home Run')])
        self.assertEqual([b['value'] for b in self.story['bars']], [6, 1])
        self.assertEqual(self.story['barMaximum'], 30)
        parks = self.story['passport']['items']
        self.assertEqual(len(parks), 30)
        self.assertEqual([(p['id'], p['name']) for p in parks if p['result'] == 'yes'], [('147', 'Yankee Stadium')])
        self.assertEqual(sum(p['result'] == 'no' for p in parks), 29)
        changed = copy.deepcopy(self.source); changed['plays'][0]['distance'] = 350
        with self.assertRaises(ValueError): build(changed)

    def test_invalid_or_unsafe_story_never_validates(self):
        mutations = [lambda p: p.update(schemaVersion=2), lambda p: p.update(schemaVersion=True), lambda p: p.update(barMaximum=5), lambda p: p.update(correctChoiceID='missing'),
                     lambda p: p['sources'][0].update(url='javascript:alert(1)'),
                     lambda p: p['sources'][0].update(url='https://user:pass@example.com'),
                     lambda p: p['bars'][0].update(value=float('nan')),
                     lambda p: p['passport']['items'][0].update(result='probably'),
                     lambda p: p['choices'].append(copy.deepcopy(p['choices'][0])),
                     lambda p: p.update(id='../outside')]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                story = copy.deepcopy(self.story); mutation(story)
                with self.assertRaises(ValueError): validate_payload(story)
        with self.assertRaises(ValueError): decode(b' ' * (PAYLOAD_LIMIT + 1), PAYLOAD_LIMIT)
        with self.assertRaises(ValueError): decode(b'{"x":1,"x":2}', PAYLOAD_LIMIT)

    def test_staging_two_stories_and_rollback_keeps_immutable_payloads(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); payload = root / 'input.json'; payload.write_bytes(encoded(self.story))
            first = stage(payload, root / 'data', 'First story', [139, 147])
            first_path = root / 'first-catalog.json'; first_path.write_bytes(encoded(first))
            original_payload = (root / 'data' / entry_path(first['stories'][0])).read_bytes()
            second_story = {**self.story, 'id': 'second-story', 'title': 'A second fixture'}
            payload.write_bytes(encoded(second_story))
            second = stage(payload, root / 'data', 'Second story', [139])
            self.assertEqual(len(validate_tree(root / 'data')['stories']), 2)
            self.assertEqual((root / 'data' / entry_path(first['stories'][0])).read_bytes(), original_payload)
            result = rollback(first_path, root / 'data')
            self.assertEqual([e['id'] for e in result['stories']], ['this-stadium'])
            self.assertNotEqual(result['revision'], first['revision'])
            self.assertTrue((root / 'data' / entry_path(second['stories'][0])).exists())
            self.assertEqual(len(validate_tree(root / 'data')['stories']), 1)

    def test_failed_publication_or_rollback_does_not_switch_catalog(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); payload = root / 'input.json'; payload.write_bytes(encoded(self.story))
            first = stage(payload, root / 'data', 'First story', [139])
            pointer = root / 'data/stories/catalog-v1.json'; previous = pointer.read_bytes()
            payload.write_bytes(encoded({**self.story, 'correctChoiceID': 'wrong'}))
            with self.assertRaises(ValueError): stage(payload, root / 'data', 'Bad', [139])
            self.assertEqual(pointer.read_bytes(), previous)
            invalid = copy.deepcopy(first); invalid['stories'][0]['revision'] = 'a' * 64
            bad = root / 'bad.json'; bad.write_bytes(encoded(invalid))
            with self.assertRaises(FileNotFoundError): rollback(bad, root / 'data')
            self.assertEqual(pointer.read_bytes(), previous)
            traversal = copy.deepcopy(first); traversal['stories'][0]['id'] = '../outside'
            with self.assertRaises(ValueError): validate_catalog(traversal)

    def test_offline_preview_is_strict_and_serves_both_legacy_paths(self):
        server = preview_server(ROOT / 'data', fixtures=True)
        worker = threading.Thread(target=server.serve_forever, daemon=True); worker.start()
        origin = f'http://127.0.0.1:{server.server_port}'
        def get(path):
            with urllib.request.urlopen(origin + path) as r: return r.read()
        try:
            self.assertEqual(get('/data/stories/catalog-v1.json'), get('/api/data/stories/catalog-v1.json'))
            get('/__fixture/next')
            self.assertEqual(len(json.loads(get('/data/stories/catalog-v1.json'))['stories']), 2)
            get('/__fixture/rollback')
            self.assertEqual(len(json.loads(get('/data/stories/catalog-v1.json'))['stories']), 1)
            for path in ['/api/x-discovery', '/data/../docs/stories/stadium-story-source.json', '/data/stories/catalog-history/no.json']:
                with self.assertRaises(urllib.error.HTTPError) as error: get(path)
                self.assertEqual(error.exception.code, 404)
            get('/__fixture/offline')
            with self.assertRaises(urllib.error.HTTPError) as error: get('/data/stories/catalog-v1.json')
            self.assertEqual(error.exception.code, 503)
        finally:
            server.shutdown(); server.server_close(); worker.join()


if __name__ == '__main__': unittest.main()
