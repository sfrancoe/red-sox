// Story: Four Roads, One Record.
// Presentation config (colors, arc labels, narrative beats) + data wiring.
//
// Every beat below states something the data can be checked against — run
// `python3 scripts/story_facts.py` after a data refresh and make sure the peaks,
// valleys, streaks and records still say what these lines claim.
import { initStory } from '../../src/chart.js';

const CONFIG = {
  2023:{color:'#087ea4',label:'The Grind',beats:[
    {g:0,t:'2023 · The steady climb begins.'},
    {g:13,t:'Two weeks in — three games under. A soft open.'},
    {g:35,t:'An 8-game winning streak lifts them to +7.'},
    {g:103,t:'Cresting at +9 — the season high.'},
    {g:108,t:'Checkpoint: 57–51. No drama — just a grind.'},
    {g:159,t:'The floor gives way: seven under, the season low.'},
    {g:162,t:'Fade to 78–84. Last place in the AL East.'}]},
  2024:{color:'#9a6700',label:'The Flatline',beats:[
    {g:0,t:'2024 · Life on the .500 tightrope.'},
    {g:46,t:'The season low is just two games under. That is the whole drama.'},
    {g:96,t:'A late surge to +10 — the high-water mark.'},
    {g:108,t:'Checkpoint: 57–51. The exact same number, again.'},
    {g:140,t:'A five-game slide erases the cushion.'},
    {g:162,t:'Dead even: 81–81.'}]},
  2025:{color:'#7753c7',label:'The Bounce-Back',beats:[
    {g:0,t:'2025 · The best of the four — it just hid it early.'},
    {g:63,t:'Season low: five games under, and sinking.'},
    {g:83,t:'A six-game skid — the worst stretch of the year.'},
    {g:98,t:'The answer: ten wins in a row.'},
    {g:108,t:'Checkpoint: 57–51 too.'},
    {g:140,t:'+16 — the season high, and clear of the pack.'},
    {g:162,t:'89–73. A Wild Card berth.'}]},
  2026:{color:'#d52c3a',label:'The Rollercoaster',beats:[
    {g:0,t:'2026 · Buckle up.'},
    {g:6,t:'Five straight losses out of the gate.'},
    {g:72,t:'Rock bottom — FOURTEEN games under .500.'},
    {g:95,t:'Then the turn: ten wins in a row.'},
    {g:108,t:'Checkpoint: 57–51 — the same number, a fourth straight year.'}]}
};
const YEARS = [2023, 2024, 2025, 2026];

const DATA = await fetch('../../data/seasons.json?v=20260827-whip').then(r => r.json());

// A portable single-file build has no site root to return to.
if (location.protocol === 'file:') {
  document.querySelector('.site-header')?.setAttribute('hidden', '');
  document.documentElement.style.setProperty('--site-header-height', '0px');
}

const leaderLabels = [
  ['WAR', 'war_leader'],
  ['WHIP', 'whip'],
  ['HR', 'hr'],
  ['AVG', 'avg'],
  ['OPS', 'ops'],
  ['RBI', 'rbi'],
];

function leaderEntries(season, key) {
  if (key === 'war_leader') {
    const leaders = season.war_leaders || (season.war_leader ? [season.war_leader] : []);
    return leaders.map(leader => ({ name: leader.name, value: leader.war.toFixed(1) }));
  }
  if (key === 'whip') {
    return season.pitching_leaders?.whip?.top || [];
  }
  const category = season.batting_leaders?.[key];
  if (!category) return [];
  return category.top || category.names.map(name => ({ name, value: category.value }));
}

function leaderList(season, key) {
  const entries = leaderEntries(season, key);
  if (!entries.length) return document.createTextNode('—');
  const list = document.createElement('ol');
  list.className = 'leader-ranking';
  for (const entry of entries) {
    const item = document.createElement('li');
    const text = document.createElement('span');
    text.textContent = `${entry.name} · ${entry.value}`;
    item.appendChild(text);
    list.appendChild(item);
  }
  return list;
}

const leadersBody = document.getElementById('leadersBody');
const leaderYears = [...YEARS].sort((a, b) => {
  const currentFirst = Number(DATA[String(b)]?.in_progress) - Number(DATA[String(a)]?.in_progress);
  return currentFirst || b - a;
});
for (const year of leaderYears) {
  const season = DATA[String(year)];
  const row = document.createElement('tr');
  row.style.setProperty('--seasoncol', CONFIG[year].color);
  const yearCell = document.createElement('th');
  yearCell.scope = 'row';
  yearCell.textContent = season.in_progress ? `${year} YTD` : year;
  row.appendChild(yearCell);
  for (const [label, key] of leaderLabels) {
    const cell = document.createElement('td');
    cell.dataset.label = label;
    cell.appendChild(leaderList(season, key));
    row.appendChild(cell);
  }
  leadersBody.appendChild(row);
}

const liveSeason = YEARS.map(year => DATA[String(year)]).find(season => season.in_progress);
if (liveSeason?.last_game_date) {
  const through = new Date(`${liveSeason.last_game_date}T12:00:00`);
  const date = through.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  document.getElementById('leadersNote').prepend(`Live-season statistics through ${date}. `);
}

// The live season's closing beat has to come from the data, not from a hardcoded
// string — the daily refresh moves it, and a stale record on screen is exactly the
// kind of quiet wrongness this project is trying to avoid.
for (const year of YEARS) {
  const season = DATA[String(year)];
  if (!season?.in_progress) continue;
  CONFIG[year].beats.push({
    g: season.end_game,
    t: `Still being written: ${season.record.replace('-', '–')} through ${season.end_game} games.`,
  });
}

const story = initStory({ DATA, CONFIG, YEARS });

const tabs = [document.getElementById('storyTab'), document.getElementById('leadersTab')];
const stage = document.getElementById('stage');
const leadersPanel = document.getElementById('leadersPanel');

function selectView(view, focus = false) {
  const showLeaders = view === 'leaders';
  tabs[0].classList.toggle('active', !showLeaders);
  tabs[0].setAttribute('aria-pressed', String(!showLeaders));
  tabs[0].tabIndex = showLeaders ? -1 : 0;
  tabs[1].classList.toggle('active', showLeaders);
  tabs[1].setAttribute('aria-pressed', String(showLeaders));
  tabs[1].tabIndex = showLeaders ? 0 : -1;
  stage.hidden = showLeaders;
  leadersPanel.hidden = !showLeaders;
  if (showLeaders) {
    document.getElementById('playOverlay')?.remove();
    story.pause();
  }
  if (location.protocol !== 'file:') {
    const url = new URL(location.href);
    if (showLeaders) url.searchParams.set('view', 'leaders');
    else url.searchParams.delete('view');
    history.replaceState(null, '', url);
  }
  window.scrollTo(0, 0);
  if (focus) tabs[showLeaders ? 1 : 0].focus();
}

tabs[0].addEventListener('click', () => selectView('story'));
tabs[1].addEventListener('click', () => selectView('leaders'));
tabs.forEach((tab, index) => {
  tab.tabIndex = index === 0 ? 0 : -1;
  tab.addEventListener('keydown', event => {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    const leaders = event.key === 'ArrowRight' || event.key === 'End';
    selectView(leaders ? 'leaders' : 'story', true);
  });
});

const requestedView = new URLSearchParams(location.search).get('view');
if (requestedView === 'leaders') selectView('leaders');
