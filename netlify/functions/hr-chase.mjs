const MLB_ORIGIN = 'https://statsapi.mlb.com';
const JUDGE_PLAYER_ID = 592450;
const FALLBACK_USER_AGENT = 'OpenAI File Downloader, XaiImageApiFetch/1.0';

function easternYear(date = new Date()) {
  return Number(new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York',
    year: 'numeric',
  }).format(date));
}

async function fetchJSON(url, request = fetch) {
  let lastError;
  for (const headers of [
    { Accept: 'application/json' },
    { Accept: 'application/json', 'User-Agent': FALLBACK_USER_AGENT },
  ]) {
    try {
      const response = await request(url, {
        headers,
        signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) throw new Error(`MLB returned ${response.status}`);
      return await response.json();
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

export async function loadJudgeChase(request = fetch, now = new Date()) {
  const year = easternYear(now);
  const statsURL = new URL(`/api/v1/people/${JUDGE_PLAYER_ID}/stats`, MLB_ORIGIN);
  statsURL.search = new URLSearchParams({
    stats: 'season',
    group: 'hitting',
    season: String(year),
  });
  const seasonURL = new URL(`/api/v1/seasons/${year}`, MLB_ORIGIN);
  seasonURL.search = new URLSearchParams({ sportId: '1' });

  const [stats, calendar] = await Promise.all([
    fetchJSON(statsURL, request),
    fetchJSON(seasonURL, request),
  ]);
  const totals = stats?.stats?.[0]?.splits?.[0]?.stat;
  const regularSeasonEndDate = calendar?.seasons?.[0]?.regularSeasonEndDate;
  if (!Number.isInteger(totals?.homeRuns)
      || !Number.isInteger(totals?.atBats)
      || !/^\d{4}-\d{2}-\d{2}$/.test(regularSeasonEndDate || '')) {
    throw new Error('MLB response is missing Judge season totals.');
  }

  return {
    year,
    age: 34 + (year - 2026),
    homeRuns: totals.homeRuns,
    atBats: totals.atBats,
    regularSeasonEndDate,
    source: 'MLB Stats API via Hub Ball',
  };
}

export default async () => {
  try {
    return Response.json(await loadJudgeChase(), {
      headers: {
        'Cache-Control': 'public, max-age=60, stale-while-revalidate=300',
        'Netlify-CDN-Cache-Control': 'public, durable, max-age=60, stale-while-revalidate=300',
        'Access-Control-Allow-Origin': '*',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  } catch (error) {
    console.error('Judge HR chase refresh failed', error);
    return Response.json({ error: 'Home run chase data is temporarily unavailable.' }, {
      status: 502,
      headers: { 'Cache-Control': 'no-store' },
    });
  }
};

export const config = { path: '/api/hr-chase', method: 'GET' };
