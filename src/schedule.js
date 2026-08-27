const status = document.getElementById('scheduleStatus');
const nextGame = document.getElementById('nextGame');
const followingGames = document.getElementById('followingGames');
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
  return gameDate(game.game_date, { weekday: 'long', month: 'short', day: 'numeric' });
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

function makePitchers(game, compact = false) {
  const wrap = document.createElement('div');
  wrap.className = compact ? 'pitching-matchup compact' : 'pitching-matchup';
  addText(wrap, 'div', 'pitching-label', 'Projected starters');
  const matchup = document.createElement('div');
  matchup.className = 'pitching-names';
  const redSox = document.createElement('div');
  addText(redSox, 'span', 'pitching-team', 'Boston');
  addText(redSox, 'strong', '', game.red_sox_pitcher || 'TBD');
  const divider = addText(matchup, 'span', 'pitching-vs', 'vs.');
  divider.setAttribute('aria-hidden', 'true');
  const opponent = document.createElement('div');
  addText(opponent, 'span', 'pitching-team', game.opponent);
  addText(opponent, 'strong', '', game.opponent_pitcher || 'TBD');
  matchup.prepend(redSox);
  matchup.appendChild(opponent);
  wrap.appendChild(matchup);
  return wrap;
}

function renderNext(game) {
  const top = document.createElement('div');
  top.className = 'next-game-top';
  addText(top, 'div', 'next-game-date', `${dateLabel(game)} · ${timeLabel(game)}`);
  const badges = document.createElement('div');
  badges.className = 'game-badges';
  if (game.doubleheader) addText(badges, 'span', 'game-badge', `Doubleheader · Game ${game.game_number}`);
  addText(badges, 'span', 'game-badge muted', game.status);
  top.appendChild(badges);

  const body = document.createElement('div');
  body.className = 'next-game-body';
  const matchup = document.createElement('div');
  matchup.className = 'next-matchup';
  addText(matchup, 'div', 'next-location', `${locationLabel(game)} ${game.venue}`);
  addText(matchup, 'h2', '', game.opponent);
  addText(matchup, 'div', 'opponent-record', `Opponent record · ${game.opponent_record}`);
  addText(matchup, 'div', 'sox-record', `Boston · ${game.red_sox_record}`);
  body.appendChild(matchup);
  if (game.show_probables || game.red_sox_pitcher || game.opponent_pitcher) {
    body.appendChild(makePitchers(game));
  }

  const link = document.createElement('a');
  link.className = 'gameday-link';
  link.href = gameUrl(game);
  link.target = '_blank';
  link.rel = 'noreferrer noopener';
  link.textContent = 'Open MLB Gameday ↗';

  nextGame.replaceChildren(top, body, link);
  nextGame.hidden = false;
}

function makeGameCard(game) {
  const item = document.createElement('li');
  const card = document.createElement('a');
  card.className = 'schedule-card';
  card.href = gameUrl(game);
  card.target = '_blank';
  card.rel = 'noreferrer noopener';

  const top = document.createElement('div');
  top.className = 'schedule-card-top';
  addText(top, 'span', 'schedule-card-date', dateLabel(game));
  addText(top, 'span', 'schedule-card-time', timeLabel(game));
  card.appendChild(top);

  addText(card, 'div', 'schedule-card-location', `${locationLabel(game)} ${game.venue}`);
  addText(card, 'h3', '', game.opponent);
  addText(card, 'div', 'schedule-card-record', `Opponent · ${game.opponent_record}`);
  if (game.doubleheader) addText(card, 'span', 'game-badge', `Doubleheader · Game ${game.game_number}`);
  if (game.show_probables || game.red_sox_pitcher || game.opponent_pitcher) {
    card.appendChild(makePitchers(game, true));
  }
  item.appendChild(card);
  return item;
}

async function loadSchedule() {
  try {
    const response = await fetch('../data/schedule.json', { cache: 'no-store' });
    if (!response.ok) throw new Error(`Schedule request returned ${response.status}`);
    const feed = await response.json();
    if (!Array.isArray(feed.games) || !feed.games.length) throw new Error('Upcoming schedule was empty');
    renderNext(feed.games[0]);
    const fragment = document.createDocumentFragment();
    feed.games.slice(1).forEach(game => fragment.appendChild(makeGameCard(game)));
    scheduleGrid.replaceChildren(fragment);
    followingGames.hidden = feed.games.length < 2;
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
