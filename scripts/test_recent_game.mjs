// Zero-dependency tests against the built site over HTTP.
// bash scripts/build_site.sh; python3 -m http.server 8765 --directory _site
// node --experimental-vm-modules scripts/test_recent_game.mjs
import assert from 'node:assert/strict';
import vm from 'node:vm';

const origin = process.env.TEST_SITE_URL || 'http://localhost:8765';
async function source(path) {
  const response = await fetch(`${origin}${path}`);
  assert.equal(response.status, 200, path);
  return response.text();
}
const adapterSource = await source('/src/recent-game-feed.js');
const pageSource = await source('/src/recent-game.js');
const saved = JSON.parse(await source('/data/recent-game.json'));
const adapter = await import(`data:text/javascript;base64,${Buffer.from(adapterSource).toString('base64')}`);
const final = (gamePk, gameDate, code = 'F') => ({ gamePk, gameDate, status: { abstractGameState: 'Final', codedGameState: code } });
assert.equal(adapter.latestFinal({ dates: [{ games: [
  final(1, '2026-08-30T17:00:00Z'), final(2, '2026-08-30T23:00:00Z'),
  final(3, '2026-08-31T00:00:00Z', 'D'), final(4, '2026-08-31T01:00:00Z', 'C'),
] }] }).gamePk, 2, 'choose latest doubleheader final, excluding postponed/cancelled');
assert.equal(adapter.latestFinal({ dates: [] }), undefined);
assert.ok(adapter.isOlderGame({ ...saved, game_date: '2020-01-01T00:00:00Z' }, saved));
assert.throws(() => adapter.validateFeed({ ...saved, innings: [] }), /incomplete/);
assert.throws(() => adapter.buildLiveFeed({ gameData: { status: { abstractGameState: 'Live' } } }), /not final/);
let requestedURL;
await assert.rejects(adapter.fetchLatestGame(new Date('2026-08-31T02:00:00Z'), async url => {
  requestedURL = url;
  return { dates: [] };
}), /No recent/);
assert.match(requestedURL, /endDate=2026-08-30/, 'use Eastern date, not UTC');

