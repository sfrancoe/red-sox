#!/usr/bin/env python3
"""Generate bundled private previews. Never writes data/, a public catalog, or hosting files."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from story_content import encoded, digest, require, validate_catalog, validate_payload

X = [i / 2 for i in range(19)]
CLEVELAND = [0,0,0,0,0,0,0,0,0,3,3,9,9,9,9,9,9,9,9]
CHICAGO = [0,0,0,0,0,0,2,2,2,2,4,4,4,4,4,4,4,4,5]
MARGINS = [
    [0,0,0,-2,-2,-2,0,0,0,0,0,0,0,0,1,1,1,1,1],
    [0,-1,-1,-1,-1,-1,-1,-1,-1,-2,-1,-1,-1,-2,-1,-1,-1,-1,1],
    [0,0,0,0,0,0,-2,-1,-1,0,-1,-1,-2,-1,-1,-1,-1,-1,-1],
    [0,0,0,0,0,1,0,0,0,1,1,2,2,2,2,2,2,2,2],
]
GAME_IDS = [849832,849830,849825,849826,849827]
SAVES = [0,1,0,0,3,41]
IDS = ['preview-oct09-sixth','preview-oct09-brewers','preview-oct09-baker']

def scores(innings):
    """Half-inning endpoint convention: n-.5 after the top; n after the bottom."""
    away = home = 0
    a, h = [0], [0]
    for n, inning in enumerate(innings, 1):
        require(inning['num'] == n, 'Nonconsecutive inning')
        away += inning['away'].get('runs', 0)
        a.append(away); h.append(home)
        home += inning['home'].get('runs', 0)  # Missing runs means unplayed, not an invented zero-run turn.
        a.append(away); h.append(home)
    require(len(a) == 19, 'Expected nine-inning final')
    return a, h

def source_proof(snapshots):
    schedule = json.loads((snapshots/'schedule.json').read_bytes())
    games = {g['gamePk']:g for d in schedule['dates'] for g in d['games']}
    rows=[]
    for game_id in GAME_IDS:
        game=games[game_id]; raw=(snapshots/f'game-{game_id}.json').read_bytes(); line=json.loads(raw)
        require(game['gameType']=='D' and game['status']['abstractGameState']=='Final' and game['officialDate'] <= '2026-10-08', 'Wrong cutoff/type/status')
        a,h=scores(line['innings']); require(a[-1]==line['teams']['away']['runs'] and h[-1]==line['teams']['home']['runs'], 'Final totals disagree')
        rows.append({'gameID':game_id,'date':game['officialDate'],'awayTeamID':game['teams']['away']['team']['id'],'homeTeamID':game['teams']['home']['team']['id'],'innings':line['innings'],'rawSHA256':hashlib.sha256(raw).hexdigest()})
    stats=json.loads((snapshots/'baker.json').read_bytes()); totals=[]
    for year in range(2021,2027):
        splits=[s for group in stats['stats'] for s in group.get('splits',[]) if s['season']==str(year)]
        combined=[s for s in splits if s.get('numTeams',0)>1]
        selected=combined or splits
        require(len(selected)==1, 'Exactly one combined-team or single-team row required')
        totals.append(selected[0]['stat']['saves'])
    alds=json.loads((snapshots/'baker-alds-proof.json').read_bytes())
    require(len(alds['games'])==3 and all(g['saves']==1 and g['date'] <= '2026-10-08' for g in alds['games']), 'Three completed ALDS saves required')
    stamp=datetime.fromtimestamp(max(p.stat().st_mtime for p in snapshots.glob('*.json')),timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    return {'retrievedAt':stamp,'cutoff':'2026-10-08','games':rows,'bakerSaves':totals,'bakerALDS':alds,'bakerRawSHA256':hashlib.sha256((snapshots/'baker.json').read_bytes()).hexdigest()}

def verify(proof):
    require(proof['cutoff']=='2026-10-08', 'Wrong preview cutoff')
    rows=proof['games']; require([r['gameID'] for r in rows]==GAME_IDS,'Wrong games')
    require(rows[0]['awayTeamID']==114 and rows[0]['homeTeamID']==145,'Wrong Cleveland opponent')
    require(scores(rows[0]['innings'])==(CLEVELAND,CHICAGO),'Cleveland/Chicago arrays disagree with official linescore')
    for index,row in enumerate(rows[1:]):
        a,h=scores(row['innings']); require({row['awayTeamID'],row['homeTeamID']}=={158,135},'Wrong NLDS teams')
        margin=[(home-away) if row['homeTeamID']==158 else (away-home) for away,home in zip(a,h)]
        require(margin==MARGINS[index] and max(abs(v) for v in margin)<=2,'Milwaukee margins disagree')
    require(proof['bakerSaves']==SAVES,'Regular-season saves disagree')
    require(len(proof['bakerALDS']['games'])==3 and all(g['saves']==1 for g in proof['bakerALDS']['games']),'ALDS saves disagree')

def build(proof):
    verify(proof)
    stamp=proof['retrievedAt']
    def source(id,title,url):return {'id':id,'title':title,'url':url,'retrievedAt':stamp}
    def row(id,label,color,x,y):return {'id':id,'label':label,'color':color,'points':[{'x':a,'y':b} for a,b in zip(x,y)]}
    def axis(label,minimum,maximum,ticks):return {'label':label,'minimum':minimum,'maximum':maximum,'ticks':ticks}
    rights='Original writing and native graphics of factual statistics. No third-party photos, logos, video, music or article prose are included. Source links support verification; public access is not a commercial reuse license.'
    half='Each point records the score after a completed half-inning: n−0.5 marks the end of the top of inning n, and n marks the end of its bottom half. The x=5.5 point is after the top of the sixth, not halfway through a batting turn. Lines step at these checkpoints without smoothing. Animation timing is editorial, not real elapsed game time.'
    stories=[{
      'id':IDS[0],'title':'The Sixth That Saved October','kicker':'CLEVELAND · ELIMINATION GAME · OCTOBER 8',
      'intro':'Down 4–3 after five innings, Cleveland needed a way to keep October open. Six runs in the top of the sixth changed the score, and the series. Watch both teams after each half-inning.',
      'chart':{'kind':'step','durationSeconds':7,'xAxis':axis('Inning',0,9,[0,1,3,5,6,7,9]),'yAxis':axis('Runs',0,10,[0,2,4,6,8,10]),'series':[row('cleveland','Cleveland','coral',X,CLEVELAND),row('chicago','Chicago White Sox','navy',X,CHICAGO)],'emphasis':[{'id':'six-run-sixth','x':5.5,'y':9,'holdSeconds':0.7,'title':'Six in the sixth. October stays open.','detail':'After the top of the sixth: Cleveland 9, Chicago 4. Six runs turned a one-run deficit into a five-run lead.'}]},
      'conclusion':'Cleveland finished the job, 9–5. The elimination game became an invitation to Game 5. Sometimes the whole shape of a postseason changes in one half-inning.',
      'methodology':[half,'Official MLB linescore for ALDS Game 4, game 849832, completed October 8, 2026. Cleveland was the visiting team; Chicago was home. The seven-second playback includes a 0.7-second hold after Cleveland’s sixth-inning rally.',rights],
      'sources':[source('mlb-linescore','MLB official ALDS Game 4 linescore','https://statsapi.mlb.com/api/v1/game/849832/linescore'),source('mlb-report','MLB · Cleveland forces Game 5','https://www.mlb.com/news/guardians-win-alds-game-4-2026')]
    },{
      'id':IDS[1],'title':'Four Games. Never Breathing Room.','kicker':'MILWAUKEE · FOUR-GAME NLDS',
      'intro':'Four games, and the score never gave either dugout room to relax. Follow Milwaukee’s lead or deficit one game at a time. Every line uses the same scale; every earlier game stays on screen.',
      'chart':{'kind':'step','durationSeconds':8,'sequence':{'secondsPerSeries':2},'xAxis':axis('Inning',0,9,[0,1,3,5,7,9]),'yAxis':axis('Milwaukee run margin',-3,3,[-2,0,2]),'series':[row(f'game-{i+1}',f'Game {i+1}',color,X,MARGINS[i]) for i,color in enumerate(['navy','gold','teal','coral'])],'emphasis':[]},
      'conclusion':'No lead grew beyond two runs. Milwaukee won Games 1, 2 and 4, and took the series 3–1. Four games of having just enough—and almost no cushion.',
      'methodology':[half,'Margin means Milwaukee runs minus San Diego runs. Positive is a Brewers lead; negative is a deficit; zero is tied. All four games use a −3 to +3 scale. The final margins are +1, +1, −1 and +2. Each game draws for two seconds, in series order, and completed lines remain visible. No shaded tolerance band or decorative arrows are used.','Unplayed last home half-innings in Games 1 and 3 carry the settled final margin forward to x=9. This is an axis-alignment convention, not additional play. Runs within each played half-inning move the margin monotonically between its two endpoints; all endpoints lie between −2 and +2, confirming neither team ever led by more than two.',rights],
      'sources':[source(f'mlb-game-{i+1}',f'MLB official NLDS Game {i+1} linescore',f'https://statsapi.mlb.com/api/v1/game/{g}/linescore') for i,g in enumerate(GAME_IDS[1:])]+[source('mlb-report','MLB · Brewers–Padres close NLDS','https://www.mlb.com/news/brewers-padres-complete-historically-close-nlds-matchup')]
    },{
      'id':IDS[2],'title':'Four Saves. Then Forty-One.','kicker':'BRYAN BAKER · REGULAR-SEASON SAVES',
      'intro':'Five seasons, four saves combined. Then came 2026: forty-one in a single year. Watch the annual bars, from his 2021 debut through his first full season as Tampa Bay’s closer.',
      'chart':{'kind':'bar','durationSeconds':6,'xAxis':axis('Season',2021,2026,list(range(2021,2027))),'yAxis':axis('Regular-season saves',0,45,[0,10,20,30,40,45]),'series':[row('bryan-baker','Bryan Baker','coral',list(range(2021,2027)),SAVES)],'emphasis':[]},
      'conclusion':'Then he closed all three ALDS wins.',
      'methodology':['The six bars show MLB regular-season saves only, by year: 2021–2026 = 0, 1, 0, 0, 3, 41. The baseline is zero and the vertical scale is 0–45; every zero remains a labeled year. The 2026 bar is 41, verified in the current official StatsAPI rather than stale indexed player snippets.','For 2025, the combined-team row is three saves. We select that total once instead of adding it to the separate Baltimore and Tampa Bay rows. The first five seasons total four saves.','The closing caption is a separate postseason fact. Official ALDS box scores credit Baker with one save in each of Tampa Bay’s three wins (games 849835, 849839 and 849838). Those three saves are not added to the regular-season 2026 bar. The six-second chart holds its ending; Reduced Motion shows all bars immediately.',rights],
      'sources':[source('mlb-yearly','MLB official Bryan Baker yearly pitching statistics','https://statsapi.mlb.com/api/v1/people/641329/stats?stats=yearByYear&group=pitching'),source('savant','Baseball Savant · Bryan Baker','https://baseballsavant.mlb.com/savant-player/bryan-baker-641329'),source('mlb-report','MLB · Tampa Bay wins the ALDS','https://www.mlb.com/news/rays-win-alds-2026')]+[source(f'mlb-save-{i+1}',f'MLB official ALDS save · game {g["game"]}',f'https://statsapi.mlb.com/api/v1/game/{g["game"]}/boxscore') for i,g in enumerate(proof['bakerALDS']['games'])]
    }]
    for story in stories:
        story.update({'schemaVersion':1,'renderer':'chart-trajectory','rendererVersion':1});validate_payload(story)
    return stories

def write(stories,output,stamp):
    summaries=['Six runs in one half-inning kept Cleveland alive. Two synchronized score lines · 7 seconds.','Four games without a lead bigger than two. Four sequential margin lines · 8 seconds.','A career went from four saves to forty-one. Six annual bars · 6 seconds.']
    entries=[]
    for index,story in enumerate(stories):
        raw=encoded(story);(output/f'story-private-{story["id"]}.json').write_bytes(raw)
        entries.append({'id':story['id'],'revision':digest(raw),'title':story['title'],'summary':summaries[index],'fallback':story['conclusion'],'publishedAt':stamp,'teamIDs':[[114,145],[158,135],[139]][index],'renderer':'chart-trajectory','rendererVersion':1,'minimumRendererVersion':3 if story['chart'].get('sequence') else 2})
    catalog={'schemaVersion':1,'revision':'private-october9-2026','publishedAt':stamp,'stories':entries};validate_catalog(catalog)
    (output/'story-private-catalog.json').write_bytes(encoded(catalog))

if __name__=='__main__':
    root=Path(__file__).resolve().parents[1];p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--snapshots',type=Path,default=root/'dist/private-october9/sources');p.add_argument('--proof',type=Path,default=root/'docs/stories/private-october9-source.json');p.add_argument('--output',type=Path,default=root/'ios/Hub Ball/Hub Ball');args=p.parse_args()
    if args.snapshots.exists():proof=source_proof(args.snapshots);args.proof.write_bytes(encoded(proof))
    else:proof=json.loads(args.proof.read_bytes())
    write(build(proof),args.output,proof['retrievedAt'])
    print('Validated and bundled three private candidates. Shared production catalog and data/ untouched.')
