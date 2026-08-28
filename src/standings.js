const status = document.getElementById('standingsStatus');
const divisionGrid = document.getElementById('divisionGrid');
const wildCardTable = document.getElementById('wildCardTable');
const panels = [...document.querySelectorAll('.standings-panel')];
const tabs = [...document.querySelectorAll('.standings-tab')];

function cell(tag, text, className = '') {
  const element = document.createElement(tag);
  element.className = className;
  element.textContent = text;
  return element;
}

function selectView(targetId, focus = false) {
  const selected = tabs.find(tab => tab.dataset.target === targetId) || tabs[0];
  tabs.forEach(tab => {
    const active = tab === selected;
    tab.classList.toggle('active', active);
    tab.setAttribute('aria-selected', String(active));
    tab.tabIndex = active ? 0 : -1;
  });
  panels.forEach(panel => {
    panel.hidden = panel.id !== selected.dataset.target;
  });
  if (focus) selected.focus();
}

tabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectView(tab.dataset.target));
  tab.addEventListener('keydown', event => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    const direction = event.key === 'ArrowRight' ? 1 : -1;
    const next = tabs[(index + direction + tabs.length) % tabs.length];
    selectView(next.dataset.target, true);
  });
});

function standingsTable(teams, gamesBackKey, cutoff = false) {
  const table = document.createElement('table');
  table.className = 'standings-table';

  const head = document.createElement('thead');
  const headRow = document.createElement('tr');
  ['#', 'Team', 'W', 'L', 'PCT', gamesBackKey === 'games_back' ? 'GB' : 'WCGB', 'L10', 'STRK']
    .forEach((label, index) => headRow.appendChild(cell('th', label, index === 1 ? 'team-cell' : '')));
  head.appendChild(headRow);

  const body = document.createElement('tbody');
  teams.forEach(team => {
    const row = document.createElement('tr');
    if (team.is_red_sox) row.classList.add('red-sox');
    if (cutoff && Number(team.rank) === 4) row.classList.add('outside-cutoff');
    row.appendChild(cell('td', team.rank, 'rank-cell'));
    const teamCell = cell('th', team.short_name, 'team-cell');
    teamCell.scope = 'row';
    teamCell.title = team.name;
    row.appendChild(teamCell);
    row.appendChild(cell('td', team.wins));
    row.appendChild(cell('td', team.losses));
    row.appendChild(cell('td', team.pct));
    row.appendChild(cell('td', team[gamesBackKey] === '-' ? '—' : team[gamesBackKey], 'games-back-cell'));
    row.appendChild(cell('td', team.last_ten));
    row.appendChild(cell('td', team.streak, team.streak.startsWith('W') ? 'winning-streak' : ''));
    body.appendChild(row);
  });
  table.append(head, body);
  return table;
}

function divisionCard(division) {
  const card = document.createElement('article');
  card.className = 'standings-card';
  const header = document.createElement('header');
  header.className = 'standings-card-head';
  const heading = document.createElement('h2');
  heading.textContent = division.name;
  header.appendChild(heading);
  card.append(header, standingsTable(division.teams, 'games_back'));
  return card;
}

function updatedLabel(value) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.valueOf())) return '';
  return `Updated ${date.toLocaleString(undefined, {
    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  })}.`;
}

async function loadStandings() {
  try {
    const response = await fetch('../data/standings.json', { cache: 'no-store' });
    if (!response.ok) throw new Error(`Standings request returned ${response.status}`);
    const feed = await response.json();
    if (!Array.isArray(feed.divisions) || !Array.isArray(feed.wild_card)) {
      throw new Error('Standings data was incomplete');
    }
    divisionGrid.replaceChildren(...feed.divisions.map(divisionCard));
    wildCardTable.replaceChildren(standingsTable(feed.wild_card, 'wild_card_games_back', true));
    document.getElementById('standingsKicker').textContent = `${feed.season} American League`;
    document.getElementById('standingsUpdated').textContent = updatedLabel(feed.generated_at);
    status.hidden = true;
    const requested = new URLSearchParams(location.search).get('view');
    selectView(requested === 'wild-card' ? 'wildCardPanel' : 'divisionsPanel');
  } catch (error) {
    console.error(error);
    status.textContent = 'The standings could not be loaded right now. Please try again soon.';
  }
}

await loadStandings();
setInterval(() => {
  if (document.visibilityState === 'visible') loadStandings();
}, 300_000);
