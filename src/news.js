const status = document.getElementById('newsStatus');
const list = document.getElementById('newsList');
const freshness = document.getElementById('newsFreshness');
const panel = document.getElementById('newsPanel');
const sourceTabs = [...document.querySelectorAll('.newspaper-tab')];
let activeConfig = null;
let currentGeneration = '';
let loadSequence = 0;

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

function makeArticle(article, index, config) {
  const item = document.createElement('li');
  item.className = 'news-item';

  const link = document.createElement('a');
  link.className = 'news-card';
  link.href = article.url;
  link.target = '_blank';
  link.rel = 'noreferrer noopener';
  link.setAttribute('aria-label', `${article.title} — read at ${config.source}`);

  addTextElement(link, 'span', 'news-number', String(index + 1).padStart(2, '0'));
  const body = document.createElement('div');
  const meta = document.createElement('div');
  meta.className = 'news-meta';
  addTextElement(meta, 'span', 'news-category', article.category || config.defaultCategory);
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

function renderFeed(feed, config) {
  if (feed.generated_at === currentGeneration) return;

  const fragment = document.createDocumentFragment();
  feed.articles.forEach((article, index) => fragment.appendChild(makeArticle(article, index, config)));
  list.replaceChildren(fragment);
  list.hidden = false;
  status.hidden = true;
  currentGeneration = feed.generated_at || '';

  const updated = formatDate(feed.generated_at, {
    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'
  });
  freshness.textContent = updated ? `Updated ${updated}` : '';
}

function configFromTab(tab) {
  return {
    key: tab.dataset.sourceKey,
    feed: tab.dataset.feed,
    source: tab.dataset.source,
    defaultCategory: tab.dataset.defaultCategory || 'Red Sox',
  };
}

async function loadFeed(config = activeConfig) {
  if (!config) return;
  const sequence = ++loadSequence;
  try {
    if (!config.feed || !config.source) throw new Error('Headline source configuration is missing');
    const response = await fetch(config.feed, { cache: 'no-store' });
    if (!response.ok) throw new Error(`Headline request returned ${response.status}`);
    const feed = await response.json();
    if (!Array.isArray(feed.articles) || !feed.articles.length) {
      throw new Error('Headline feed was empty');
    }
    if (sequence !== loadSequence || activeConfig?.key !== config.key) return;
    renderFeed(feed, config);
  } catch (error) {
    console.error(error);
    if (sequence === loadSequence && !currentGeneration) {
      status.textContent = `${config.source || 'The headline source'} could not be loaded right now. Please try again soon.`;
    }
  }
}

async function selectSource(key, updateUrl = true) {
  const selectedTab = sourceTabs.find(tab => tab.dataset.sourceKey === key) || sourceTabs[0];
  if (!selectedTab) return;

  sourceTabs.forEach(tab => {
    const selected = tab === selectedTab;
    tab.classList.toggle('active', selected);
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
  });

  activeConfig = configFromTab(selectedTab);
  panel.setAttribute('aria-labelledby', selectedTab.id);
  currentGeneration = '';
  list.replaceChildren();
  list.hidden = true;
  freshness.textContent = '';
  status.textContent = `Loading ${activeConfig.source} headlines…`;
  status.hidden = false;

  if (updateUrl) {
    const url = new URL(location.href);
    if (activeConfig.key === 'globe') url.searchParams.delete('source');
    else url.searchParams.set('source', activeConfig.key);
    history.replaceState(null, '', url);
  }

  await loadFeed(activeConfig);
}

sourceTabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectSource(tab.dataset.sourceKey));
  tab.addEventListener('keydown', event => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    const direction = event.key === 'ArrowRight' ? 1 : -1;
    const nextTab = sourceTabs[(index + direction + sourceTabs.length) % sourceTabs.length];
    nextTab.focus();
    selectSource(nextTab.dataset.sourceKey);
  });
});

const requestedSource = new URLSearchParams(location.search).get('source');
await selectSource(requestedSource === 'herald' ? 'herald' : 'globe', false);

// A reader can leave this tab open during a game or news cycle. Check the
// generated feed periodically so a Netlify refresh appears without a reload.
setInterval(() => {
  if (document.visibilityState === 'visible') loadFeed();
}, 60_000);
