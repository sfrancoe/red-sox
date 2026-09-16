import { MLB_TEAMS } from './team-registry.mjs';

const RAW_DATA_ROOT = 'https://raw.githubusercontent.com/sfrancoe/red-sox/main/data';
const FALLBACK_USER_AGENT = 'OpenAI File Downloader, XaiImageApiFetch/1.0';

const STANDARD_FILES = [
  'meta.json', 'pitching.json', 'recent-game.json', 'schedule.json',
  'seasons.json', 'standings.json', 'x-posts.json',
];

export const ALLOWED_PATHS = new Set(MLB_TEAMS.flatMap(team => {
  const prefix = team.legacy_root_data ? '' : `${team.data_directory}/`;
  const files = [
    ...STANDARD_FILES,
    ...team.news_sources.map(source => `${source.key}.json`),
  ];
  if (team.features.players) files.push('players.json');
  return files.map(file => `${prefix}${file}`);
}));

// Shared comparison artifacts never carry a team-directory prefix. Keep the
// allowlist finite: a new season is a deliberate gateway/deployment change.
for (const year of [2023, 2024, 2025, 2026]) {
  ALLOWED_PATHS.add(`leaderboards/${year}.json`);
}

// A player card requests a single generated career record by the stable numeric
// ID in its roster feed. Restrict this dynamic collection to a filename only:
// no nested paths, extensions, or arbitrary repository reads are permitted.
function isAllowedPath(path) {
  return ALLOWED_PATHS.has(path) || /^player-careers\/\d{1,10}\.json$/.test(path);
}

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
  if (!path || !isAllowedPath(path)) {
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
