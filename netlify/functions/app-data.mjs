const RAW_DATA_ROOT = 'https://raw.githubusercontent.com/sfrancoe/red-sox/main/data';
const FALLBACK_USER_AGENT = 'OpenAI File Downloader, XaiImageApiFetch/1.0';

const ALLOWED_PATHS = new Set([
  'athletic.json',
  'globe.json',
  'herald.json',
  'masslive.json',
  'meta.json',
  'pitching.json',
  'players.json',
  'recent-game.json',
  'schedule.json',
  'seasons.json',
  'standings.json',
  'x-posts.json',
  'yankees/athletic.json',
  'yankees/dailynews.json',
  'yankees/meta.json',
  'yankees/nypost.json',
  'yankees/nytimes.json',
  'yankees/pitching.json',
  'yankees/recent-game.json',
  'yankees/schedule.json',
  'yankees/seasons.json',
  'yankees/standings.json',
  'mets/athletic.json',
  'mets/dailynews.json',
  'mets/meta.json',
  'mets/nypost.json',
  'mets/nytimes.json',
  'mets/pitching.json',
  'mets/recent-game.json',
  'mets/schedule.json',
  'mets/seasons.json',
  'mets/standings.json',
  'rays/athletic.json',
  'rays/meta.json',
  'rays/pitching.json',
  'rays/recent-game.json',
  'rays/schedule.json',
  'rays/seasons.json',
  'rays/standings.json',
  'rays/tampabay.json',
]);

function requestedPath(request) {
  const pathname = new URL(request.url).pathname;
  const prefix = ['/api/data/', '/data/'].find(candidate => pathname.startsWith(candidate));
  if (!prefix) return null;
  try {
    return decodeURIComponent(pathname.slice(prefix.length));
  } catch {
    return null;
  }
}

async function fetchSource(path, request = fetch) {
  let lastError;
  for (const headers of [
    { Accept: 'application/json' },
    { Accept: 'application/json', 'User-Agent': FALLBACK_USER_AGENT },
  ]) {
    try {
      const response = await request(`${RAW_DATA_ROOT}/${path}`, {
        headers,
        signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) throw new Error(`GitHub returned ${response.status}`);
      const body = await response.text();
      JSON.parse(body);
      return body;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

export default async request => {
  const path = requestedPath(request);
  if (!path || !ALLOWED_PATHS.has(path)) {
    return Response.json({ error: 'Unknown app data file.' }, {
      status: 404,
      headers: { 'Cache-Control': 'no-store' },
    });
  }

  try {
    const body = await fetchSource(path);
    return new Response(body, {
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'public, max-age=60, stale-while-revalidate=300',
        'Netlify-CDN-Cache-Control': 'public, durable, max-age=300, stale-while-revalidate=3600',
        'Access-Control-Allow-Origin': '*',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  } catch (error) {
    console.error(`App data refresh failed for ${path}`, error);
    return Response.json({ error: 'App data is temporarily unavailable.' }, {
      status: 502,
      headers: { 'Cache-Control': 'no-store' },
    });
  }
};

export const config = { path: ['/api/data/*', '/data/*'], method: 'GET' };
