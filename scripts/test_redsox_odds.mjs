import assert from 'node:assert/strict';
import { normalizeDraftKings } from '../netlify/functions/redsox-odds.mjs';

const base = {
  id: 42,
  date: '2026-09-05T23:05:00Z',
  home: 'Baltimore Orioles',
  away: 'Boston Red Sox',
  bookmakers: {
    DraftKings: [
      { name: 'ML', updatedAt: '2026-09-05T15:00:00Z', odds: [{ home: '1.80', away: '2.10' }] },
      { name: 'Spread', odds: [{ hdp: -1.5, home: '2.30', away: '1.65' }] },
    ],
  },
};

assert.deepEqual(normalizeDraftKings(base), {
  eventId: '42',
  gameDate: base.date,
  homeTeam: base.home,
  awayTeam: base.away,
  sportsbook: 'DraftKings',
  moneyline: 110,
  runLine: 1.5,
  runLinePrice: -154,
  updatedAt: '2026-09-05T15:00:00Z',
});

assert.equal(normalizeDraftKings({ ...base, home: 'New York Yankees', away: 'Baltimore Orioles' }), null);
assert.equal(normalizeDraftKings({ ...base, bookmakers: {} }), null);
console.log('redsox odds normalization tests passed');
