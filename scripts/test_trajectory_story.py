"""Chart contract and official-source reconciliation; no upstream or production writes."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from build_white_sox_story import build, derive, season_games
from publish_story import stage
from story_content import encoded, validate_payload, validate_tree

ROOT = Path(__file__).resolve().parents[1]

class TrajectoryTests(unittest.TestCase):
    def setUp(self):
        self.proof = json.loads((ROOT / 'docs/stories/white-sox-story-source.json').read_text())
        self.story = build(self.proof)

    def test_exact_totals_checkpoints_and_no_smoothing(self):
        chart = self.story['chart']
        self.assertEqual([s['points'][-1]['y'] for s in chart['series']], [41, 60, 84])
        self.assertEqual(chart['xAxis']['maximum'], 162)
        self.assertEqual(chart['yAxis']['minimum'], 0)
        self.assertEqual(chart['yAxis']['maximum'], 90)
        self.assertEqual([chart['series'][2]['points'][n]['y'] for n in [77, 78, 79, 80, 116, 117]], [40, 41, 41, 42, 60, 61])
        for series in chart['series']:
            self.assertEqual(len(series['points']), 163)
            self.assertTrue(all(b['y'] - a['y'] in [0, 1] for a, b in zip(series['points'], series['points'][1:])))

    def test_changed_source_rejected(self):
        for number in [77, 79, 116, 161]:
            source = copy.deepcopy(self.proof); source['seasons'][2]['games'][number]['wins'] += 1
            with self.assertRaises(ValueError): build(source)

    def test_sequence_comparison_and_legacy_capabilities(self):
        chart = self.story['chart']
        self.assertEqual(chart['sequence']['secondsPerSeries'], 2)
        self.assertEqual(chart['emphasis'][0]['holdSeconds'], 2)
        for change in [lambda p: p['chart']['sequence'].update(secondsPerSeries=float('nan')),
                       lambda p: p['chart']['sequence'].update(secondsPerSeries=3),
                       lambda p: p['chart']['emphasis'][0]['comparison'].update(targetSeriesID='season-2025'),
                       lambda p: p['chart']['emphasis'][0]['comparison'].update(sourceSeriesID='missing')]:
            p = copy.deepcopy(self.story); change(p)
            with self.assertRaises(ValueError): validate_payload(p)
        legacy = copy.deepcopy(self.story)
        legacy['chart'].pop('sequence'); legacy['chart']['emphasis'][0].pop('comparison')
        legacy['chart']['emphasis'][0]['holdSeconds'] = .9
        validate_payload(legacy)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); payload = root / 'story.json'; payload.write_bytes(encoded(legacy))
            self.assertEqual(stage(payload, root / 'data', 'Legacy', [145])['stories'][0]['minimumRendererVersion'], 2)

    def test_final_duplicate_and_postponement_filter(self):
        game = {'gamePk': 7, 'gameType': 'R', 'officialDate': '2026-06-23', 'gameNumber': 1, 'gameDate': '2026-06-23T23:00:00Z',
                'status': {'abstractGameState': 'Final', 'codedGameState': 'F'},
                'teams': {'home': {'team': {'id': 145}, 'isWinner': True}, 'away': {'team': {'id': 111}}}}
        postponed = {**game, 'gamePk': 9, 'status': {'abstractGameState': 'Final', 'codedGameState': 'D'}}
        postseason = {**game, 'gamePk': 10, 'gameType': 'D'}
        schedule = {'dates': [{'games': [game, copy.deepcopy(game), postponed, postseason]}]}
        self.assertEqual([g['gamePk'] for g in season_games(schedule)], [7])
        conflicting = copy.deepcopy(game); conflicting['teams']['home']['isWinner'] = False
        schedule['dates'][0]['games'].append(conflicting)
        with self.assertRaises(ValueError): season_games(schedule)

    def test_unbounded_or_malformed_chart_rejected(self):
        mutations = [lambda p: p['chart'].update(durationSeconds=100), lambda p: p['chart'].update(kind='execute'),
                     lambda p: p['chart']['series'][0]['points'][1].update(x=0), lambda p: p['chart']['series'][0]['points'][1].update(y=-1),
                     lambda p: p['chart']['series'][0]['points'][1].update(y=float('nan')), lambda p: p['chart']['xAxis'].update(maximum=0),
                     lambda p: p['chart']['emphasis'][0].update(holdSeconds=8), lambda p: p['sources'][0].update(url='javascript:bad')]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                story = copy.deepcopy(self.story); mutate(story)
                with self.assertRaises(ValueError): validate_payload(story)

    def test_all_chart_kinds_and_version_gated_local_staging(self):
        for kind in ['line', 'step', 'bar']:
            story = copy.deepcopy(self.story); story['chart']['kind'] = kind
            if kind == 'bar':
                story['chart']['emphasis'][0].pop('comparison')
                for row in story['chart']['series']: row['points'] = [row['points'][0], row['points'][-1]]
            validate_payload(story)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); payload = root / 'story.json'; payload.write_bytes(encoded(self.story))
            catalog = stage(payload, root / 'data', 'Chart first', [145])
            entry = catalog['stories'][0]
            self.assertEqual(entry['minimumRendererVersion'], 3)
            self.assertEqual(entry['renderer'], 'chart-trajectory')
            self.assertIn('84', entry['fallback'])
            self.assertEqual(validate_tree(root / 'data'), catalog)
            wrong = {**entry, 'minimumRendererVersion': 1}
            with self.assertRaises(ValueError): validate_payload(self.story, wrong)

if __name__ == '__main__': unittest.main()
