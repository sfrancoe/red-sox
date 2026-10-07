import assert from 'node:assert/strict';
import { buildDiscoveryFeed, TEAM_CONFIG } from '../netlify/functions/x-discovery.mjs';

const generatedAt = new Date('2026-09-04T18:00:00Z');
const payload = {
  data: [
    {
      id: 'newer', author_id: 'one', created_at: '2026-09-04T17:30:00Z',
      text: 'Latest Yankees update', public_metrics: { like_count: 4 },
    },
    {
      id: 'liked', author_id: 'two', created_at: '2026-09-04T16:00:00Z',
      text: 'Popular Yankees update', public_metrics: { like_count: 40 },
    },
    {
      id: 'old', author_id: 'one', created_at: '2026-09-03T17:59:00Z',
      text: 'Outside the window', public_metrics: { like_count: 500 },
    },
  ],
  includes: {
    users: [
      { id: 'one', name: 'Reporter One', username: 'reporter1', profile_image_url: '' },
      { id: 'two', name: 'Reporter Two', username: 'reporter2', profile_image_url: '' },
    ],
  },
};

const feed = buildDiscoveryFeed(payload, generatedAt, TEAM_CONFIG.yankees);
assert.equal(feed.source_url, 'https://x.com/search?q=Yankees');
assert.deepEqual(feed.recent.map(post => post.id), ['newer', 'liked']);
assert.deepEqual(feed.popular.map(post => post.id), ['liked', 'newer']);
assert.ok(feed.recent.every(post => post.url.startsWith('https://x.com/')));
assert.match(TEAM_CONFIG.redsox.query, /Red Sox/);
assert.match(TEAM_CONFIG.yankees.query, /Yankees/);
assert.match(TEAM_CONFIG.yankees.query, /#RepBX/);
assert.notEqual(TEAM_CONFIG.redsox.query, TEAM_CONFIG.yankees.query);
assert.match(TEAM_CONFIG.mets.query, /Mets/);
assert.match(TEAM_CONFIG.mets.query, /#LFGM/);
assert.notEqual(TEAM_CONFIG.mets.query, TEAM_CONFIG.yankees.query);
assert.match(TEAM_CONFIG.rays.query, /Tampa Bay Rays/);
assert.match(TEAM_CONFIG.rays.query, /#RaysUp/);
assert.notEqual(TEAM_CONFIG.rays.query, TEAM_CONFIG.mets.query);
const redSoxFeed = buildDiscoveryFeed(payload, generatedAt);
assert.deepEqual(redSoxFeed.recent, []);
assert.equal(redSoxFeed.source_url, 'https://x.com/search?q=Red%20Sox');
console.log('Yankees X discovery feed ordering and team identity: OK');

const { createDiscoveryHandler } = await import('../netlify/functions/x-discovery.mjs');
const values = new Map();
const store = {
  async get(key) { return values.get(key) ?? null; },
  async setJSON(key, value, options) {
    if (options?.onlyIfNew && values.has(key)) return { modified: false };
    values.set(key, value);
    return { modified: true };
  },
};
let paidCalls = 0;
let date = new Date(generatedAt);
const handler = createDiscoveryHandler({
  openStore: () => store, now: () => date, token: () => 'test-only',
  requestX: async () => { paidCalls++; return Response.json(payload); },
});
const request = query => new Request(`https://example.test/api/x-discovery?${query}`);
assert.equal((await handler(request('team=redsox&z=1'))).status, 400);
assert.equal((await handler(request('team=redsox&team=mets'))).status, 400);
assert.equal((await handler(request('team=unknown'))).status, 400);
assert.equal((await handler(request('team=constructor'))).status, 400);
assert.equal((await handler(request('team=__proto__'))).status, 400);
assert.equal(paidCalls, 0);
await Promise.all(Array.from({ length: 20 }, () => handler(request('team=redsox'))));
assert.equal(paidCalls, 1, 'Concurrent misses reserve a single paid request');
const cached = await handler(request('team=REDSOX'));
assert.equal(cached.status, 200);
assert.equal(cached.headers.get('Netlify-Vary'), 'query=team');
assert.equal(paidCalls, 1);
// A new function instance/deploy still sees the same durable reservation.
const failed = createDiscoveryHandler({
  openStore: () => store, now: () => date, token: () => 'test-only',
  requestX: async () => { paidCalls++; throw new Error('simulated upstream timeout'); },
});
date = new Date(date.valueOf() + 25 * 60 * 60 * 1000);
assert.equal((await failed(request('team=redsox'))).status, 200);
await failed(request('team=redsox'));
assert.equal(paidCalls, 2, 'A failed paid call consumes the day reservation');
const unavailable = createDiscoveryHandler({
  openStore: () => { throw new Error('simulated storage failure'); },
  requestX: async () => { paidCalls++; }, token: () => 'test-only',
});
assert.equal((await unavailable(request('team=redsox'))).status, 502);
assert.equal(paidCalls, 2, 'Storage failure must fail closed');
console.log('X discovery durable spending cap: OK');

// CDN lifetime follows the feed's remaining 24 hours instead of a fixed day.
const { cacheHeaders } = await import('../netlify/functions/x-discovery.mjs');
const cdnSeconds = headers => Number(headers['Netlify-CDN-Cache-Control'].match(/max-age=(\d+)/)[1]);
const born = { generated_at: '2026-09-04T18:00:00.000Z' };
assert.equal(cdnSeconds(cacheHeaders(born, new Date('2026-09-04T18:00:00Z'))), 86400);
assert.equal(cdnSeconds(cacheHeaders(born, new Date('2026-09-05T17:00:00Z'))), 3600);
assert.equal(cdnSeconds(cacheHeaders(born, new Date('2026-09-05T19:00:00Z'))), 300, 'Expired feeds recheck soon');
assert.equal(cdnSeconds(cacheHeaders({}, new Date())), 300, 'Unparseable dates never cache for a day');
assert.equal(cdnSeconds(cacheHeaders(born, new Date('2026-09-04T17:59:00Z'))), 86400,
  'Future feed timestamps cannot exceed the daily CDN ceiling');
assert.equal(cdnSeconds(cacheHeaders(born, new Date('2026-09-05T17:59:59Z'))), 300,
  'Nearly expired feeds retain the five-minute recheck floor');
const agedFeeds = new Map([['feed/redsox', { ...redSoxFeed, generated_at: '2026-09-04T18:00:00.000Z' }]]);
const aged = createDiscoveryHandler({
  openStore: () => ({
    async get(key) { return agedFeeds.get(key) ?? null; },
    async setJSON() { throw new Error('A fresh saved feed must not reserve a paid call'); },
  }),
  now: () => new Date('2026-09-05T17:00:00Z'), token: () => 'test-only',
  requestX: async () => { throw new Error('A fresh saved feed must not call X'); },
});
const agedResponse = await aged(request('team=redsox'));
assert.equal(agedResponse.status, 200);
assert.match(agedResponse.headers.get('Netlify-CDN-Cache-Control'), /max-age=3600,/);
console.log('X discovery CDN lifetime tracks feed age: OK');
