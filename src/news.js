const columns = [...document.querySelectorAll('.newspaper-column')].map(section => ({
  section,
  feedUrl: section.dataset.feed,
  source: section.dataset.source,
  defaultCategory: section.dataset.defaultCategory || 'Red Sox',
  status: section.querySelector('.news-status'),
  list: section.querySelector('.news-list'),
  freshness: section.querySelector('.news-freshness'),
  generation: '',
  loadSequence: 0,
}));
const mobileTabs = [...document.querySelectorAll('.mobile-newspaper-tab')];

function selectMobileColumn(targetId, updateUrl = true) {
  const selectedTab = mobileTabs.find(tab => tab.dataset.target === targetId) || mobileTabs[0];
  if (!selectedTab) return;

  mobileTabs.forEach(tab => {
    const selected = tab === selectedTab;
    tab.classList.toggle('active', selected);
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
  });
  columns.forEach(column => {
    column.section.classList.toggle('mobile-active', column.section.id === selectedTab.dataset.target);
  });

  if (updateUrl) {
    const url = new URL(location.href);
    url.hash = selectedTab.dataset.target === 'boston-herald' ? 'boston-herald' : '';
    history.replaceState(null, '', url);
  }
}

mobileTabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectMobileColumn(tab.dataset.target));
  tab.addEventListener('keydown', event => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    const direction = event.key === 'ArrowRight' ? 1 : -1;
    const nextTab = mobileTabs[(index + direction + mobileTabs.length) % mobileTabs.length];
    nextTab.focus();
    selectMobileColumn(nextTab.dataset.target);
  });
});

selectMobileColumn(location.hash === '#boston-herald' ? 'boston-herald' : 'boston-globe', false);
window.addEventListener('hashchange', () => {
  selectMobileColumn(location.hash === '#boston-herald' ? 'boston-herald' : 'boston-globe', false);
});

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

function makeArticle(article, column) {
  const item = document.createElement('li');
  item.className = 'news-item';

  const link = document.createElement('a');
  link.className = 'news-card';
  link.href = article.url;
  link.target = '_blank';
  link.rel = 'noreferrer noopener';
  link.setAttribute('aria-label', `${article.title} — read at ${column.source}`);

  const body = document.createElement('div');
  const meta = document.createElement('div');
  meta.className = 'news-meta';
  addTextElement(meta, 'span', 'news-category', article.category || column.defaultCategory);
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

function renderFeed(feed, column) {
  if (feed.generated_at === column.generation) return;

  const fragment = document.createDocumentFragment();
  feed.articles.forEach(article => fragment.appendChild(makeArticle(article, column)));
  column.list.replaceChildren(fragment);
  column.list.hidden = false;
  column.status.hidden = true;
  column.generation = feed.generated_at || '';
}

function markChecked(column) {
  const checked = formatDate(new Date(), {
    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'
  });
  column.freshness.textContent = checked ? `Checked ${checked}` : '';
}

async function loadFeed(column) {
  const sequence = ++column.loadSequence;
  try {
    if (!column.feedUrl || !column.source) throw new Error('Headline source configuration is missing');
    const response = await fetch(column.feedUrl, { cache: 'no-store' });
    if (!response.ok) throw new Error(`Headline request returned ${response.status}`);
    const feed = await response.json();
    if (!Array.isArray(feed.articles) || !feed.articles.length) {
      throw new Error('Headline feed was empty');
    }
    if (sequence !== column.loadSequence) return;
    markChecked(column);
    renderFeed(feed, column);
  } catch (error) {
    console.error(error);
    if (sequence === column.loadSequence && !column.generation) {
      column.status.textContent = `${column.source || 'The headline source'} could not be loaded right now. Please try again soon.`;
    }
  }
}

await Promise.all(columns.map(loadFeed));

// A reader can leave this page open during a game or news cycle. Check both
// generated feeds periodically so a Netlify refresh appears without a reload.
setInterval(() => {
  if (document.visibilityState === 'visible') columns.forEach(loadFeed);
}, 60_000);
