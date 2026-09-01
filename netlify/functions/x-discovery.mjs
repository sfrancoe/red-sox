const X_RECENT_SEARCH_URL = 'https://api.x.com/2/tweets/search/recent';
// X bills Post and User resources separately. Sixteen Posts plus, at worst,
// sixteen distinct authors costs $0.24 per UTC day at the September 2026
// rates. Media expansions are intentionally omitted from this paid feed.
const MAX_DAILY_POSTS = 16;
const DAY_MS = 24 * 60 * 60 * 1000;
const SEARCH_QUERY = '(("Red Sox" OR RedSox OR #RedSox OR @RedSox OR Fenway) lang:en) -is:retweet -is:reply';

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

export function buildDiscoveryFeed(payload, generatedAt = new Date()) {
  const users = new Map((payload.includes?.users || []).map(user => [user.id, user]));
  const cutoff = generatedAt.valueOf() - DAY_MS;
  const popular = (payload.data || [])
    .map(post => postFromResult(post, users))
    .filter(post => post && new Date(post.published).valueOf() >= cutoff)
    .sort((a, b) => b.likes - a.likes || b.published.localeCompare(a.published));

  return {
    generated_at: generatedAt.toISOString(),
    source: 'X recent search',
    source_url: `https://x.com/search?q=${encodeURIComponent('Red Sox')}`,
    recent: [],
    popular,
  };
}

function searchURL(now = new Date()) {
  const url = new URL(X_RECENT_SEARCH_URL);
  url.searchParams.set('query', SEARCH_QUERY);
  url.searchParams.set('start_time', new Date(now.valueOf() - DAY_MS).toISOString());
  url.searchParams.set('max_results', String(MAX_DAILY_POSTS));
  url.searchParams.set('sort_order', 'relevancy');
  url.searchParams.set('tweet.fields', 'author_id,created_at,entities,note_tweet,public_metrics');
  url.searchParams.set('expansions', 'author_id');
  url.searchParams.set('user.fields', 'name,profile_image_url,username');
  return url;
}

export default async () => {
  const bearerToken = process.env.X_BEARER_TOKEN;
  if (!bearerToken) {
    return Response.json({ error: 'X discovery is not configured.' }, {
      status: 503,
      headers: { 'Cache-Control': 'no-store' },
    });
  }

  try {
    const response = await fetch(searchURL(), {
      headers: { Authorization: `Bearer ${bearerToken}` },
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error(`X recent search returned ${response.status}`);

    const feed = buildDiscoveryFeed(await response.json());
    return Response.json(feed, { headers: {
      'Cache-Control': 'public, max-age=300, stale-while-revalidate=300',
      'Netlify-CDN-Cache-Control': 'public, durable, max-age=86400, stale-while-revalidate=3600',
    } });
  } catch (error) {
    console.error('X discovery refresh failed', error);
    return Response.json({ error: 'X discovery is temporarily unavailable.' }, {
      status: 502,
      headers: { 'Cache-Control': 'no-store' },
    });
  }
};

export const config = { path: '/api/x-discovery', method: 'GET' };
