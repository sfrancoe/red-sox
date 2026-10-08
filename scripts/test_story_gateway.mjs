import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import handler from '../netlify/functions/app-data.mjs';

const originalFetch = globalThis.fetch;
const originalError = console.error;
const catalogBytes = await readFile(new URL('../data/stories/catalog-v1.json', import.meta.url));
const entry = JSON.parse(catalogBytes).stories[0];
const path = `stories/${entry.id}/${entry.revision}.json`;
const payload = await readFile(new URL(`../data/${path}`, import.meta.url));
let calls = [];

try {
  console.error = () => {}; // Expected failures are asserted below.
  globalThis.fetch = async url => {
    calls.push(url);
    return new Response(url.endsWith('catalog-v1.json') ? catalogBytes : payload);
  };
  for (const host of ['api.autumnlane.io', 'red-sox.netlify.app']) {
    for (const prefix of ['/api/data/', '/data/']) {
      const response = await handler(new Request(`https://${host}${prefix}stories/catalog-v1.json`));
      assert.equal(response.status, 200);
      assert.equal((await response.json()).schemaVersion, 1);
      assert.match(response.headers.get('Cache-Control'), /must-revalidate/);
      assert.equal(response.headers.get('Netlify-CDN-Cache-Control'), 'public, durable, max-age=30');
      assert.doesNotMatch(response.headers.get('Netlify-CDN-Cache-Control'), /stale-while-revalidate/);
      const story = await handler(new Request(`https://${host}${prefix}${path}`));
      assert.equal(story.status, 200);
      assert.equal((await story.json()).id, entry.id);
      assert.match(story.headers.get('Cache-Control'), /immutable/);
      assert.equal(story.headers.get('X-Content-Type-Options'), 'nosniff');
      const notModified = await handler(new Request(`https://${host}${prefix}${path}`, { headers: { 'If-None-Match': story.headers.get('ETag') } }));
      assert.equal(notModified.status, 304);
    }
  }
  for (const rejected of ['stories/draft.json', 'stories/catalog-history/old.json', 'stories/a/extra/file.json',
    'stories/../not-allowlisted.json', 'stories/a/%2e%2e/%2e%2e/config.json', `stories/a/${'A'.repeat(64)}.json`,
    `stories/${'a'.repeat(81)}/${entry.revision}.json`, `${path}/more`, `${path}.js`]) {
    calls = [];
    const response = await handler(new Request(`https://example.test/api/data/${rejected}`));
    assert.equal(response.status, 404, rejected);
    assert.equal(calls.length, 0, rejected);
  }
  for (const invalid of [Buffer.from('{}'), Buffer.from('{'), Buffer.alloc(512 * 1024 + 1, 32)]) {
    globalThis.fetch = async () => new Response(invalid);
    const response = await handler(new Request(`https://example.test/api/data/${path}`));
    assert.equal(response.status, 502);
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
  }
  for (const invalid of [Buffer.from('{"schemaVersion":2,"stories":[]}'), Buffer.alloc(128 * 1024 + 1, 32)]) {
    globalThis.fetch = async () => new Response(invalid);
    assert.equal((await handler(new Request('https://example.test/data/stories/catalog-v1.json'))).status, 502);
  }
  console.log('Story gateway passed: both hosts/routes, cache/ETag, immutable integrity, size limits, unsafe namespace rejection.');
} finally { globalThis.fetch = originalFetch; console.error = originalError; }
