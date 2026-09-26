import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { getPostseasonResponse, normalizePostseason, TOURNAMENT_FORMATS } from '../netlify/functions/postseason.mjs';

const fixture = async year => JSON.parse(await readFile(new URL(`./fixtures/postseason-${year}.json`, import.meta.url)));
const completed = normalizePostseason(await fixture(2025), '2025', '2026-09-26T00:00:00Z');
assert.equal(completed.games.length, 47);
assert.equal(completed.series.length, 11);
assert.deepEqual(TOURNAMENT_FORMATS[2026], { F: 2, D: 3, L: 4, W: 4 });
assert.ok(completed.series.every(series => series.requiredWins === ({
  'wild-card': 2, 'division-series': 3, 'league-championship': 4, 'world-series': 4,
})[series.round]));
assert.equal(completed.phase, 'complete');
const wcA = completed.series.find(series => series.round === 'wild-card' && series.league === 'AL' && series.bracketSlot === 'A');
const alDsB = completed.series.find(series => series.round === 'division-series' && series.league === 'AL' && series.bracketSlot === 'B');
assert.deepEqual(wcA.nextSlots, [alDsB.id]);
assert.ok(completed.series.filter(series => series.round === 'league-championship')
  .every(series => series.nextSlots?.[0] === completed.series.find(item => item.round === 'world-series')?.id));
assert.equal(completed.series.find(series => series.round === 'world-series').nextSlots, null);
assert.ok(completed.games.every(game => !game.timeTBD));
assert.ok(completed.series.some(series => series.round === 'world-series'));
assert.ok(completed.series.every(series => series.participants.length >= 2));
assert.ok(completed.series.some(series => series.winnerTeamId !== null));
assert.ok(completed.games.every(game => game.winnerTeamId === null || game.abstractState === 'Final'));
assert.ok(completed.games.every(game => game.liveInning !== null));
assert.ok(completed.games.some(game => game.broadcasts.length > 0));

const duplicateSource = await fixture(2025);
const firstGame = duplicateSource.dates[0].games[0];
duplicateSource.dates[0].games.push(structuredClone(firstGame));
const deduplicated = normalizePostseason(duplicateSource, '2025');
assert.equal(deduplicated.games.length, 47);
assert.equal(deduplicated.series.find(item => item.id === deduplicated.games[0].seriesId).gameIds.length, 3);

const conflictSource = await fixture(2025);
const conflictGame = structuredClone(conflictSource.dates[0].games[0]);
conflictGame.teams.away.score += 1;
conflictSource.dates[0].games.push(conflictGame);
const conflict = normalizePostseason(conflictSource, '2025');
assert.equal(conflict.series.find(item => item.id === conflict.games[0].seriesId).state, 'unknown');

const conditionalSource = await fixture(2026);
const conditionalGame = structuredClone(conditionalSource.dates[0].games[0]);
conditionalGame.ifNecessary = 'Y';
conditionalGame.status = { abstractGameState: 'Final', codedGameState: 'C', detailedState: 'Cancelled' };
conditionalGame.teams.away.score = 0;
conditionalGame.teams.home.score = 0;
conditionalGame.teams.away.isWinner = false;
conditionalGame.teams.home.isWinner = false;
conditionalSource.dates[0].games[0] = conditionalGame;
const conditional = normalizePostseason(conditionalSource, '2026');
assert.equal(conditional.games[0].conditional, true);
assert.equal(conditional.games[0].winnerTeamId, null);
const canceledSeries = conditional.series.find(item => item.id === conditional.games[0].seriesId);
assert.equal(canceledSeries.completedGameCount, 0);
assert.equal(canceledSeries.state, 'scheduled');

const upcoming = normalizePostseason(await fixture(2026), '2026', '2026-09-26T00:00:00Z');
assert.equal(upcoming.games.length, 53);
assert.equal(upcoming.phase, 'field-setting');
assert.ok(upcoming.games.some(game => game.timeTBD));
assert.ok(upcoming.teamsAndSlots.some(team => team.unresolved));
assert.ok(upcoming.teamsAndSlots.filter(team => !team.unresolved)
  .every(team => team.qualification === 'unknown'));
assert.ok(upcoming.games.filter(game => game.timeTBD).every(game => game.gameDate));

let fetchedURL;
const response = await getPostseasonResponse(
  new Request('https://example.test/api/postseason?season=2026'),
  async url => {
    fetchedURL = String(url);
    return new Response(JSON.stringify(await fixture(2026)));
  },
);
assert.equal(response.status, 200);
assert.match(fetchedURL, /gameTypes=F%2CD%2CL%2CW/);
assert.match(fetchedURL, /hydrate=linescore%2Cbroadcasts/);
assert.match(response.headers.get('Cache-Control'), /max-age=300/);
assert.match(response.headers.get('Netlify-CDN-Cache-Control'), /durable/);
assert.equal((await response.json()).schemaVersion, 1);

const rejected = await getPostseasonResponse(
  new Request('https://example.test/api/postseason?season=2024'),
  async () => { throw new Error('must not fetch'); },
);
assert.equal(rejected.status, 400);

console.log('postseason normalization and gateway tests passed');
