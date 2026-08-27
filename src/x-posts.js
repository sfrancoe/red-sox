const status = document.getElementById('xPostsStatus');
const list = document.getElementById('xPostsList');
const freshness = document.getElementById('xPostsFreshness');
let generation = '';

function addText(parent, tag, className, text) {
  const element = document.createElement(tag);
  element.className = className;
  element.textContent = text;
  parent.appendChild(element);
  return element;
}

function formatPublished(value) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.valueOf())) return '';
  return date.toLocaleString(undefined, {
    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  });
}

function makePost(post) {
  const item = document.createElement('li');
  item.className = 'x-post';
  const card = document.createElement('a');
  card.className = 'x-post-card';
  card.href = post.url;
  card.target = '_blank';
  card.rel = 'noreferrer noopener';

  if (post.avatar) {
    const avatar = document.createElement('img');
    avatar.className = 'x-post-avatar';
    avatar.src = post.avatar;
    avatar.alt = '';
    avatar.loading = 'lazy';
    card.appendChild(avatar);
  }

  const body = document.createElement('div');
  body.className = 'x-post-body';
  const authorLine = document.createElement('div');
  authorLine.className = 'x-post-author-line';
  addText(authorLine, 'strong', 'x-post-author', post.author);
  addText(authorLine, 'span', 'x-post-handle', `@${post.handle}`);
  const published = formatPublished(post.published);
  if (published) addText(authorLine, 'time', 'x-post-date', published);
  body.appendChild(authorLine);
  addText(body, 'p', 'x-post-text', post.text);

  if (post.quoted_text) {
    const quote = document.createElement('blockquote');
    quote.className = 'x-post-quote';
    const quoteBy = post.quoted_handle
      ? `${post.quoted_author || post.quoted_handle} · @${post.quoted_handle}`
      : post.quoted_author;
    if (quoteBy) addText(quote, 'div', 'x-post-quote-author', quoteBy);
    addText(quote, 'p', '', post.quoted_text);
    body.appendChild(quote);
  }

  if (post.media) {
    const image = document.createElement('img');
    image.className = 'x-post-media';
    image.src = post.media;
    image.alt = '';
    image.loading = 'lazy';
    body.appendChild(image);
  }

  card.appendChild(body);
  addText(card, 'span', 'x-post-arrow', '↗').setAttribute('aria-hidden', 'true');
  item.appendChild(card);
  return item;
}

function render(feed) {
  if (feed.generated_at === generation) return;
  const fragment = document.createDocumentFragment();
  feed.posts.forEach(post => fragment.appendChild(makePost(post)));
  list.replaceChildren(fragment);
  list.hidden = false;
  status.hidden = true;
  generation = feed.generated_at || '';
}

async function loadPosts() {
  try {
    const response = await fetch('../data/x-posts.json', { cache: 'no-store' });
    if (!response.ok) throw new Error(`X post request returned ${response.status}`);
    const feed = await response.json();
    if (!Array.isArray(feed.posts) || !feed.posts.length) throw new Error('X post feed was empty');
    freshness.textContent = `Checked ${new Date().toLocaleTimeString(undefined, {
      hour: 'numeric', minute: '2-digit',
    })}`;
    render(feed);
  } catch (error) {
    console.error(error);
    if (!generation) status.textContent = 'Red Sox X posts could not be loaded right now. Please try again soon.';
  }
}

await loadPosts();
setInterval(() => {
  if (document.visibilityState === 'visible') loadPosts();
}, 60_000);
