import { getStore } from '@netlify/blobs';

const X_RECENT_SEARCH_URL = 'https://api.x.com/2/tweets/search/recent';
// X bills Post and User resources separately. Sixteen Posts plus, at worst,
// sixteen distinct authors are requested per allowed team per UTC day.
// Media expansions are intentionally omitted from this paid feed.
const MAX_DAILY_POSTS = 16;
const DAY_MS = 24 * 60 * 60 * 1000;
export const TEAM_CONFIG = {
  redsox: {
    label: 'Red Sox',
    query: '(("Red Sox" OR RedSox OR #RedSox OR @RedSox OR Fenway) lang:en) -is:retweet -is:reply',
    includeRecent: false,
  },
  yankees: {
    label: 'Yankees',
    query: '(("New York Yankees" OR Yankees OR #Yankees OR @Yankees OR #RepBX) lang:en) -is:retweet -is:reply',
    // Keep Recent populated for build 2, which reads only this endpoint. Build 3 uses
    // the filtered Yankees list for Recent and ignores discovery.recent.
    includeRecent: true,
  },
  mets: {
    label: 'Mets',
    query: '(("New York Mets" OR Mets OR #Mets OR @Mets OR #LGM OR #LFGM) lang:en) -is:retweet -is:reply',
    includeRecent: true,
  },
  rays: {
    label: 'Rays',
    query: '(("Tampa Bay Rays" OR "TB Rays" OR #Rays OR @RaysBaseball OR #RaysUp) lang:en) -is:retweet -is:reply',
    includeRecent: true,
  },
};

function cleanText(value) {
  return typeof value === 'string' ? value.replace(/\s+/g, ' ').trim() : '';
}

function expandedText(post) {
  let text = cleanText(post.note_tweet?.text || post.text);
  for (const url of post.entities?.urls || []) {
    const replacement = cleanText(url.unwound_url || url.expanded_url || url.display_url);
    if (url.url && replacement) text = text.replaceAll(url.url, replacement);
  }
  return text;
}

function postFromResult(post, users) {
  const author = users.get(post.author_id) || {};
  const handle = cleanText(author.username);
  if (!post.id || !post.created_at || !handle) return null;

  return {
    id: String(post.id),
    text: expandedText(post),
    url: `https://x.com/${handle}/status/${post.id}`,
    published: post.created_at,
    likes: Number(post.public_metrics?.like_count || 0),
    author: cleanText(author.name) || handle,
    handle,
    avatar: cleanText(author.profile_image_url),
    media: '',
    quoted_text: '',
    quoted_author: '',
    quoted_handle: '',
  };
}

export function buildDiscoveryFeed(payload, generatedAt = new Date(), team = TEAM_CONFIG.redsox) {
  const users = new Map((payload.includes?.users || []).map(user => [user.id, user]));
  const cutoff = generatedAt.valueOf() - DAY_MS;
  const popular = (payload.data || [])
    .map(post => postFromResult(post, users))
    .filter(post => post && new Date(post.published).valueOf() >= cutoff)
    .sort((a, b) => b.likes - a.likes || b.published.localeCompare(a.published));

  return {
    generated_at: generatedAt.toISOString(),
    source: 'X recent search',
    source_url: `https://x.com/search?q=${encodeURIComponent(team.label)}`,
    recent: team.includeRecent
      ? [...popular].sort((a, b) => b.published.localeCompare(a.published))
      : [],
    popular,
  };
}

function searchURL(team, now = new Date()) {
  const url = new URL(X_RECENT_SEARCH_URL);
  url.searchParams.set('query', team.query);
  url.searchParams.set('start_time', new Date(now.valueOf() - DAY_MS).toISOString());
  url.searchParams.set('max_results', String(MAX_DAILY_POSTS));
  url.searchParams.set('sort_order', 'relevancy');
  url.searchParams.set('tweet.fields', 'author_id,created_at,entities,note_tweet,public_metrics');
  url.searchParams.set('expansions', 'author_id');
  url.searchParams.set('user.fields', 'name,profile_image_url,username');
  return url;
}

