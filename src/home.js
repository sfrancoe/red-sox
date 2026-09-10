import { fetchHomeGame } from './home-game.js';

const SOX_ID = 111;
const json = async (url, allowFailure = false) => {
  const response = await fetch(url);
  if (!response.ok) {
    if (allowFailure) return null;
    throw new Error(`${url} returned ${response.status}`);
  }
  return response.json();
};
const escapeHtml = value => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#039;');
const signed = value => value > 0 ? `+${value}` : String(value);
const american = value => Number.isFinite(value) ? signed(value) : '—';

function matchingOdds(game, feed) {
  if (!feed?.games) return null;
  const gameTime = new Date(game.game_date).valueOf();
  return feed.games.find(line => {
    const lineTime = new Date(line.gameDate).valueOf();
    const teams = `${line.homeTeam} ${line.awayTeam}`.toLowerCase();
    return Number.isFinite(lineTime) && Math.abs(lineTime - gameTime) < 8 * 60 * 60 * 1000 && teams.includes(game.opponent.toLowerCase());
  });
}

let scheduleFeed = null;
let oddsFeed = null;
let currentGamePk = null;
let renderedGameContent = '';
let excludedScheduleGamePk = null;

function renderResult(game, live = false) {
  const sox = game.away.id === SOX_ID ? game.away : game.home;
  const opponent = game.away.id === SOX_ID ? game.home : game.away;
  const date = new Date(game.game_date).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  const card = document.getElementById('lastGame');
  const isLive = live && game.is_live;
  const result = live ? (isLive ? 'Live' : 'Final') : game.result;
  const gameState = live ? game.status : 'Final';
  const content = JSON.stringify([game.game_pk, game.game_date, game.venue, game.away, game.home, result, gameState]);
  if (content === renderedGameContent) return;
  card.href = live ? game.gameday_url : 'recent-game/';
  if (live) {
    card.target = '_blank';
    card.rel = 'noreferrer noopener';
  } else {
    card.removeAttribute('target');
    card.removeAttribute('rel');
  }
  card.classList.toggle('is-live', isLive);
  card.innerHTML = `
    <span class="result-head"><strong>${live ? 'Today’s game' : 'Last game'}</strong><span class="result-pill">${escapeHtml(result)}</span><time>${escapeHtml(date)}</time></span>
    <span class="scoreboard">
      <span class="score-team is-sox"><span class="club"><strong>${escapeHtml(sox.abbreviation)}</strong><small>${escapeHtml(sox.record)}</small></span><span class="score">${sox.runs}</span></span>
      <span class="game-state">${escapeHtml(gameState)}</span>
      <span class="score-team"><span class="club"><strong>${escapeHtml(opponent.abbreviation)}</strong><small>${escapeHtml(opponent.record)}</small></span><span class="score">${opponent.runs}</span></span>
    </span>
    <span class="result-foot"><span aria-hidden="true">⌖</span><span class="venue">${escapeHtml(game.venue)}</span><span class="go">${live ? 'MLB Gameday&nbsp; ↗' : 'Game center&nbsp; →'}</span></span>`;
  renderedGameContent = content;
}

function renderStanding(feed) {
  const division = feed.divisions.find(item => item.name === 'AL East');
  const sox = division?.teams.find(team => team.is_red_sox);
  if (!sox) throw new Error('Boston standing unavailable');
  const ordinal = new Intl.PluralRules('en', { type: 'ordinal' }).select(Number(sox.rank));
  const suffix = { one: 'st', two: 'nd', few: 'rd', other: 'th' }[ordinal];
  document.getElementById('standingSummary').innerHTML = `
    <span class="metric"><span>AL East</span><strong>${escapeHtml(sox.rank)}${suffix}</strong></span>
    <span class="metric"><span>Record</span><strong>${sox.wins}–${sox.losses}</strong></span>
    <span class="metric"><span>Games back</span><strong>${sox.games_back === '-' ? '—' : escapeHtml(sox.games_back)}</strong></span>
    <span class="metric"><span>Streak</span><strong>${escapeHtml(sox.streak)}</strong></span>`;
}

function renderSchedule(schedule, odds, excludedGamePk = null) {
  const rows = schedule.games.filter(game => game.game_pk !== excludedGamePk).slice(0, 3).map(game => {
    const date = new Date(game.game_date);
    const day = date.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
    const time = date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
    const line = matchingOdds(game, odds);
    const runLine = Number.isFinite(line?.runLine) ? `${signed(line.runLine)} ${american(line.runLinePrice)}` : '—';
    const site = game.location === 'home' ? 'Home' : 'Away';
    return `<div class="game-row">
      <div class="game-when"><strong>${escapeHtml(day)}</strong><span>${escapeHtml(time)}</span></div>
      <div class="game-opponent"><div><span class="site-pill ${game.location === 'home' ? 'is-home' : ''}">${site}</span><strong>${escapeHtml(game.opponent)}</strong></div><small>${escapeHtml(game.venue)}</small></div>
      <div class="line ${runLine === '—' ? 'empty' : ''}">${runLine}</div>
      <div class="line ${Number.isFinite(line?.moneyline) ? '' : 'empty'}">${american(line?.moneyline)}</div>
    </div>`;
  }).join('');
  document.getElementById('nextGames').innerHTML = rows || '<p class="loading-copy">No upcoming games are scheduled.</p>';
  document.getElementById('oddsStatus').textContent = odds?.available ? 'DraftKings' : 'Lines pending';
}

try {
  const [recent, schedule, standings, odds] = await Promise.all([
    json('data/recent-game.json'),
    json('data/schedule.json'),
    json('data/standings.json'),
    json('/api/redsox-odds', true),
  ]);
  scheduleFeed = schedule;
  oddsFeed = odds;
  renderResult(recent);
  renderStanding(standings);
  renderSchedule(schedule, odds);
  const when = recent.generated_at ? new Date(recent.generated_at) : null;
  if (when && !Number.isNaN(when.valueOf())) {
    document.getElementById('freshness').textContent = ` Updated ${when.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}.`;
  }
} catch {
  document.getElementById('lastGame').innerHTML = '<span class="loading-copy">The latest result is temporarily unavailable.</span>';
  document.getElementById('nextGames').innerHTML = '<p class="loading-copy">The upcoming schedule is temporarily unavailable.</p>';
  document.getElementById('standingSummary').innerHTML = '<span class="metric"><span>AL East</span><strong>Unavailable</strong></span>';
}

let liveRefreshTimer;
let refreshingLive = false;

async function refreshLiveGame() {
  if (refreshingLive || document.visibilityState !== 'visible') return;
  refreshingLive = true;
  let live = false;
  try {
    const game = await fetchHomeGame(currentGamePk);
    if (game) {
      currentGamePk = game.game_pk;
      live = game.is_live;
      renderResult(game, true);
      if (scheduleFeed && excludedScheduleGamePk !== game.game_pk) {
        renderSchedule(scheduleFeed, oddsFeed, game.game_pk);
        excludedScheduleGamePk = game.game_pk;
      }
    }
  } catch (error) {
    console.warn('Live game unavailable; keeping the saved result', error);
  } finally {
    refreshingLive = false;
    clearTimeout(liveRefreshTimer);
    liveRefreshTimer = setTimeout(refreshLiveGame, live ? 15_000 : 60_000);
  }
}

await refreshLiveGame();
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState !== 'visible') {
    clearTimeout(liveRefreshTimer);
    return;
  }
  refreshLiveGame();
});
window.addEventListener('online', refreshLiveGame);
