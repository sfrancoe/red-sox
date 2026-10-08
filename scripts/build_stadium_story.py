#!/usr/bin/env python3
"""Author the verified two-ball story from a compact MLB source snapshot."""
import argparse
import json
from pathlib import Path
from story_content import encoded, require, validate_payload


def build(source):
    require(source['gameID'] == 849838 and source['officialDate'] == '2026-10-07', 'Wrong source game')
    a, b = source['plays']
    require((a['distance'], a['event'], a['inning']) == (356, 'Flyout', 2), 'Earlier at-bat changed: review story')
    require((b['distance'], b['event'], b['inning']) == (340, 'Home Run', 4), 'Later at-bat changed: review story')
    require(source['model']['earlierHomeRunParks'] == 6 and source['model']['laterHomeRunParks'] == 1 and source['model']['laterOnlyPark'] == 'Yankee Stadium', 'Park report changed: review story')
    require(len(source['teams']) == 30 and len({t['id'] for t in source['teams']}) == 30, 'Incomplete park roster')
    require(sum(t['venue'] == 'Yankee Stadium' for t in source['teams']) == 1, 'Missing unique actual venue')
    parks = []
    for team in sorted(source['teams'], key=lambda t: (t['venue'] != 'Yankee Stadium', t['abbreviation'])):
        yes = team['venue'] == 'Yankee Stadium'
        parks.append({'id': str(team['id']), 'label': team['abbreviation'], 'name': team['venue'], 'result': 'yes' if yes else 'no',
                      'detail': 'MLB reports this as the only park where the 340-foot ball was modeled as a home run. It was also the actual venue.' if yes else 'MLB reports that the 340-foot ball was not modeled as a home run here. This does not predict its actual result in a game played at this park.'})
    story = {
        'schemaVersion': 1, 'id': 'this-stadium', 'renderer': 'guess-reveal', 'rendererVersion': 1,
        'title': 'The home run that needed this stadium', 'kicker': 'Tampa Bay · ALDS Game 3 · October 7, 2026',
        'intro': 'Ryan Vilade. Two swings. Same night in the Bronx. One ball traveled farther. Only one left the yard.',
        'question': 'Which ball became the home run?',
        'choices': [
            {'id': 'ball-a', 'label': 'Ball A', 'value': '356', 'unit': 'feet', 'detail': 'Second inning · left field'},
            {'id': 'ball-b', 'label': 'Ball B', 'value': '340', 'unit': 'feet', 'detail': 'Fourth inning · right field'},
        ],
        'correctChoiceID': 'ball-b', 'answerTitle': 'Sixteen feet shorter. One home run.',
        'answer': 'Ball A was caught. Ball B cleared the right-field wall. The shorter swing put a run on the board. Where a ball goes matters as much as how far it goes.',
        'stats': [
            {'label': 'Ball A', 'value': 'Flyout', 'note': '356 ft · 95.2 mph off the bat'},
            {'label': 'Ball B', 'value': 'Home run', 'note': '340 ft · 97.1 mph off the bat'},
            {'label': 'Ball B · park model', 'value': '1 / 30', 'note': 'Only Yankee Stadium'},
        ],
        'barMaximum': 30,
        'bars': [
            {'label': 'Ball A · 356 ft', 'value': 6, 'unit': 'of 30 parks', 'detail': 'Statcast’s park estimate, as reported by MLB. Actual result: flyout.'},
            {'label': 'Ball B · 340 ft', 'value': 1, 'unit': 'of 30 parks', 'detail': 'Statcast’s park estimate, as reported by MLB. Actual result: home run.'},
        ],
        'passport': {'title': 'One stamp in a 30-park passport',
                     'intro': 'Take Ball B around the league. One park earns a home-run stamp. Tap any park to inspect the reported model result.', 'items': parks},
        'conclusion': 'Same hitter. A longer out and a shorter homer. Distance tells part of the story; the stadium helps write the ending.',
        'methodology': [
            'The two actual outcomes, Statcast-projected distances, exit velocities and launch angles come from MLB’s game feed for Rays at Yankees, October 7, 2026. The earlier ball: 356 ft, 95.2 mph, 31°. The later ball: 340 ft, 97.1 mph, 37°.',
            'The cross-park counts are Statcast modeled estimates reported by MLB: six parks for the earlier flyout and only Yankee Stadium for the later homer. We do not calculate park outcomes from distance alone.',
            'A modeled home run is an estimate about a batted ball and park geometry, not a guarantee of what another game would produce. Conditions, defense and other differences can change an actual result.',
            'The passport covers the 340-foot ball only. MLB’s report identifies its sole modeled home-run park. The report gives six parks for the 356-foot ball without naming all six, so we do not assign that ball individual park outcomes.',
            'Park names come from MLB’s 2026 team/venue registry. The flight motifs and passport stamps are original illustrations, not measured trajectories or stadium diagrams. No video, photographs, logos or music are copied into this story.',
        ],
        'sources': [{'id': key, 'title': title, 'url': source['sourceURLs'][key], 'retrievedAt': source['retrievedAt']} for key, title in [
            ('game', 'MLB game feed · actual at-bats and measurements'), ('article', 'MLB report · Vilade and the park estimates'),
            ('story', 'MLB Game 3 story · one-park home run'), ('teams', 'MLB 2026 teams and venues')]],
    }
    return validate_payload(story)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parents[1]
    parser.add_argument('--source', type=Path, default=root / 'docs/stories/stadium-story-source.json')
    parser.add_argument('--output', type=Path, default=root / 'docs/stories/stadium-story.json')
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(encoded(build(json.loads(args.source.read_text()))))
    print(f'Authored verified story: {args.output}')
