// Zero-dependency tests against the built site over HTTP.
// bash scripts/build_site.sh; python3 -m http.server 8765 --directory _site
// node scripts/test_home_game.mjs
import assert from 'node:assert/strict';

const origin = process.env.TEST_SITE_URL || 'http://localhost:8765';
const response = await fetch(`${origin}/src/home-game.js`);
assert.equal(response.status, 200);
const source = await response.text();
const gameModule = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

const scheduled = {
  gamePk: 10, gameDate: '2026-09-05T23:05:00Z', status: { abstractGameState: 'Preview' },
};
const live = {
  gamePk: 11, gameDate: '2026-09-05T23:05:00Z', venue: { name: 'Fenway Park' },
  status: { abstractGameState: 'Live', detailedState: 'In Progress' },
  teams: {
    away: { team: { id: 111, abbreviation: 'BOS' }, leagueRecord: { wins: 77, losses: 65 }, score: 5 },
    home: { team: { id: 147, abbreviation: 'NYY' }, leagueRecord: { wins: 75, losses: 67 }, score: 2 },
  },
  linescore: { inningState: 'Bottom', currentInningOrdinal: '7th' },
};
const final = { ...live, status: { abstractGameState: 'Final', detailedState: 'Final' } };
assert.equal(gameModule.easternDate(new Date('2026-09-06T02:00:00Z')), '2026-09-05');
assert.equal(gameModule.selectHomeGame({ dates: [{ games: [scheduled, live] }] }).gamePk, 11);
assert.equal(gameModule.selectHomeGame({ dates: [{ games: [scheduled, final] }] }), null);
assert.equal(gameModule.selectHomeGame({ dates: [{ games: [scheduled, final] }] }, 11).gamePk, 11);
const normalized = gameModule.normalizeHomeGame(live);
assert.equal(normalized.status, 'Bottom 7th');
assert.equal(normalized.away.record, '77-65');
assert.equal(normalized.home.runs, 2);
assert.equal(normalized.is_live, true);
assert.match(normalized.gameday_url, /11$/);

let requestedURL;
const fetched = await gameModule.fetchHomeGame(null, new Date('2026-09-06T02:00:00Z'), async url => {
  requestedURL = url;
  return { ok: true, json: async () => ({ dates: [{ games: [live] }] }) };
});
assert.equal(fetched.game_pk, 11);
assert.match(requestedURL, /date=2026-09-05/);
assert.match(requestedURL, /hydrate=linescore,team/);
console.log('Home live-game selection, normalization, and Eastern-date tests passed.');
