"""Checks the story's scoring contract and fail-closed generator behavior."""
import copy
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch
import fetch_seasons

ROOT = pathlib.Path(__file__).resolve().parent.parent


class BrewersStoryTests(unittest.TestCase):
    def test_bundled_data_matches_generated_feed(self):
        generated = (ROOT / 'data/brewers/shutouts.json').read_bytes()
        self.assertEqual(generated, (ROOT / 'ios/Hub Ball/Hub Ball/brewers-shutouts.json').read_bytes())
        games = json.loads(generated)['games']
        self.assertEqual([g['total'] for g in games], [22, 20])
        for game in games:
            self.assertEqual(len(game['innings']), 9)
            self.assertEqual(sum(game['innings']), game['total'])
            total = 0
            for play in game['plays']:
                self.assertGreater(play['runs'], 0)
                total += play['runs']
                self.assertEqual(total, play['total'])
            self.assertEqual(total, game['total'])
            for inning in range(1, 10):
                self.assertEqual(sum(p['runs'] for p in game['plays'] if p['inning'] == inning), game['innings'][inning - 1])

    def test_invalid_game_never_overwrites_story(self):
        feed = {
            'gameData': {'status': {'abstractGameState': 'Final'},
                         'teams': {'home': {'id': 158}},
                         'datetime': {'officialDate': '2026-08-18'}},
            'liveData': {'linescore': {'teams': {'home': {'runs': 22}, 'away': {'runs': 1}}}}
        }
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            target = root / 'data/brewers/shutouts.json'
            target.parent.mkdir(parents=True)
            target.write_text('existing story')
            for state in ['Final', 'Live']:
                invalid = copy.deepcopy(feed)
                invalid['gameData']['status']['abstractGameState'] = state
                with self.subTest(state=state), patch.object(fetch_seasons, 'ROOT', root), patch.object(fetch_seasons, 'fetch_json', return_value=invalid):
                    with self.assertRaises(ValueError):
                        fetch_seasons.fetch_brewers_shutouts()
                    self.assertEqual(target.read_text(), 'existing story')


if __name__ == '__main__':
    unittest.main()