// Cache a feed only for what remains of its 24-hour life. A saved feed that is
// already 23 hours old must not be pinned at the CDN for another full day:
// the app drops posts older than 24 hours, so it would contribute nothing.
// An expired feed (today's paid call already spent) is rechecked every 5 minutes.
const MIN_CDN_SECONDS = 300;
export function cacheHeaders(feed, now) {
  const age = now.valueOf() - Date.parse(feed?.generated_at);
  const remaining = Number.isFinite(age) ? Math.floor((DAY_MS - age) / 1000) : 0;
  const cdnSeconds = Math.min(DAY_MS / 1000, Math.max(MIN_CDN_SECONDS, remaining));
  return {
    'Netlify-Vary': 'query=team',
    'Cache-Control': `public, max-age=${Math.min(300, cdnSeconds)}, stale-while-revalidate=300`,
    'Netlify-CDN-Cache-Control': `public, durable, max-age=${cdnSeconds}, stale-while-revalidate=${Math.min(3600, cdnSeconds)}`,
  };
}

// Injection keeps tests offline: never exercise production Blobs or paid X calls.
export function createDiscoveryHandler({
  openStore = () => getStore({ name: 'x-discovery-budget-v1', consistency: 'strong' }),
  requestX = fetch,
  now = () => new Date(),
  token = () => process.env.X_BEARER_TOKEN,
} = {}) {
  return async request => {
    const query = new URL(request.url).searchParams;
    const fail = (error, status) => Response.json({ error }, {
      status, headers: { 'Netlify-Vary': 'query=team', 'Cache-Control': 'no-store' },
    });
    if ([...query.keys()].some(key => key !== 'team') || query.getAll('team').length > 1) {
      return fail('Only one team parameter is supported.', 400);
    }
    const requestedTeam = query.get('team')?.toLowerCase() || 'redsox';
    const team = Object.hasOwn(TEAM_CONFIG, requestedTeam) ? TEAM_CONFIG[requestedTeam] : null;
    if (!team) return fail('Unknown team.', 400);

    let saved;
    try {
      const store = openStore();
      saved = await store.get(`feed/${requestedTeam}`, { type: 'json' });
      const date = now();
      if (saved && date.valueOf() - Date.parse(saved.generated_at) < DAY_MS) {
        return Response.json(saved, { headers: cacheHeaders(saved, date) });
      }
      if (!token()) return fail('X discovery is not configured.', 503);
      // An immutable reservation, not a read/increment/write counter. Never remove
      // a reservation after a failure: even a timeout may have incurred X charges.
      // With four allowed teams this bounds the entire endpoint to four calls/day.
      const { modified } = await store.setJSON(
        `reservation/${date.toISOString().slice(0, 10)}/${requestedTeam}`,
        { reservedAt: date.toISOString() }, { onlyIfNew: true },
      );
      if (!modified) {
        return saved ? Response.json(saved, { headers: cacheHeaders(saved, date) })
          : fail('Daily discovery request already reserved. Try again tomorrow.', 503);
      }
      const response = await requestX(searchURL(team, date), {
        headers: { Authorization: `Bearer ${token()}` },
        signal: AbortSignal.timeout(15_000),
      });
      if (!response.ok) throw new Error(`X recent search returned ${response.status}`);
      const feed = buildDiscoveryFeed(await response.json(), date, team);
      await store.setJSON(`feed/${requestedTeam}`, feed);
      return Response.json(feed, { headers: cacheHeaders(feed, date) });
    } catch (error) {
      console.error('X discovery refresh failed', error);
      return saved ? Response.json(saved, { headers: cacheHeaders(saved, now()) })
        : fail('X discovery is temporarily unavailable.', 502);
    }
  };
}

export default createDiscoveryHandler();
export const config = { path: '/api/x-discovery', method: 'GET' };
