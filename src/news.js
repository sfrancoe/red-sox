const status = document.getElementById('newsStatus');
const list = document.getElementById('newsList');
const freshness = document.getElementById('newsFreshness');

function formatDate(value, options) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.valueOf())) return '';
  return date.toLocaleDateString(undefined, options);
}

function formatTime(value) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.valueOf())) return '';
  return date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
}

function addTextElement(parent, tag, className, text) {
  const element = document.createElement(tag);
  element.className = className;
  element.textContent = text;
  parent.appendChild(element);
  return element;
}

function makeArticle(article, index) {
  const item = document.createElement('li');
  item.className = 'news-item';

  const link = document.createElement('a');
  link.className = 'news-card';
  link.href = article.url;
  link.target = '_blank';
  link.rel = 'noreferrer noopener';
  link.setAttribute('aria-label', `${article.title} — read at The Boston Globe`);

  addTextElement(link, 'span', 'news-number', String(index + 1).padStart(2, '0'));
  const body = document.createElement('div');
  const meta = document.createElement('div');
  meta.className = 'news-meta';
  addTextElement(meta, 'span', 'news-category', article.category || 'Red Sox');
  const publishedDate = formatDate(article.published, { month: 'short', day: 'numeric' });
  const publishedTime = formatTime(article.published);
  const published = publishedDate && publishedTime ? `${publishedDate} · ${publishedTime}` : publishedDate;
  if (published) addTextElement(meta, 'span', 'news-date', published);
  body.appendChild(meta);
  addTextElement(body, 'h3', 'news-headline', article.title);
  addTextElement(body, 'p', 'news-blurb', article.description);
  link.appendChild(body);
  addTextElement(link, 'span', 'news-arrow', '↗').setAttribute('aria-hidden', 'true');
  item.appendChild(link);
  return item;
}

try {
  const response = await fetch('../data/globe.json', { cache: 'no-store' });
  if (!response.ok) throw new Error(`Headline request returned ${response.status}`);
  const feed = await response.json();
  if (!Array.isArray(feed.articles) || !feed.articles.length) {
    throw new Error('Headline feed was empty');
  }

  const fragment = document.createDocumentFragment();
  feed.articles.forEach((article, index) => fragment.appendChild(makeArticle(article, index)));
  list.appendChild(fragment);
  list.hidden = false;
  status.hidden = true;

  const updated = formatDate(feed.generated_at, {
    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'
  });
  freshness.textContent = updated ? `Updated ${updated}` : '';
} catch (error) {
  console.error(error);
  status.textContent = 'The Globe headline list could not be loaded right now. Try the Globe link above.';
}
