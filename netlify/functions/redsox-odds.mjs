const API = 'https://api.odds-api.io/v3';
const BOOKMAKER = 'DraftKings';
const FALLBACK = 'OpenAI File Downloader, XaiImageApiFetch/1.0';

function decimalToAmerican(value) {
  const decimal = Number(value);
  if (!Number.isFinite(decimal) || decimal <= 1) return null;
  const american = decimal >= 2 ? (decimal - 1) * 100 : -100 / (decimal - 1);
  return Math.round(american);
}

function teamSide(event) {
  if (/boston red sox/i.test(event.home || '')) return 'home';
  if (/boston red sox/i.test(event.away || '')) return 'away';
  return null;
}

function market(markets, names) {
  return markets.find(item => names.includes(String(item.name).toLowerCase()));
}

export function normalizeDraftKings(event) {
  const side = teamSide(event);
  const markets = event.bookmakers?.[BOOKMAKER];
  if (!side || !Array.isArray(markets)) return null;

  const moneyline = market(markets, ['ml', 'moneyline', 'money line']);
  const spread = market(markets, ['spread', 'spreads', 'run line', 'runline']);
  const moneylineOdds = moneyline?.odds?.[0];
  const spreadOdds = spread?.odds?.[0];
  const homeHandicap = Number(spreadOdds?.hdp);

  return {
    eventId: String(event.id),
    gameDate: event.date,
    homeTeam: event.home,
    awayTeam: event.away,
    sportsbook: BOOKMAKER,
    moneyline: decimalToAmerican(moneylineOdds?.[side]),
    runLine: Number.isFinite(homeHandicap) ? (side === 'home' ? homeHandicap : -homeHandicap) : null,
    runLinePrice: decimalToAmerican(spreadOdds?.[side]),
    updatedAt: moneyline?.updatedAt || spread?.updatedAt || null,
  };
}

async function apiJson(path, apiKey) {
  let error;
  for (const headers of [{}, { 'User-Agent': FALLBACK }]) {
    try {
      const separator = path.includes('?') ? '&' : '?';
      const response = await fetch(`${API}${path}${separator}apiKey=${encodeURIComponent(apiKey)}`, {
        headers,
        signal: AbortSignal.timeout(7000),
      });
      if (!response.ok) throw new Error(`Odds source returned ${response.status}`);
      return await response.json();
    } catch (caught) {
      error = caught;
    }
  }
  throw error;
}

async function draftKingsGames(apiKey) {
  const events = await apiJson(
    `/events?sport=baseball&league=usa-mlb&status=pending&bookmaker=${encodeURIComponent(BOOKMAKER)}`,
    apiKey,
  );
  const boston = (Array.isArray(events) ? events : [])
    .filter(teamSide)
    .sort((a, b) => String(a.date).localeCompare(String(b.date)))
    .slice(0, 3);
  if (!boston.length) return [];

  const ids = boston.map(event => event.id).join(',');
  const odds = await apiJson(
    `/odds/multi?eventIds=${encodeURIComponent(ids)}&bookmakers=${encodeURIComponent(BOOKMAKER)}`,
    apiKey,
  );
  return (Array.isArray(odds) ? odds : []).map(normalizeDraftKings).filter(Boolean);
}

export default async () => {
  const headers = {
    'Cache-Control': 'public, max-age=60',
    'Netlify-CDN-Cache-Control': 'public, durable, max-age=300',
  };
  const apiKey = process.env.ODDS_API_IO_KEY;
  if (!apiKey) {
    return Response.json({
      generatedAt: null,
      sportsbook: BOOKMAKER,
      games: [],
      available: false,
      message: 'Sportsbook lines are not configured yet.',
    }, { status: 503, headers: { 'Cache-Control': 'no-store' } });
  }

  try {
    const games = await draftKingsGames(apiKey);
    return Response.json({
      generatedAt: new Date().toISOString(),
      sportsbook: BOOKMAKER,
      games,
      available: true,
    }, { headers });
  } catch {
    return Response.json({
      generatedAt: null,
      sportsbook: BOOKMAKER,
      games: [],
      available: false,
      message: 'Sportsbook lines are temporarily unavailable.',
    }, { status: 502, headers: { 'Cache-Control': 'no-store' } });
  }
};

export const config = { path: '/api/redsox-odds', method: 'GET' };
