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
assert.match(TEAM_CONFIG.yankees.query, /from:Yankees/);
assert.match(TEAM_CONFIG.yankees.query, /from:BryanHoch/);
assert.notEqual(TEAM_CONFIG.redsox.query, TEAM_CONFIG.yankees.query);
const redSoxFeed = buildDiscoveryFeed(payload, generatedAt);
assert.deepEqual(redSoxFeed.recent, []);
assert.equal(redSoxFeed.source_url, 'https://x.com/search?q=Red%20Sox');
console.log('Yankees X discovery feed ordering and team identity: OK');
