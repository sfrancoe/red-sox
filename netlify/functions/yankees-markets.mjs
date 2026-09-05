// Public, read-only market data. No credentials, orders, wallets, or dependencies.
const KALSHI = 'https://api.elections.kalshi.com/trade-api/v2';
const GAMMA = 'https://gamma-api.polymarket.com';
const CLOB = 'https://clob.polymarket.com';
const FALLBACK = 'OpenAI File Downloader, XaiImageApiFetch/1.0';
const series = ['KXMLBGAME', 'KXMLBTOTAL', 'KXMLBSPREAD', 'KXMLB'];
const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
export function number(value) {
  if (value === null || value === undefined || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}
const price = v => { const n = number(v); return n !== null && n >= 0 && n <= 1 ? n : null; };
const array = v => { try { return Array.isArray(v) ? v : JSON.parse(v || '[]'); } catch { return []; } };
async function json(url) {
  let error;
  for (const headers of [{}, { 'User-Agent': FALLBACK }]) {
    try {
      const r = await fetch(url, { headers, signal: AbortSignal.timeout(7000) });
      if (!r.ok) throw new Error(`Source returned ${r.status}`);
      return await r.json();
    } catch (e) { error = e; }
  }
  throw error;
}
function gameIdentity(ticker) {
  const m = ticker.match(/-(\d{2})([A-Z]{3})(\d{2})(\d{4})([A-Z]+)$/);
  if (!m || !m[5].includes('NYY')) return null;
  const month = months.indexOf(m[2]) + 1;
  if (!month) return null;
  const date = `20${m[1]}-${String(month).padStart(2, '0')}-${m[3]}`;
  return { date, opponent: m[5].replace('NYY', ''), time: `${m[4].slice(0,2)}:${m[4].slice(2)}` };
}
export function normalizeKalshi(m, now = new Date()) {
  if (m.status !== 'active' || m.result) return null;
  const kind = m.event_ticker?.split('-')[0];
  const game = gameIdentity(m.event_ticker || '');
  const future = kind === 'KXMLB' && m.ticker === `KXMLB-${String(now.getUTCFullYear()).slice(2)}-NYY`;
  if (!game && !future) return null;
  if (kind === 'KXMLBGAME' && !m.ticker.endsWith('-NYY')) return null;
  const bid = price(m.yes_bid_dollars), ask = price(m.yes_ask_dollars);
  // Missing/one-sided books are not 0% forecasts; do not use untraded zero prices.
  const probability = bid !== null && ask !== null && bid <= ask && bid > 0 && ask < 1 ? (bid + ask) / 2 : null;
  return {
    id: m.ticker, provider: 'Kalshi', title: future ? m.title : `New York vs ${game.opponent}`,
    question: m.title, outcome: kind === 'KXMLBGAME' ? 'Yankees win' : (m.yes_sub_title || 'Yes'),
    category: future ? 'Season' : kind === 'KXMLBGAME' ? 'Winner' : kind === 'KXMLBTOTAL' ? 'Totals' : 'Spread',
    probability, bid, ask, volume: number(m.volume_24h_fp), volumeUnit: 'contracts / 24h',
    date: game?.date || null, timeLabel: game ? `${game.time} ET` : `${now.getUTCFullYear()} season`,
    matchKey: kind === 'KXMLBGAME' ? `${game.date}:${game.opponent}` : null,
    historyId: m.ticker, rules: [m.rules_primary, m.rules_secondary].filter(Boolean).join('\n\n'),
    url: `https://kalshi.com/markets/${kind.toLowerCase()}/${m.event_ticker.toLowerCase()}`,
  };
}
export function normalizePoly(event, m) {
  if (!m.active || m.closed || m.archived || m.acceptingOrders === false) return null;
  const slug = event.slug || '';
  const game = slug.match(/^mlb-([a-z]+)-([a-z]+)-(\d{4}-\d{2}-\d{2})$/);
  const isGame = game && [game[1],game[2]].includes('nyy');
  if (!isGame && !/yankees/i.test(m.question || '')) return null;
  // Keep the season board about team outcomes; manager speculation can swamp it.
  if (/manager|coach/i.test(event.title || '')) return null;
  const outcomes = array(m.outcomes), prices = array(m.outcomePrices), tokens = array(m.clobTokenIds);
  const winner = m.sportsMarketType === 'moneyline';
  let index = winner ? outcomes.findIndex(x => /yankees/i.test(x)) : 0;
  if (index < 0 || !tokens[index]) return null;
  const p = price(prices[index]);
  const b = price(m.bestBid), a = price(m.bestAsk);
  const bid = index === 0 ? b : a === null ? null : 1-a;
  const ask = index === 0 ? a : b === null ? null : 1-b;
  return {
    id: m.id, provider: 'Polymarket', title: event.title, question: m.question,
    outcome: winner ? 'Yankees win' : outcomes[index],
    category: !isGame ? 'Season' : winner ? 'Winner' : m.sportsMarketType === 'totals' ? 'Totals' : m.sportsMarketType === 'spreads' ? 'Spread' : 'Game props',
    probability: p, bid, ask, volume: number(m.volume24hr), volumeUnit: 'USD / 24h',
    date: isGame ? game[3] : null,
    timeLabel: m.gameStartTime ? new Date(m.gameStartTime).toLocaleTimeString('en-US', { timeZone: 'America/New_York', hour: 'numeric', minute: '2-digit' }) + ' ET' : 'Season market',
    matchKey: isGame && winner ? `${game[3]}:${(game[1] === 'nyy' ? game[2] : game[1]).toUpperCase()}` : null,
    historyId: tokens[index], rules: m.description || event.description || '',
    url: `https://polymarket.com/event/${encodeURIComponent(slug)}/${encodeURIComponent(m.slug)}`,
  };
}
async function kalshiMarkets() {
  const pages = await Promise.all(series.map(async s => {
    const out = []; let cursor = '';
    for (let page = 0; page < 4; page++) {
      const data = await json(`${KALSHI}/markets?status=open&limit=1000&series_ticker=${s}&cursor=${encodeURIComponent(cursor)}`);
      out.push(...data.markets); cursor = data.cursor;
      if (!cursor) break;
      if (page === 3) throw new Error('Market pagination limit reached');
    }
    return out;
  }));
  return pages.flat().map(m => normalizeKalshi(m)).filter(Boolean);
}
async function polyMarkets() {
  const out = [];
  for (let page = 1; page <= 3; page++) {
    const data = await json(`${GAMMA}/public-search?q=Red%20Sox&events_status=active&limit_per_type=50&page=${page}`);
    for (const e of data.events || []) for (const m of e.markets || []) {
      const normalized = normalizePoly(e, m);
      if (normalized) out.push(normalized);
    }
    if (!data.pagination?.hasMore) break;
  }
  return [...new Map(out.map(m => [m.id, m])).values()];
}
export function cleanHistory(points, start, end) {
  return [...new Map(points.filter(p => Number.isFinite(p.t) && p.t >= start && p.t <= end && price(p.p) !== null).map(p => [p.t, p])).values()].sort((a,b) => a.t-b.t);
}
async function history(provider, id, days) {
  const end = Math.floor(Date.now()/1000), start = end - days*86400;
  let points;
  if (provider === 'Kalshi') {
    if (!/^KXMLB(?:GAME|TOTAL|SPREAD)?-[A-Z0-9-]+$/.test(id)) throw new Error('Invalid market');
    const data = await json(`${KALSHI}/series/${id.split('-')[0]}/markets/${id}/candlesticks?start_ts=${start}&end_ts=${end}&period_interval=60`);
    points = (data.candlesticks || []).map(c => {
      const b = price(c.yes_bid?.close_dollars), a = price(c.yes_ask?.close_dollars);
      return { t: c.end_period_ts, p: b !== null && a !== null && b <= a && b > 0 && a < 1 ? (b+a)/2 : null };
    }).filter(p => p.p !== null);
  } else if (provider === 'Polymarket') {
    if (!/^\d{1,100}$/.test(id)) throw new Error('Invalid token');
    const data = await json(`${CLOB}/prices-history?market=${id}&startTs=${start}&endTs=${end}&fidelity=60`);
    points = data.history || [];
  } else throw new Error('Invalid provider');
  return { points: cleanHistory(points,start,end) };
}
export default async request => {
  const params = new URL(request.url).searchParams;
  const headers = { 'Cache-Control': 'public, max-age=60', 'Netlify-CDN-Cache-Control': 'public, durable, max-age=120' };
  if (params.has('history')) {
    try { return Response.json(await history(params.get('provider'), params.get('history'), params.get('days') === '7' ? 7 : 1), { headers }); }
    catch { return Response.json({ error: 'Price history is temporarily unavailable.' }, {status:502,headers:{'Cache-Control':'no-store'}}); }
  }
  const results = await Promise.allSettled([kalshiMarkets(), polyMarkets()]);
  const sources = results.map((r,i) => ({ name: ['Kalshi','Polymarket'][i], available: r.status === 'fulfilled' }));
  const markets = results.flatMap(r => r.status === 'fulfilled' ? r.value : []);
  const today = new Date().toLocaleDateString('en-CA', {timeZone:'America/New_York'});
  // Open-but-abandoned games must not masquerade as upcoming games.
  const current = markets.filter(m => !m.date || m.date >= today).sort((a,b) => (a.date || '9999').localeCompare(b.date || '9999') || (b.volume || 0)-(a.volume || 0));
  return Response.json({ generatedAt: new Date().toISOString(), markets: current, sources }, { status: sources.some(s => s.available) ? 200 : 502, headers: sources.some(s=>s.available) ? headers : {'Cache-Control':'no-store'} });
};
export const config = { path: '/api/yankees-markets', method: 'GET' };
