const status = document.getElementById('scheduleStatus');
const schedulePanel = document.getElementById('schedulePanel');
const scheduleGrid = document.getElementById('scheduleGrid');

function addText(parent, tag, className, text) {
  const element = document.createElement(tag);
  element.className = className;
  element.textContent = text;
  parent.appendChild(element);
  return element;
}

function gameDate(value, options) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.valueOf())) return '';
  return date.toLocaleString(undefined, options);
}

function dateLabel(game) {
  return gameDate(game.game_date, { weekday: 'short', month: 'short', day: 'numeric' });
}

function timeLabel(game) {
  return gameDate(game.game_date, { hour: 'numeric', minute: '2-digit' });
}

function locationLabel(game) {
  return game.location === 'home' ? 'vs.' : 'at';
}

function gameUrl(game) {
  return `https://www.mlb.com/gameday/${game.game_pk}`;
}

function makeGameRow(game, index) {
  const item = document.createElement('li');
  item.className = index === 0 ? 'schedule-row next' : 'schedule-row';

  const link = document.createElement('a');
  link.className = 'schedule-row-link';
  link.href = gameUrl(game);
  link.target = '_blank';
  link.rel = 'noreferrer noopener';

  const date = document.createElement('div');
  date.className = 'schedule-row-date';
  addText(date, 'span', '', dateLabel(game));
  addText(date, 'strong', '', timeLabel(game));

  const details = document.createElement('div');
  details.className = 'schedule-row-details';
  const matchup = document.createElement('div');
  matchup.className = 'schedule-row-matchup';
  addText(matchup, 'span', 'schedule-row-location', locationLabel(game));
  addText(matchup, 'strong', '', game.opponent);
  addText(matchup, 'span', 'schedule-row-record', game.opponent_record);
  if (game.doubleheader) addText(matchup, 'span', 'schedule-row-dh', `DH Game ${game.game_number}`);

  details.appendChild(matchup);
  if (game.show_probables || game.red_sox_pitcher || game.opponent_pitcher) {
    const pitchers = document.createElement('div');
    pitchers.className = 'schedule-row-pitchers';
    addText(pitchers, 'span', 'pitching-label', 'Projected starters');
    addText(
      pitchers,
      'span',
      '',
      `${game.red_sox_pitcher || 'TBD'} vs. ${game.opponent_pitcher || 'TBD'}`,
    );
    addText(pitchers, 'span', 'schedule-row-venue', game.venue);
    details.appendChild(pitchers);
  }

  link.append(date, details);
  addText(link, 'span', 'schedule-row-arrow', '↗').setAttribute('aria-hidden', 'true');
  item.appendChild(link);
  return item;
}

async function loadSchedule() {
  try {
    const response = await fetch('../data/schedule.json', { cache: 'no-store' });
    if (!response.ok) throw new Error(`Schedule request returned ${response.status}`);
    const feed = await response.json();
    if (!Array.isArray(feed.games)) throw new Error('Upcoming schedule was invalid');
    if (!feed.games.length) {
      const year = String(feed.regular_season_end || '').slice(0, 4);
      status.textContent = `The ${year ? `${year} ` : ''}regular season schedule is complete.`;
      return;
    }
    const fragment = document.createDocumentFragment();
    feed.games.forEach((game, index) => fragment.appendChild(makeGameRow(game, index)));
    scheduleGrid.replaceChildren(fragment);
    schedulePanel.hidden = false;
    status.hidden = true;
  } catch (error) {
    console.error(error);
    status.textContent = 'The upcoming schedule could not be loaded right now. Please try again soon.';
  }
}

await loadSchedule();
setInterval(() => {
  if (document.visibilityState === 'visible') loadSchedule();
}, 300_000);
