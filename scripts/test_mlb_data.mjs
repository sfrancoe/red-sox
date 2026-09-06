import assert from 'node:assert/strict';
import handler from '../netlify/functions/mlb-data.mjs';

const originalFetch = globalThis.fetch;
const requests = [];
globalThis.fetch = async url => {
  requests.push(String(url));
  if (String(url).includes('/schedule')) {
    return new Response(JSON.stringify({ dates: [] }));
  }
  if (String(url).includes('/content')) {
    return new Response(JSON.stringify({
      editorial: { recap: { mlb: { headline: 'Boston wins', slug: 'boston-wins' } } },
    }));
  }
  return new Response(JSON.stringify({
    gamePk: 123,
    gameData: { teams: { away: { id: 111 }, home: { id: 147 } } },
  }));
};

let response = await handler(new Request(
  'https://example.test/api/mlb/schedule?team=red-sox&startDate=2026-09-01&endDate=2026-09-06',
));
assert.equal(response.status, 200);
assert.match(requests[0], /teamId=111/);
assert.match(requests[0], /startDate=2026-09-01/);

response = await handler(new Request(
  'https://example.test/api/mlb/schedule?team=redsox&startDate=2026-09-01&endDate=2026-09-06',
));
assert.equal(response.status, 200);
assert.match(requests[1], /teamId=111/);

response = await handler(new Request(
  'https://example.test/api/mlb/schedule?team=mets&startDate=2026-09-01&endDate=2026-09-06',
));
assert.equal(response.status, 200);
assert.match(requests[2], /teamId=121/);

response = await handler(new Request(
  'https://example.test/api/mlb/schedule?team=rays&startDate=2026-09-01&endDate=2026-09-06',
));
assert.equal(response.status, 200);
assert.match(requests[3], /teamId=139/);

response = await handler(new Request('https://example.test/api/mlb/game?team=red-sox&gamePk=123'));
assert.equal(response.status, 200);
assert.match(requests[4], /game\/123\/feed\/live/);
assert.match(requests[5], /game\/123\/content/);
assert.deepEqual((await response.json()).officialRecap, {
  headline: 'Boston wins',
  url: 'https://www.mlb.com/news/boston-wins',
});

response = await handler(new Request('https://example.test/api/mlb/game?team=red-sox&gamePk=nope'));
assert.equal(response.status, 404);

response = await handler(new Request('https://example.test/api/mlb/schedule?team=unknown'));
assert.equal(response.status, 404);

globalThis.fetch = originalFetch;
console.log('MLB live-data gateway tests passed');
