import assert from 'node:assert/strict';
import handler, { TEAMS } from '../netlify/functions/mlb-data.mjs';

const originalFetch = globalThis.fetch;
const requests = [];
globalThis.fetch = async url => {
  requests.push(String(url));
  if (String(url).includes('/standings')) {
    const nationalLeague = new URL(String(url)).searchParams.get('leagueId') === '104';
    const division = (id, name, abbreviation, rank) => ({
      standingsType: 'regularSeason',
      division: { id },
      lastUpdated: '2026-09-10T02:15:01.914Z',
      teamRecords: [{
        team: {
          id: id === 201 ? 111 : id === 204 ? 121 : id,
          name, shortName: name, abbreviation,
        },
        divisionRank: String(rank), wins: 80, losses: 67,
        winningPercentage: '.544', gamesBack: '8.0', wildCardGamesBack: '+6.0',
        streak: { streakCode: 'L2' },
        records: { splitRecords: [{ type: 'lastTen', wins: 6, losses: 4 }] },
      }],
    });
    const divisions = nationalLeague
      ? [
        division(204, 'New York Mets', 'NYM', 2),
        division(205, 'Chicago Cubs', 'CHC', 1),
        division(203, 'Los Angeles Dodgers', 'LAD', 1),
      ]
      : [
        division(201, 'Boston Red Sox', 'BOS', 3),
        division(202, 'Cleveland Guardians', 'CLE', 1),
        division(200, 'Seattle Mariners', 'SEA', 1),
      ];
    const favorite = nationalLeague
      ? { id: 121, name: 'New York Mets', shortName: 'NY Mets', abbreviation: 'NYM' }
      : { id: 111, name: 'Boston Red Sox', shortName: 'Boston', abbreviation: 'BOS' };
    return new Response(JSON.stringify({ records: [
      ...divisions,
      {
        standingsType: 'wildCard',
        lastUpdated: '2026-09-10T02:15:01.914Z',
        teamRecords: [{
          team: favorite,
          wildCardRank: '1', wins: 80, losses: 67, winningPercentage: '.544',
          gamesBack: '8.0', wildCardGamesBack: '+6.0', streak: { streakCode: 'L2' },
          records: { splitRecords: [{ type: 'lastTen', wins: 6, losses: 4 }] },
        }],
      },
    ] }));
  }
  if (String(url).includes('/schedule')) {
    return new Response(JSON.stringify({ dates: [] }));
  }
  if (String(url).includes('/content')) {
    return new Response(JSON.stringify({
      editorial: { recap: { mlb: { headline: 'Boston wins', slug: 'boston-wins' } } },
    }));
  }
  return new Response(JSON.stringify({
    gamePk: 123,
    gameData: { teams: { away: { id: 111 }, home: { id: 147 } } },
  }));
};

let response = await handler(new Request(
  'https://example.test/api/mlb/schedule?team=red-sox&startDate=2026-09-01&endDate=2026-09-06',
));
assert.equal(response.status, 200);
assert.match(requests[0], /teamId=111/);
assert.match(requests[0], /startDate=2026-09-01/);

response = await handler(new Request(
  'https://example.test/api/mlb/schedule?team=redsox&startDate=2026-09-01&endDate=2026-09-06',
));
assert.equal(response.status, 200);
assert.match(requests[1], /teamId=111/);

response = await handler(new Request(
  'https://example.test/api/mlb/schedule?team=mets&startDate=2026-09-01&endDate=2026-09-06',
));
assert.equal(response.status, 200);
assert.match(requests[2], /teamId=121/);

response = await handler(new Request(
  'https://example.test/api/mlb/schedule?team=rays&startDate=2026-09-01&endDate=2026-09-06',
));
assert.equal(response.status, 200);
assert.match(requests[3], /teamId=139/);

assert.equal(TEAMS.size, 31);
assert.equal(TEAMS.get('orioles'), 110);
assert.equal(TEAMS.get('dodgers'), 119);
assert.equal(TEAMS.get('brewers'), 158);

response = await handler(new Request('https://example.test/api/mlb/game?team=red-sox&gamePk=123'));
assert.equal(response.status, 200);
assert.match(requests[4], /game\/123\/feed\/live/);
assert.match(requests[5], /game\/123\/content/);
assert.deepEqual((await response.json()).officialRecap, {
  headline: 'Boston wins',
  url: 'https://www.mlb.com/news/boston-wins',
});

response = await handler(new Request('https://example.test/api/mlb/standings?team=redsox'));
assert.equal(response.status, 200);
assert.match(requests[6], /leagueId=103/);
assert.equal(response.headers.get('X-Data-Freshness'), 'live');
assert.equal(response.headers.get('Netlify-CDN-Cache-Control'),
  'public, durable, max-age=30, stale-while-revalidate=30');
const standings = await response.json();
assert.equal(standings.freshness, 'live');
assert.equal(standings.source_updated_at, '2026-09-10T02:15:01.914Z');
assert.equal(standings.divisions[0].name, 'AL East');
assert.equal(standings.divisions[0].teams[0].losses, 67);
assert.equal(standings.divisions[0].teams[0].is_favorite, true);
assert.equal(standings.wild_card[0].streak, 'L2');

response = await handler(new Request('https://example.test/api/mlb/standings?team=mets'));
assert.equal(response.status, 200);
assert.match(requests[7], /leagueId=104/);
const nationalStandings = await response.json();
assert.equal(nationalStandings.league, 'National League');
assert.equal(nationalStandings.divisions[0].name, 'NL East');
assert.equal(nationalStandings.divisions[0].teams[0].is_favorite, true);

response = await handler(new Request('https://example.test/api/mlb/game?team=red-sox&gamePk=nope'));
assert.equal(response.status, 404);

response = await handler(new Request('https://example.test/api/mlb/schedule?team=unknown'));
assert.equal(response.status, 404);

globalThis.fetch = async url => {
  if (String(url).startsWith('https://statsapi.mlb.com/')) {
    return new Response('{"error":"unavailable"}', { status: 502 });
  }
  assert.equal(String(url),
    'https://raw.githubusercontent.com/sfrancoe/red-sox/main/data/standings.json');
  return new Response(JSON.stringify({
    generated_at: '2026-09-10T00:15:03Z', source: 'MLB Stats API', season: 2026,
    league: 'American League', divisions: [{ id: 201, name: 'AL East', teams: [] }],
    wild_card: [],
  }));
};
response = await handler(new Request('https://example.test/api/mlb/standings?team=redsox'));
assert.equal(response.status, 200);
assert.equal(response.headers.get('X-Data-Freshness'), 'stale');
assert.equal((await response.json()).freshness, 'stale');

globalThis.fetch = originalFetch;
console.log('MLB live-data gateway tests passed');
