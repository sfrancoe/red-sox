import assert from 'node:assert/strict';
import handler, { ALLOWED_PATHS } from '../netlify/functions/app-data.mjs';

const originalFetch = globalThis.fetch;

try {
  let calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({ url, options });
    return new Response('{"ok":true}', { status: 200 });
  };

  let response = await handler(new Request('https://example.test/api/data/schedule.json'));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/red-sox/main/data/schedule.json');
  assert.equal(calls[0].options.headers['User-Agent'], undefined);
  assert.match(response.headers.get('Netlify-CDN-Cache-Control'), /durable/);

  calls = [];
  response = await handler(new Request('https://example.test/data/schedule.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/red-sox/main/data/schedule.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/yankees/standings.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/red-sox/main/data/yankees/standings.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/mets/standings.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/red-sox/main/data/mets/standings.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/rays/tampabay.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/red-sox/main/data/rays/tampabay.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/../netlify.toml'));
  assert.equal(response.status, 404);
  assert.equal(calls.length, 0);

  let attempt = 0;
  globalThis.fetch = async (_url, options) => {
    attempt += 1;
    if (attempt === 1) throw new Error('blocked');
    assert.equal(options.headers['User-Agent'], 'OpenAI File Downloader, XaiImageApiFetch/1.0');
    return new Response('{"fallback":true}', { status: 200 });
  };
  response = await handler(new Request('https://example.test/api/data/meta.json'));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { fallback: true });
  assert.equal(attempt, 2);

  console.log('app-data tests passed');
} finally {
  globalThis.fetch = originalFetch;
}

assert.equal(ALLOWED_PATHS.has('orioles/standings.json'), true);
assert.equal(ALLOWED_PATHS.has('dodgers/los-angeles-times.json'), true);
assert.equal(ALLOWED_PATHS.has('redsox/standings.json'), false);
assert.equal(ALLOWED_PATHS.has('standings.json'), true);
