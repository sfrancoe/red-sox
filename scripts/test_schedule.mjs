// Zero-dependency regression tests against the built site over HTTP.
// TEST_SITE_URL=http://localhost:8767 node scripts/test_schedule.mjs
import assert from 'node:assert/strict';
import vm from 'node:vm';

const origin = process.env.TEST_SITE_URL || 'http://localhost:8765';
const response = await fetch(`${origin}/src/schedule.js`);
assert.equal(response.status, 200);
const source = await response.text();

class Element {
  children = [];
  hidden = false;
  appendChild(child) { this.children.push(child); return child; }
  append(...children) { this.children.push(...children); }
  replaceChildren(fragment) { this.children = fragment.children; }
  setAttribute() {}
}
const game = (id, status = 'Scheduled') => ({
  game_pk: id, status, game_date: '2026-08-30T17:00:00Z',
  opponent: 'Yankees', location: 'away', opponent_record: '77-59',
});
const live = states => ({ dates: [{ games: states.map(([id, state]) => ({
  gamePk: id, status: { abstractGameState: state },
})) }] });
let feed = { games: [game(1), game(2)], regular_season_end: '2026-09-27' };
let liveFeed = live([[1, 'Final'], [2, 'Preview']]);
let liveFails = false, savedFails = false, interval, intervalMs;
const elements = new Map();
const get = id => {
  if (!elements.has(id)) elements.set(id, new Element());
  return elements.get(id);
};
const events = {};
const doc = {
  visibilityState: 'visible', getElementById: get,
  createElement: () => new Element(), createDocumentFragment: () => new Element(),
  addEventListener: (event, callback) => { events[event] = callback; },
};
let liveCalls = 0;
await vm.runInNewContext(`(async () => { ${source}\n })()`, {
  document: doc, window: { addEventListener: (event, callback) => { events[event] = callback; } },
  console: { warn() {}, error() {} }, URLSearchParams, AbortController,
  setTimeout, clearTimeout,
  setInterval(callback, ms) { interval = callback; intervalMs = ms; },
  fetch: async url => {
    const isLive = url.startsWith('https://statsapi.mlb.com/');
    if (isLive) liveCalls++;
    if (isLive ? liveFails : savedFails) throw new Error('offline');
    return { ok: true, json: async () => isLive ? liveFeed : feed };
  },
});
const rows = () => get('scheduleGrid').children;
const tick = async callback => {
  callback();
  await new Promise(resolve => setImmediate(resolve));
};
assert.equal(intervalMs, 60_000);
assert.equal(rows().length, 1, 'remove doubleheader final, keep its next game');
assert.match(rows()[0].children[0].href, /\/2$/);
assert.equal(rows()[0].className, 'schedule-row next');

liveFails = true;
await tick(interval);
assert.equal(rows().length, 1, 'stale snapshot cannot resurrect a known final');
assert.equal(get('scheduleStatus').hidden, false, 'disclose unavailable live status');
liveFails = false;
liveFeed = live([[1, 'Final'], [2, 'Final']]);
await tick(events.focus);
assert.equal(rows().length, 0, 'clear the last game when it finishes');
assert.equal(get('schedulePanel').hidden, true);
assert.equal(get('scheduleStatus').hidden, false);
assert.match(get('scheduleStatus').textContent, /schedule is complete/);

feed = { ...feed, games: [game(3, 'Final/10'), game(4, 'Delayed'), game(5, 'Suspended')] };
liveFeed = live([[4, 'Live'], [5, 'Live']]);
await tick(events.visibilitychange);
assert.equal(rows().length, 2, 'filter saved finals but keep delayed/suspended games');
assert.equal(get('schedulePanel').hidden, false);
assert.equal(get('scheduleStatus').hidden, true);
savedFails = true;
liveFeed = live([[4, 'Final'], [5, 'Live']]);
await tick(interval);
assert.equal(rows().length, 1, 'live checks still work if the saved request fails');

doc.visibilityState = 'hidden';
const before = liveCalls;
await tick(interval);
assert.equal(liveCalls, before, 'do not poll background tabs');
doc.visibilityState = 'visible';
savedFails = false;
feed = { ...feed, games: [] };
await tick(events.visibilitychange);
assert.equal(rows().length, 0, 'an empty refreshed feed clears existing rows');
assert.equal(get('schedulePanel').hidden, true);
assert.equal(get('scheduleStatus').hidden, false);
console.log('Schedule regression tests passed.');
