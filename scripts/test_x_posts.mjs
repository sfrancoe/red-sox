import assert from 'node:assert/strict';
import { buildFeed, TEAM_CONFIG } from '../netlify/functions/x-posts.mjs';

const generatedAt = new Date('2026-09-04T20:00:00Z');

function entry({ id, text, createdAt, likes, handle = 'reporter' }) {
  return {
    content: {
      tweet: {
        id_str: id,
        full_text: text,
        created_at: createdAt,
        favorite_count: likes,
        permalink: `/${handle}/status/${id}`,
        user: {
          name: 'Reporter',
          screen_name: handle,
          profile_image_url_https: '',
        },
      },
    },
  };
}

const entries = [
  entry({
    id: 'latest',
    text: 'First pitch at Yankee Stadium is set for tonight.',
    createdAt: 'Fri Sep 04 19:45:00 +0000 2026',
    likes: 12,
  }),
  entry({
    id: 'liked',
    text: 'Aaron Judge gives the Yankees the lead with a two-run homer.',
    createdAt: 'Fri Sep 04 18:00:00 +0000 2026',
    likes: 250,
  }),
  entry({
    id: 'roster',
    text: 'Jazz Chisholm Jr. is back in the lineup tonight.',
    createdAt: 'Fri Sep 04 17:00:00 +0000 2026',
    likes: 80,
  }),
  entry({
    id: 'off-topic',
    text: 'A charity golf event is scheduled for next weekend.',
    createdAt: 'Fri Sep 04 19:30:00 +0000 2026',
    likes: 900,
  }),
  entry({
    id: 'old',
    text: 'Yankees history from an earlier week.',
    createdAt: 'Mon Aug 31 12:00:00 +0000 2026',
    likes: 500,
  }),
];

const rosterTerms = new Set(['aaron judge', 'judge', 'jazz chisholm jr.', 'chisholm']);
const feed = buildFeed(entries, rosterTerms, TEAM_CONFIG.yankees, generatedAt);

assert.equal(TEAM_CONFIG.yankees.listId, '2095986539037647187');
assert.equal(feed.source_url, 'https://x.com/i/lists/2095986539037647187');
assert.deepEqual(feed.recent.map(post => post.id), ['latest', 'liked', 'roster', 'old']);
assert.deepEqual(feed.popular.map(post => post.id), ['liked', 'roster', 'latest']);
assert.ok(!feed.recent.some(post => post.id === 'off-topic'));

const redSoxFeed = buildFeed([
  entry({
    id: 'sox',
    text: 'The Red Sox return to Fenway tonight.',
    createdAt: 'Fri Sep 04 19:00:00 +0000 2026',
    likes: 20,
  }),
], new Set(), TEAM_CONFIG.redsox, generatedAt);
assert.equal(redSoxFeed.source_url, 'https://x.com/i/lists/1431748439818346496');

const metsFeed = buildFeed([
  entry({
    id: 'mets',
    text: 'The Mets return to Citi Field tonight.',
    createdAt: 'Fri Sep 04 19:15:00 +0000 2026',
    likes: 30,
  }),
  entry({
    id: 'not-mets',
    text: 'The Yankees are back in the Bronx.',
    createdAt: 'Fri Sep 04 19:10:00 +0000 2026',
    likes: 90,
  }),
], new Set(), TEAM_CONFIG.mets, generatedAt);
assert.equal(TEAM_CONFIG.mets.listId, '2096714864223748361');
assert.equal(metsFeed.source_url, 'https://x.com/i/lists/2096714864223748361');
assert.deepEqual(metsFeed.recent.map(post => post.id), ['mets']);

const raysFeed = buildFeed([
  entry({
    id: 'rays',
    text: 'The Rays are back at Steinbrenner Field tonight.',
    createdAt: 'Fri Sep 04 19:20:00 +0000 2026',
    likes: 35,
  }),
  entry({
    id: 'not-rays',
    text: 'The Tampa Bay Lightning begin training camp.',
    createdAt: 'Fri Sep 04 19:18:00 +0000 2026',
    likes: 100,
  }),
], new Set(), TEAM_CONFIG.rays, generatedAt);
assert.equal(TEAM_CONFIG.rays.listId, '2096730568285200550');
assert.equal(raysFeed.source_url, 'https://x.com/i/lists/2096730568285200550');
assert.deepEqual(raysFeed.recent.map(post => post.id), ['rays']);

console.log('Team-specific X list filtering and ordering: OK');
