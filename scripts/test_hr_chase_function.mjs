import assert from 'node:assert/strict';
import { loadJudgeChase } from '../netlify/functions/hr-chase.mjs';

const requested = [];
const mockFetch = async url => {
  requested.push(String(url));
  if (String(url).includes('/people/')) {
    return Response.json({ stats: [{ splits: [{ stat: { homeRuns: 17, atBats: 224 } }] }] });
  }
  return Response.json({ seasons: [{ regularSeasonEndDate: '2026-09-27' }] });
};

const payload = await loadJudgeChase(mockFetch, new Date('2026-09-12T12:00:00Z'));
assert.deepEqual(payload, {
  year: 2026,
  age: 34,
  homeRuns: 17,
  atBats: 224,
  regularSeasonEndDate: '2026-09-27',
  source: 'MLB Stats API via Hub Ball',
});
assert.equal(requested.length, 2);
assert(requested.some(url => url.includes('/people/592450/stats')));
assert(requested.some(url => url.includes('/seasons/2026')));
console.log('Home Run Chase backend tests passed');
