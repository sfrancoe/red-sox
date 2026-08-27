const LIST_ID = '1431748439818346496';
const LIST_URL = `https://syndication.twitter.com/srv/timeline-list/list-id/${LIST_ID}?lang=en&theme=light&showHeader=false&hideBorder=true`;
const ROSTER_URL = `https://statsapi.mlb.com/api/v1/teams/111/roster?rosterType=fullSeason&season=${new Date().getUTCFullYear()}&hydrate=person`;
const FALLBACK_USER_AGENT = 'OpenAI File Downloader, XaiImageApiFetch/1.0';
const TEAM_TERMS = [
  'red sox', 'redsox', '#redsox', '@redsox', 'bosox', 'fenway', 'woo sox', 'woosox',
  'worcester red sox', 'portland sea dogs', 'portland seadogs', 'red stockings',
  'sox prospects', 'soxprospects',
];
const RED_SOX_LINK_TERMS = [
  'redsox.com', 'mlb.com/redsox', 'bostonglobe.com/sports/baseball/redsox',
  'bostonherald.com/sports/mlb/boston-red-sox', 'masslive.com/redsox', 'beyondthemonster',
  'overthemonster', 'bosoxinjection', 'soxprospects', 'thepeskyreport', 'sawxstack',
];
const NON_REDSOX_TERMS = [
  'white sox', 'chicago sox', 'patriots', '#patriots', '#nfl', 'football', 'celtics',
  '#nba', 'basketball', 'bruins', '#nhl', 'hockey',
];
const COMMON_SURNAMES = new Set([
  'anderson', 'anthony', 'campbell', 'gray', 'harris', 'hill', 'miller', 'scott', 'short',
  'story', 'walker', 'west', 'white', 'young',
]);

function cleanText(value) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(/&#x([\da-f]+);/gi, (_, code) => String.fromCodePoint(parseInt(code, 16)))
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
    .replace(/\s+/g, ' ').trim();
}

async function fetchText(url, expected) {
  let lastError;
  for (const headers of [{}, { 'User-Agent': FALLBACK_USER_AGENT }]) {
    try {
      const response = await fetch(url, { headers, signal: AbortSignal.timeout(12_000) });
      if (!response.ok) throw new Error(`request returned ${response.status}`);
      const body = await response.text();
      if (!body.includes(expected)) throw new Error(`response did not contain ${expected}`);
      return body;
    } catch (error) {
      lastError = error;
    }
  }
  throw new Error(`Could not fetch source: ${lastError?.message || 'unknown error'}`);
}

function rosterTerms(payload) {
  const terms = new Set();
  for (const row of payload.roster || []) {
    const name = cleanText(row.person?.fullName).toLowerCase();
    if (!name) continue;
    terms.add(name);
    const surname = name.split(/[\s-]+/).at(-1);
    if (surname.length >= 5 && !COMMON_SURNAMES.has(surname)) terms.add(surname);
  }
  return terms;
}

function tweetContext(tweet) {
  const parts = [tweet.full_text, tweet.text];
  for (const nested of [tweet.quoted_status || {}, tweet.retweeted_status || {}]) {
    parts.push(nested.full_text, nested.text);
  }
  for (const item of [tweet, tweet.quoted_status || {}, tweet.retweeted_status || {}]) {
    for (const url of item.entities?.urls || []) parts.push(url.expanded_url, url.display_url);
    for (const media of item.extended_entities?.media || []) parts.push(media.ext_alt_text);
  }
  return cleanText(parts.filter(part => typeof part === 'string').join(' ')).toLowerCase();
}

function relevant(tweet, players) {
  const context = tweetContext(tweet);
  if ([...TEAM_TERMS, ...RED_SOX_LINK_TERMS].some(term => context.includes(term))) return true;
  if (NON_REDSOX_TERMS.some(term => context.includes(term))) return false;
  for (const term of players) {
    const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (new RegExp(`(^|[^\\w])${escaped}([^\\w]|$)`).test(context)) return true;
  }
  return false;
}

function postFromTweet(tweet) {
  const text = cleanText(tweet.full_text || tweet.text);
  const user = tweet.user || {};
  const handle = cleanText(user.screen_name);
  const permalink = cleanText(tweet.permalink);
  if (!text || !handle || !permalink) return null;
  const quoted = tweet.quoted_status || {};
  const quotedUser = quoted.user || {};
  const publishedDate = new Date(cleanText(tweet.created_at));
  return {
    id: cleanText(tweet.id_str), text, url: `https://x.com${permalink}`,
    published: Number.isNaN(publishedDate.valueOf()) ? cleanText(tweet.created_at) : publishedDate.toISOString(),
    likes: Number(tweet.favorite_count || 0), author: cleanText(user.name) || handle, handle,
    avatar: cleanText(user.profile_image_url_https),
    media: cleanText(tweet.extended_entities?.media?.[0]?.media_url_https),
    quoted_text: cleanText(quoted.full_text || quoted.text),
    quoted_author: cleanText(quotedUser.name), quoted_handle: cleanText(quotedUser.screen_name),
  };
}

function buildFeed(entries, players) {
  const seen = new Set();
  const posts = [];
  for (const entry of entries) {
    const tweet = entry.content?.tweet || {};
    if (!tweet.id_str || !relevant(tweet, players)) continue;
    const post = postFromTweet(tweet);
    if (!post || seen.has(post.id)) continue;
    seen.add(post.id);
    posts.push(post);
  }
  if (!posts.length) throw new Error('The Red Sox relevance filter removed every X post');
  posts.sort((a, b) => b.published.localeCompare(a.published));
  const cutoff = Date.now() - 24 * 60 * 60 * 1000;
  const popular = posts
    .filter(post => new Date(post.published).valueOf() >= cutoff)
    .sort((a, b) => b.likes - a.likes || b.published.localeCompare(a.published));
  return {
    generated_at: new Date().toISOString(), source: 'X', source_url: `https://x.com/i/lists/${LIST_ID}`,
    recent: posts.slice(0, 24), popular: popular.slice(0, 12),
  };
}

export default async () => {
  try {
    const [listHtml, rosterJson] = await Promise.all([
      fetchText(LIST_URL, '__NEXT_DATA__'), fetchText(ROSTER_URL, '"roster"'),
    ]);
    const match = listHtml.match(/<script[^>]*id=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)<\/script>/i);
    if (!match) throw new Error('X list response did not contain timeline data');
    const listPayload = JSON.parse(match[1]);
    const entries = listPayload.props?.pageProps?.timeline?.entries || [];
    const feed = buildFeed(entries, rosterTerms(JSON.parse(rosterJson)));
    return Response.json(feed, { headers: {
      'Cache-Control': 'public, max-age=60, stale-while-revalidate=60',
      'Netlify-CDN-Cache-Control': 'public, durable, max-age=300, stale-while-revalidate=60',
    } });
  } catch (error) {
    console.error('X feed refresh failed', error);
    return Response.json({ error: 'The live X feed is temporarily unavailable.' }, {
      status: 502, headers: { 'Cache-Control': 'no-store' },
    });
  }
};

export const config = { path: '/api/x-posts', method: 'GET' };