// Model only the DOM interfaces used by the renderer; no browser dependencies.
class Element {
  constructor(id = '') {
    this.id = id;
    this.children = [];
    this.dataset = {};
    this.events = {};
    this.classes = new Set();
    this.classList = {
      contains: name => this.classes.has(name),
      toggle: (name, active) => active ? this.classes.add(name) : this.classes.delete(name),
    };
  }
  appendChild(child) { this.children.push(child); return child; }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this.children = children; }
  setAttribute(key, value) { this[key] = value; }
  addEventListener(key, callback) { this.events[key] = callback; }
  focus() {}
}
async function pageHarness({ savedFeed = saved, liveFeed = saved, savedFails = false, liveFails = false, delayedSaved = false } = {}) {
  const elements = new Map();
  const get = id => {
    if (!elements.has(id)) elements.set(id, new Element(id));
    return elements.get(id);
  };
  const tabs = ['away', 'home'].map(side => {
    const tab = get(`${side}BoxTab`);
    tab.dataset.target = `${side}Box`;
    return tab;
  });
  const doc = {
    visibilityState: 'visible', events: {},
    getElementById: get, createElement: () => new Element(),
    querySelectorAll: selector => selector === '.boxscore-mobile-tab' ? tabs : [get('awayBox'), get('homeBox')],
    addEventListener(key, callback) { this.events[key] = callback; },
  };
  const win = { events: {}, addEventListener(key, callback) { this.events[key] = callback; } };
  let calls = 0, interval, intervalMs, releaseSaved;
  const waitSaved = new Promise(resolve => { releaseSaved = resolve; });
  const context = vm.createContext({
    document: doc, window: win, console: { warn() {} },
    setInterval(callback, ms) { interval = callback; intervalMs = ms; },
  });
  const dependency = new vm.SyntheticModule(['fetchJSON', 'fetchLatestGame', 'isOlderGame', 'validateFeed'], function () {
    this.setExport('fetchJSON', async () => {
      if (delayedSaved) await waitSaved;
      if (savedFails) throw new Error('offline');
      return savedFeed;
    });
    this.setExport('fetchLatestGame', async () => {
      calls++;
      if (liveFails) throw new Error('MLB unavailable');
      return liveFeed;
    });
    this.setExport('isOlderGame', adapter.isOlderGame);
    this.setExport('validateFeed', adapter.validateFeed);
  }, { context });
  const page = new vm.SourceTextModule(pageSource, { context });
  await page.link(() => dependency);
  const ready = page.evaluate();
  await new Promise(resolve => setImmediate(resolve));
  releaseSaved();
  await ready;
  assert.equal(intervalMs, 60_000);
  return {
    get, tabs, doc, win, interval,
    calls: () => calls,
    failLive() { liveFails = true; },
    changeLive(feed) { liveFeed = feed; },
  };
}
const flush = () => new Promise(resolve => setImmediate(resolve));
const newGame = { ...saved, game_pk: saved.game_pk + 1, game_date: '2099-01-01T00:00:00Z', summary: 'New final' };
const page = await pageHarness({ liveFeed: newGame, delayedSaved: true });
assert.equal(page.get('recentGameSummary').textContent, 'New final', 'late saved response cannot roll back new game');
page.tabs[1].events.click();
page.changeLive({ ...newGame, summary: 'Official correction' });
const beforeCorrection = page.calls();
page.interval();
page.interval();
await flush();
assert.equal(page.calls(), beforeCorrection + 1, 'prevent overlapping refresh requests');
assert.equal(page.get('recentGameSummary').textContent, 'Official correction');
assert.equal(page.tabs[1]['aria-selected'], 'true', 'keep selected box score on correction');
page.failLive();
page.interval();
await flush();
assert.equal(page.get('recentGameSummary').textContent, 'Official correction', 'keep latest on API failure');
page.doc.visibilityState = 'hidden';
const before = page.calls();
page.interval();
assert.equal(page.calls(), before, 'do not poll a hidden tab');
page.doc.visibilityState = 'visible';
page.doc.events.visibilitychange();
await flush();
assert.equal(page.calls(), before + 1, 'refresh immediately on return');
page.win.events.online();
await flush();
assert.equal(page.calls(), before + 2, 'refresh after reconnect');
const fallback = await pageHarness({ liveFails: true });
assert.equal(fallback.get('recentGameSummary').textContent, saved.summary);
const liveOnly = await pageHarness({ savedFails: true });
assert.equal(liveOnly.get('recentGameSummary').textContent, saved.summary);
const failed = await pageHarness({ liveFails: true, savedFails: true });
assert.match(failed.get('recentGameStatus').textContent, /could not be loaded/);
const partial = await pageHarness({ liveFeed: { ...saved, innings: [] } });
assert.equal(partial.get('recentGameSummary').textContent, saved.summary, 'keep saved box score when final is incomplete');
const correctionRace = await pageHarness({
  liveFeed: { ...saved, summary: 'Corrected same game' }, delayedSaved: true,
});
assert.equal(correctionRace.get('recentGameSummary').textContent, 'Corrected same game');

if (process.env.TEST_LIVE_MLB === '1') {
  const live = await adapter.fetchLatestGame();
  assert.equal(live.game_pk, saved.game_pk, 'refresh saved feed before live parity test');
  assert.equal(live.summary, saved.summary);
  assert.deepEqual(live.scoring_plays, saved.scoring_plays);
  for (const side of ['away', 'home']) {
    for (const key of ['runs', 'hits', 'errors', 'record', 'club_name', 'abbreviation']) {
      assert.equal(live[side][key], saved[side][key], `${side}.${key}`);
    }
    for (const role of ['batting', 'pitching']) {
      assert.equal(live[side][role].length, saved[side][role].length);
      live[side][role].forEach((row, index) => {
        for (const [key, value] of Object.entries(row)) assert.equal(value, saved[side][role][index][key], `${side}.${role}.${index}.${key}`);
      });
    }
  }
  console.log(`Live MLB parity passed for game ${live.game_pk}.`);
}
console.log('Recent Game HTTP module, refresh, fallback, selection, and date tests passed.');
