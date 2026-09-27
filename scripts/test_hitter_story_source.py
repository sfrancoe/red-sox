#!/usr/bin/env python3
"""Check inclusion/rounding boundaries and reconcile generated story counts."""
from copy import deepcopy
from decimal import Decimal
import json
import re
import unittest
from fetch_hitter_story import ROOT, extract_season


class HitterSourceTests(unittest.TestCase):
    def fixture(self) -> dict:
        return {'stats': [{'totalSplits': 3, 'splits': [
            {'season': '2025', 'player': {'id': index, 'fullName': f'Player {index}'},
             'stat': {'avg': avg, 'hits': hits, 'atBats': 601, 'plateAppearances': 650}}
            for index, avg, hits in [(1, '.299', 180), (2, '.300', 180), (3, '.301', 181)]
        ]}]}

    def test_includes_displayed_300_even_when_raw_fraction_is_lower(self):
        season = extract_season(2025, self.fixture())
        self.assertLess(180 / 601, .300)
        self.assertEqual(season['count'], 2)

    def test_rejects_partial_and_duplicate_leaderboards(self):
        partial = self.fixture()
        partial['stats'][0]['totalSplits'] = 4
        with self.assertRaises(ValueError):
            extract_season(2025, partial)
        duplicates = self.fixture()
        duplicates['stats'][0]['splits'][1] = deepcopy(duplicates['stats'][0]['splits'][0])
        with self.assertRaises(ValueError):
            extract_season(2025, duplicates)

    def test_reconciles_all_source_counts_and_swift_module(self):
        snapshot = json.loads((ROOT / 'data/mlb300-hitters.json').read_text())
        seasons = snapshot['seasons']
        self.assertEqual([s['year'] for s in seasons], list(range(1976, 2027)))
        swift = (ROOT / 'ios/Hub Ball/Hub Ball/MLB300HitterData.swift').read_text()
        swift_counts = [(int(y), int(n)) for y, n in re.findall(r'\.init\(year: (\d+), count: (\d+)', swift)]
        self.assertEqual(swift_counts, [(s['year'], s['count']) for s in seasons])
        for season in seasons:
            players = season['players']
            self.assertEqual(len(players), season['qualified_total'])
            self.assertEqual(len(players), len({p['id'] for p in players}))
            self.assertEqual(season['count'], sum(Decimal(p['avg']) >= Decimal('.300') for p in players))
            self.assertEqual(season['provisional'], season['year'] == 2026)
        for year, name in [(2025, 'Yandy Díaz'), (2026, 'TJ Rumfield')]:
            player = next(p for s in seasons if s['year'] == year for p in s['players'] if p['name'] == name)
            self.assertEqual(player['avg'], '.300')

    def test_tappable_rosters_match_counts_and_sort_by_displayed_average(self):
        seasons = json.loads((ROOT / 'data/mlb300-hitters.json').read_text())['seasons']
        module = (ROOT / 'ios/Hub Ball/Hub Ball/MLB300HitterPlayers.swift').read_text()
        for label, year in [('peak', 1999), ('latest', 2026)]:
            season = next(s for s in seasons if s['year'] == year)
            expected = sorted(
                (p for p in season['players'] if Decimal(p['avg']) >= Decimal('.300')),
                key=lambda p: (-Decimal(p['avg']), p['name']),
            )
            block = re.search(rf'static let {label}: \[Player\] = \[(.*?)\n    \]', module, re.S)
            self.assertIsNotNone(block)
            actual = [
                (int(player_id), json.loads(name), team, average)
                for player_id, name, team, average in re.findall(
                    r'\.init\(id: (\d+), name: ("(?:\\.|[^"\\])*"), team: "([A-Z]{3})", average: "(\.\d{3})"\)',
                    block.group(1),
                )
            ]
            self.assertEqual([(id, name, avg) for id, name, _, avg in actual],
                             [(p['id'], p['name'], p['avg']) for p in expected])
            self.assertEqual(len(actual), season['count'])
            teams_by_name = {name: team for _, name, team, _ in actual}
            self.assertEqual(teams_by_name['Larry Walker' if year == 1999 else 'Yordan Alvarez'],
                             'COL' if year == 1999 else 'HOU')
            self.assertEqual(teams_by_name['Fred McGriff' if year == 1999 else 'Chandler Simpson'],
                             'TBD' if year == 1999 else 'TBR')


if __name__ == '__main__':
    unittest.main()
