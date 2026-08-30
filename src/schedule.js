const status = document.getElementById('scheduleStatus');
const schedulePanel = document.getElementById('schedulePanel');
const scheduleGrid = document.getElementById('scheduleGrid');
const completedGames = new Set();
let savedFeed;
let loading = false;

async function fetchJSON(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch(url, { cache: 'no-store', signal: controller.signal });
    if (!response.ok) throw new Error(`Schedule request returned ${response.status}`);
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

async function checkCompletedGames(games) {
  const ids = games.map(game => game.game_pk).filter(Number.isInteger);
  if (!ids.length) return;
  const query = new URLSearchParams({
    sportId: '1',
    gamePks: ids.join(','),
    fields: 'dates,games,gamePk,status,abstractGameState,detailedState',
  });
  const live = await fetchJSON(`https://statsapi.mlb.com/api/v1/schedule?${query}`);
  if (!Array.isArray(live.dates)) throw new Error('Live schedule was invalid');
  for (const date of live.dates) {
    for (const game of date.games || []) {
      if (game.status?.abstractGameState === 'Final') completedGames.add(game.gamePk);
    }
  }
}

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
  if (loading) return;
  loading = true;
  try {
    try {
      const feed = await fetchJSON('../data/schedule.json');
      if (!Array.isArray(feed.games)) throw new Error('Upcoming schedule was invalid');
      savedFeed = feed;
    } catch (error) {
      if (!savedFeed) throw error;
      console.warn(error);
    }
    const feed = savedFeed;
    let liveUnavailable = false;
    try {
      await checkCompletedGames(feed.games);
    } catch (error) {
      console.warn(error);
      liveUnavailable = true;
    }
    // Remember finals so an older snapshot or a failed live check cannot
    // bring a completed game back. Never infer completion from start time.
    for (const game of feed.games) {
      if (/^(Final|Game Over|Completed Early)\b/i.test(game.status || '')) {
        completedGames.add(game.game_pk);
      }
    }
    const games = feed.games.filter(game => !completedGames.has(game.game_pk));
    const fragment = document.createDocumentFragment();
    games.forEach((game, index) => fragment.appendChild(makeGameRow(game, index)));
    scheduleGrid.replaceChildren(fragment);
    schedulePanel.hidden = !games.length;
    status.hidden = games.length > 0 && !liveUnavailable;
    if (!games.length) {
      const year = String(feed.regular_season_end || '').slice(0, 4);
      status.textContent = `The ${year ? `${year} ` : ''}regular season schedule is complete.`;
    } else if (liveUnavailable) {
      status.textContent = 'Showing the saved schedule. Live game status is temporarily unavailable.';
    }
  } catch (error) {
    console.error(error);
    status.hidden = false;
    status.textContent = 'The upcoming schedule could not be loaded right now. Please try again soon.';
  } finally {
    loading = false;
  }
}

await loadSchedule();
function refreshVisibleSchedule() {
  if (document.visibilityState === 'visible') loadSchedule();
}
setInterval(refreshVisibleSchedule, 60_000);
document.addEventListener('visibilitychange', refreshVisibleSchedule);
window.addEventListener('focus', refreshVisibleSchedule);
