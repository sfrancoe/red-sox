const status = document.getElementById('recentGameStatus');
const summary = document.getElementById('recentGameSummary');
const gameDetails = document.getElementById('gameDetails');
const lineScoreSection = document.getElementById('lineScoreSection');
const boxscoreSection = document.getElementById('boxscoreSection');
const boxTabs = [...document.querySelectorAll('.boxscore-mobile-tab')];
const boxPanels = [...document.querySelectorAll('.boxscore-team')];

function addText(parent, tag, className, text) {
  const element = document.createElement(tag);
  element.className = className;
  element.textContent = text;
  parent.appendChild(element);
  return element;
}

function selectBox(targetId, focus = false) {
  const selected = boxTabs.find(tab => tab.dataset.target === targetId) || boxTabs[0];
  boxTabs.forEach(tab => {
    const active = tab === selected;
    tab.classList.toggle('active', active);
    tab.setAttribute('aria-selected', String(active));
    tab.tabIndex = active ? 0 : -1;
  });
  boxPanels.forEach(panel => panel.classList.toggle('mobile-active', panel.id === selected.dataset.target));
  if (focus) selected.focus();
}

boxTabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectBox(tab.dataset.target));
  tab.addEventListener('keydown', event => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    const direction = event.key === 'ArrowRight' ? 1 : -1;
    const next = boxTabs[(index + direction + boxTabs.length) % boxTabs.length];
    selectBox(next.dataset.target, true);
  });
});

function renderDetails(feed) {
  const plays = document.getElementById('scoringPlays');
  plays.replaceChildren(...feed.scoring_plays.map(play => {
    const item = document.createElement('li');
    addText(item, 'div', 'scoring-inning', play.inning);
    addText(item, 'p', '', play.description);
    addText(item, 'strong', 'scoring-score', `${feed.away.abbreviation} ${play.away_score} · ${feed.home.abbreviation} ${play.home_score}`);
    return item;
  }));
  gameDetails.hidden = false;
}

function makeCell(tag, text, className = '') {
  const cell = document.createElement(tag);
  cell.className = className;
  cell.textContent = text;
  return cell;
}

function renderLineScore(feed) {
  const table = document.getElementById('lineScore');
  const head = document.createElement('thead');
  const headRow = document.createElement('tr');
  headRow.appendChild(makeCell('th', 'Team', 'team-cell'));
  feed.innings.forEach(inning => headRow.appendChild(makeCell('th', inning.num)));
  ['R', 'H', 'E'].forEach(label => headRow.appendChild(makeCell('th', label, 'total-cell')));
  head.appendChild(headRow);

  const body = document.createElement('tbody');
  [feed.away, feed.home].forEach(team => {
    const row = document.createElement('tr');
    row.appendChild(makeCell('th', team.abbreviation, 'team-cell'));
    feed.innings.forEach(inning => {
      const value = inning[team.side]?.runs;
      row.appendChild(makeCell('td', value === undefined ? '—' : value));
    });
    [team.runs, team.hits, team.errors].forEach(value => row.appendChild(makeCell('td', value, 'total-cell')));
    body.appendChild(row);
  });
  table.replaceChildren(head, body);
  const link = document.getElementById('gamedayLink');
  link.href = feed.gameday_url;
  lineScoreSection.hidden = false;
}

function statsTable(headers, rows, values) {
  const wrap = document.createElement('div');
  wrap.className = 'table-scroll';
  const table = document.createElement('table');
  table.className = 'stats-table';
  const head = document.createElement('thead');
  const headRow = document.createElement('tr');
  headers.forEach((label, index) => headRow.appendChild(makeCell('th', label, index === 0 ? 'player-cell' : '')));
  head.appendChild(headRow);
  const body = document.createElement('tbody');
  rows.forEach(rowData => {
    const row = document.createElement('tr');
    values(rowData).forEach((value, index) => row.appendChild(makeCell(index === 0 ? 'th' : 'td', value, index === 0 ? 'player-cell' : '')));
    body.appendChild(row);
  });
  table.append(head, body);
  wrap.appendChild(table);
  return wrap;
}

function renderTeamBox(team, targetId, tabId) {
  document.getElementById(tabId).textContent = team.abbreviation;
  const panel = document.getElementById(targetId);
  const header = document.createElement('header');
  addText(header, 'h3', '', team.name);
  addText(header, 'span', '', `${team.record} · ${team.runs} R · ${team.hits} H · ${team.errors} E`);

  const battingTitle = addText(panel, 'h4', '', 'Batting');
  battingTitle.id = `${targetId}Batting`;
  const batting = statsTable(
    ['Player', 'Pos', 'AB', 'R', 'H', 'RBI', 'BB', 'SO', 'LOB'],
    team.batting,
    row => [row.name, row.position, row.atBats, row.runs, row.hits, row.rbi, row.baseOnBalls, row.strikeOuts, row.leftOnBase],
  );
  const pitchingTitle = document.createElement('h4');
  pitchingTitle.textContent = 'Pitching';
  const pitching = statsTable(
    ['Pitcher', 'Dec', 'IP', 'H', 'R', 'ER', 'BB', 'SO', 'HR', 'NP'],
    team.pitching,
    row => [row.name, row.note, row.inningsPitched, row.hits, row.runs, row.earnedRuns, row.baseOnBalls, row.strikeOuts, row.homeRuns, row.numberOfPitches],
  );
  panel.replaceChildren(header, battingTitle, batting, pitchingTitle, pitching);
}

async function loadGame() {
  try {
    const response = await fetch('../data/recent-game.json', { cache: 'no-store' });
    if (!response.ok) throw new Error(`Recent game request returned ${response.status}`);
    const feed = await response.json();
    if (!feed.game_pk || !feed.away || !feed.home) throw new Error('Recent game data was incomplete');
    status.textContent = `${feed.away.name} ${feed.away.runs}, ${feed.home.name} ${feed.home.runs}`;
    summary.textContent = feed.summary;
    renderDetails(feed);
    renderLineScore(feed);
    renderTeamBox(feed.away, 'awayBox', 'awayBoxTab');
    renderTeamBox(feed.home, 'homeBox', 'homeBoxTab');
    selectBox(feed.away.id === 111 ? 'awayBox' : 'homeBox');
    boxscoreSection.hidden = false;
  } catch (error) {
    console.error(error);
    status.textContent = 'The most recent score could not be loaded right now.';
    summary.textContent = '';
  }
}

await loadGame();
setInterval(() => {
  if (document.visibilityState === 'visible') loadGame();
}, 300_000);
