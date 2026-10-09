import copy
import json
from pathlib import Path
import tempfile
import unittest
import build_private_october9 as preview
from story_content import encoded, digest

ROOT=Path(__file__).resolve().parents[1]

class PrivatePreviewTests(unittest.TestCase):
    def setUp(self):
        self.proof=json.loads((ROOT/'docs/stories/private-october9-source.json').read_bytes())
    def test_generated_resources_are_exact_and_isolated(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory);preview.write(preview.build(self.proof),output,self.proof['retrievedAt'])
            for p in output.iterdir():self.assertEqual(p.read_bytes(),(ROOT/'ios/Hub Ball/Hub Ball'/p.name).read_bytes())
        published=json.loads((ROOT/'data/stories/catalog-v1.json').read_bytes())
        self.assertFalse(set(preview.IDS)&{s['id'] for s in published['stories']})
        self.assertFalse(any((ROOT/'data/stories'/id).exists() for id in preview.IDS))
    def test_scores_use_completed_half_innings_and_carry_only_unplayed_final_home_halves(self):
        self.assertEqual(preview.scores(self.proof['games'][0]['innings']),(preview.CLEVELAND,preview.CHICAGO))
        self.assertEqual(preview.CLEVELAND[10:13],[3,9,9])
        self.assertEqual([r['gameID'] for r in self.proof['games'][1:] if 'runs' not in r['innings'][-1]['home']],[849830,849826])
        for row in self.proof['games']:
            for inning in row['innings']:
                self.assertIn('runs',inning['away'])
                if 'runs' not in inning['home']:self.assertEqual(inning['num'],9)
    def test_numerical_tampering_is_rejected(self):
        bad=copy.deepcopy(self.proof);bad['games'][0]['innings'][5]['away']['runs']=5
        with self.assertRaises(ValueError):preview.build(bad)
        bad=copy.deepcopy(self.proof);bad['bakerSaves'][4]=6
        with self.assertRaises(ValueError):preview.build(bad)
    def test_bars_exclude_postseason_and_both_scales_are_fixed(self):
        a,b,c=preview.build(self.proof)
        self.assertEqual(a['chart']['yAxis']['maximum'],10)
        self.assertEqual(b['chart']['yAxis']['ticks'],[-2,0,2]);self.assertEqual(b['chart']['durationSeconds'],8)
        self.assertEqual(c['chart']['series'][0]['points'][-1]['y'],41)
        self.assertEqual(sum(self.proof['bakerSaves'][:5]),4)
        self.assertEqual(sum(g['saves'] for g in self.proof['bakerALDS']['games']),3)
        self.assertEqual(c['conclusion'],'Then he closed all three ALDS wins.')

if __name__=='__main__':unittest.main()
