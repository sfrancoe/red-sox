#!/usr/bin/env python3
"""Build an original chart story from verified MLB regular-season schedule snapshots."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import urllib.request
from story_content import encoded, require, validate_payload

TEAM = 145
YEARS = [2024, 2025, 2026]
EXPECTED = {2024: 41, 2025: 60, 2026: 84}

def source_url(year):
    return f'https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId={TEAM}&season={year}&gameType=R'

def season_games(schedule):
    games = {}
    for date in schedule['dates']:
        for game in date['games']:
            if game.get('gameType') != 'R' or game['status'].get('abstractGameState') != 'Final' or game['status'].get('codedGameState') not in ['F', 'O']:
                continue
            require(TEAM in [game['teams'][s]['team']['id'] for s in ['home', 'away']], 'Wrong team')
            key = game['gamePk']
            if key in games:
                a, b = games[key], game
                require(a['teams'] == b['teams'] and a['officialDate'] == b['officialDate'], 'Conflicting final duplicate; reconcile source')
            games[key] = game
    return sorted(games.values(), key=lambda g: (g['officialDate'], g.get('gameNumber', 1), g['gameDate'], g['gamePk']))

def derive(schedule, year):
    games = season_games(schedule)
    require(len(games) == 162, 'Expected 162 unique final regular-season games')
    wins = 0; results = []; points = [{'x': 0, 'y': 0}]
    for number, game in enumerate(games, 1):
        side = 'home' if game['teams']['home']['team']['id'] == TEAM else 'away'
        winner = game['teams'][side].get('isWinner')
        require(type(winner) is bool, 'Missing settled winner')
        wins += int(winner)
        points.append({'x': number, 'y': wins})
        record = game['teams'][side].get('leagueRecord', {})
        # Final schedule records are checked, never used to invent or smooth results.
        require(record.get('wins') == wins and record.get('losses') == number - wins, 'Running league record disagrees with ordered final results')
        results.append({'game': number, 'gamePk': game['gamePk'], 'date': game['officialDate'], 'won': winner, 'wins': wins, 'losses': number - wins})
    require(wins == EXPECTED[year], 'Season total changed; review editorial premise')
    return points, results

def build(proof):
    require(proof['teamID'] == TEAM, 'Wrong team source')
    rows = proof['seasons']; require([r['year'] for r in rows] == YEARS, 'Missing seasons')
    for row in rows:
        results = row['games']; require(len(results) == 162 and len({g['gamePk'] for g in results}) == 162, 'Incomplete source')
        wins = 0
        for number, game in enumerate(results, 1):
            require(type(game['won']) is bool and game['game'] == number, 'Invalid ordered result')
            wins += game['won']; require(game['wins'] == wins and game['losses'] == number - wins, 'Invalid cumulative record')
        require(wins == EXPECTED[row['year']], 'Wrong total')
    current = rows[2]['games']
    for number, wins, date in [(78, 41, '2026-06-23'), (80, 42, '2026-06-26'), (117, 61, '2026-08-09')]:
        g = current[number - 1]; require(g['wins'] == wins and g['date'] == date and g['won'], 'Milestone changed')
        require(current[number - 2]['wins'] == wins - 1, 'Milestone not first crossing')
    story = {
        'schemaVersion': 1, 'id': 'whole-season-by-june', 'renderer': 'chart-trajectory', 'rendererVersion': 1,
        'title': 'A Whole Season of Wins. By June.', 'kicker': 'Chicago White Sox · 2024–2026',
        'intro': 'In 2024, Chicago needed 162 games to win 41. In 2026, it got there in 78. Watch three seasons climb the same scale.',
        'chart': {
            'kind': 'step', 'durationSeconds': 8,
            'xAxis': {'label': 'Games played', 'minimum': 0, 'maximum': 162, 'ticks': [0, 40, 80, 120, 162]},
            'yAxis': {'label': 'Cumulative wins', 'minimum': 0, 'maximum': 90, 'ticks': [0, 30, 60, 90]},
            'series': [{'id': f'season-{r["year"]}', 'label': str(r['year']), 'color': color,
                        'points': [{'x': 0, 'y': 0}] + [{'x': g['game'], 'y': g['wins']} for g in r['games']]} for r, color in zip(rows, ['navy', 'gold', 'coral'])],
            'emphasis': [{'id': 'june-crossing', 'x': 78, 'y': 41, 'holdSeconds': 0.9,
                          'title': 'A whole season. In 78 games.',
                          'detail': 'June 23, 2026 · 41–37. Chicago matched all 41 wins from 2024 before halfway through the season.'}],
        },
        'conclusion': 'On June 23, Chicago had matched a whole season of wins. Win 42 came on June 26. By August 9, Chicago had passed 2025’s 60 wins, too. The 2026 finish: 84–78—43 more wins than two years earlier.',
        'methodology': [
            'Every point is one completed regular-season game from the official MLB schedule. Chicago is team 145. We exclude spring training, postseason, postponed and unresolved games, and deduplicate final entries by gamePk.',
            'Games are ordered by official game date, then doubleheader game number, start time and gamePk. We count the winner flag and reconcile every cumulative win–loss record against the schedule’s leagueRecord. Each season has 162 distinct final games.',
            'All three lines use the same games-played axis (0–162) and wins axis (0–90). The steps show actual wins, without smoothing. A loss keeps the line level. Matching game numbers compares progress through a season, not the same calendar dates.',
            'Verified finishes: 2024, 41–121; 2025, 60–102; 2026, 84–78. The 2026 milestones are win 41 at Game 78 on June 23, win 42 at Game 80 on June 26, and win 61 at Game 117 on August 9.',
            'The animation lasts eight seconds, including a brief hold at Game 78. Playback timing is editorial emphasis; it does not represent time between real games. This is original text and an original native chart of factual game results. No MLB photographs, video, logos or music are included.',
        ],
        'sources': [{'id': f'mlb-{y}', 'title': f'MLB official White Sox regular-season schedule · {y}', 'url': source_url(y), 'retrievedAt': proof['retrievedAt']} for y in YEARS],
    }
    return validate_payload(story)

if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true', help='Read official schedules; never publishes')
    parser.add_argument('--snapshots', type=Path, default=root / 'dist/chart-story/sources')
    parser.add_argument('--source', type=Path, default=root / 'docs/stories/white-sox-story-source.json')
    parser.add_argument('--output', type=Path, default=root / 'docs/stories/white-sox-story.json')
    args = parser.parse_args()
    if args.refresh:
        args.snapshots.mkdir(parents=True, exist_ok=True)
        for year in YEARS:
            data = urllib.request.urlopen(source_url(year), timeout=45).read()
            (args.snapshots / f'{year}.json').write_bytes(data)
    if args.snapshots.exists():
        rows = []
        for year in YEARS:
            data = (args.snapshots / f'{year}.json').read_bytes(); points, games = derive(json.loads(data), year)
            rows.append({'year': year, 'sourceURL': source_url(year), 'rawSHA256': hashlib.sha256(data).hexdigest(), 'games': games})
        proof = {'teamID': TEAM, 'retrievedAt': datetime.fromtimestamp(max((args.snapshots / f'{y}.json').stat().st_mtime for y in YEARS), timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'), 'seasons': rows}
        args.source.write_bytes(encoded(proof))
    else: proof = json.loads(args.source.read_text())
    args.output.write_bytes(encoded(build(proof)))
    print(f'Verified 486 games; authored {args.output}. Nothing published.')
