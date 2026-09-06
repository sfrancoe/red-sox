const MLB_ORIGIN = 'https://statsapi.mlb.com';
const FALLBACK_USER_AGENT = 'OpenAI File Downloader, XaiImageApiFetch/1.0';
const TEAMS = new Map([
  ['red-sox', 111],
  ['redsox', 111],
  ['yankees', 147],
  ['mets', 121],
  ['rays', 139],
]);

function validDate(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value || '');
}

function easternDate(date = new Date()) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/New_York',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

async function fetchSource(url, request = fetch) {
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
      if (!response.ok) throw new Error(`Upstream returned ${response.status}`);
      const body = await response.text();
      const payload = JSON.parse(body);
      return { body, payload };
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

function upstreamURL(requestURL, teamID) {
  const route = requestURL.pathname.replace(/^\/api\/mlb\/?/, '');
  if (route === 'schedule') {
    const today = easternDate();
    const startDate = validDate(requestURL.searchParams.get('startDate'))
      ? requestURL.searchParams.get('startDate')
      : today;
    const endDate = validDate(requestURL.searchParams.get('endDate'))
      ? requestURL.searchParams.get('endDate')
      : today;
    const url = new URL('/api/v1/schedule', MLB_ORIGIN);
    url.search = new URLSearchParams({
      sportId: '1',
      teamId: String(teamID),
      startDate,
      endDate,
      gameType: 'R',
    });
    return { route, url };
  }

  if (route === 'game') {
    const gamePk = requestURL.searchParams.get('gamePk') || '';
    if (!/^\d{1,10}$/.test(gamePk)) return null;
    return { route, url: new URL(`/api/v1.1/game/${gamePk}/feed/live`, MLB_ORIGIN) };
  }
  return null;
}

function gameIncludesTeam(payload, teamID) {
  const teams = payload?.gameData?.teams;
  return teams?.away?.id === teamID || teams?.home?.id === teamID;
}

function officialRecap(content) {
  const recap = content?.editorial?.recap?.mlb;
  const headline = String(recap?.headline || '').trim();
  const slug = String(recap?.slug || '').trim();
  if (!headline || !slug) return null;
  return { headline, url: `https://www.mlb.com/news/${slug}` };
}

export default async request => {
  const requestURL = new URL(request.url);
  const teamID = TEAMS.get(requestURL.searchParams.get('team'));
  const upstream = teamID ? upstreamURL(requestURL, teamID) : null;
  if (!upstream) {
    return Response.json({ error: 'Unknown live-data request.' }, { status: 404 });
  }

  try {
    let { body, payload } = await fetchSource(upstream.url);
    if (upstream.route === 'game' && !gameIncludesTeam(payload, teamID)) {
      return Response.json({ error: 'Game does not belong to the requested team.' }, { status: 404 });
    }
    if (upstream.route === 'game') {
      const gamePk = requestURL.searchParams.get('gamePk');
      try {
        const contentURL = new URL(`/api/v1/game/${gamePk}/content`, MLB_ORIGIN);
        const { payload: content } = await fetchSource(contentURL);
        const recap = officialRecap(content);
        if (recap) {
          payload = { ...payload, officialRecap: recap };
          body = JSON.stringify(payload);
        }
      } catch (error) {
        // A box score is still useful while MLB's delayed editorial feed catches up.
        console.warn(`Official recap unavailable for game ${gamePk}`, error);
      }
    }
    return new Response(body, {
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'public, max-age=5, stale-while-revalidate=15',
        'Netlify-CDN-Cache-Control': 'public, durable, max-age=5, stale-while-revalidate=15',
        'Access-Control-Allow-Origin': '*',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  } catch (error) {
    console.error('Live game data failed', error);
    return Response.json({ error: 'Live game data is temporarily unavailable.' }, {
      status: 502,
      headers: { 'Cache-Control': 'no-store' },
    });
  }
};

export const config = { path: '/api/mlb/*', method: 'GET' };
