const status = document.getElementById('pitchingStatus');
const pitcherGrid = document.getElementById('pitcherGrid');
const canvas = document.getElementById('impactCanvas');
const context = canvas.getContext('2d');
let feed;
let plotPoints = [];
let chartFilter = 'starters';
let reportSort = 'impact';

function signed(value, places = 1) {
  const rounded = Number(value).toFixed(places);
  return `${value >= 0 ? '+' : ''}${rounded}`;
}

function percent(value) {
  return `${Number(value).toFixed(1)}%`;
}

function storyFor(pitcher) {
  const gap = pitcher.war_gap;
  const actualIp = pitcher.actual.ip;
  const expectedIp = pitcher.forecast_to_date.ip;
  const share = pitcher.innings_share_pct;
  if (gap >= 1.5) {
    return `A season-changing surprise: ${signed(gap, 1)} fWAR beyond the forecast, with ${actualIp} innings instead of the ${expectedIp.toFixed(1)} expected by now.`;
  }
  if (gap >= .5) {
    return `${signed(gap, 1)} fWAR ahead of forecast. He has covered ${percent(share)} of Boston’s innings with a ${pitcher.actual.era.toFixed(2)} ERA.`;
  }
  if (gap >= .15) {
    return `Quietly ahead of plan: ${signed(gap, 1)} fWAR, plus ${actualIp} innings that helped hold the staff together.`;
  }
  if (gap > -.15) {
    return `Almost exactly on the value forecast so far. His ${actualIp} innings account for ${percent(share)} of Boston’s total.`;
  }
  return `${Math.abs(gap).toFixed(1)} fWAR behind the forecast to this point—but still responsible for ${actualIp} innings of the season.`;
}

function statRow(label, actual, forecast, className = '') {
  const wrapper = document.createElement('div');
  if (className) wrapper.className = className;
  const term = document.createElement('dt');
  const actualValue = document.createElement('dd');
  const forecastValue = document.createElement('dd');
  term.textContent = label;
  actualValue.textContent = actual;
  forecastValue.textContent = forecast;
  wrapper.append(term, actualValue, forecastValue);
  return wrapper;
}

function pitcherCard(pitcher, rank, sort) {
  const card = document.createElement('article');
  card.className = `pitcher-card${pitcher.war_gap < 0 ? ' below' : ''}`;
  card.id = `pitcher-${pitcher.id}`;

  const header = document.createElement('header');
  header.className = 'pitcher-card__head';
  const identity = document.createElement('div');
  const rankLabel = document.createElement('span');
  rankLabel.className = 'pitcher-rank';
  const rankNames = { impact: 'Impact', surprise: 'Surprise', workload: 'Workload' };
  rankLabel.textContent = `${rankNames[sort]} rank ${rank}`;
  const heading = document.createElement('h3');
  heading.textContent = pitcher.name;
  const role = document.createElement('p');
  role.className = 'pitcher-role';
  role.textContent = `${pitcher.throws === 'L' ? 'Left' : 'Right'}-handed · ${pitcher.role} · ${pitcher.games} G${pitcher.starts ? ` · ${pitcher.starts} GS` : ''}`;
  identity.append(rankLabel, heading, role);
  const gap = document.createElement('span');
  gap.className = 'pitcher-gap';
  gap.textContent = `${signed(pitcher.war_gap, 1)} fWAR`;
  header.append(identity, gap);

  const story = document.createElement('p');
  story.className = 'pitcher-story';
  story.textContent = storyFor(pitcher);

  const scaleMax = Math.max(pitcher.actual.war, pitcher.forecast_to_date.war, .35) * 1.12;
  const trackWrap = document.createElement('div');
  const track = document.createElement('div');
  track.className = 'value-track';
  const actualBar = document.createElement('span');
  actualBar.className = 'value-track__actual';
  const forecastMark = document.createElement('span');
  forecastMark.className = 'value-track__forecast';
  actualBar.style.width = `${Math.max(0, pitcher.actual.war) / scaleMax * 100}%`;
  forecastMark.style.left = `${Math.max(0, pitcher.forecast_to_date.war) / scaleMax * 100}%`;
  track.append(actualBar, forecastMark);
  const labels = document.createElement('div');
  labels.className = 'value-track__labels';
  labels.innerHTML = '<span>0 fWAR</span><span>Actual bar · Forecast mark</span>';
  trackWrap.append(track, labels);

  const stats = document.createElement('dl');
  stats.className = 'pitcher-stats';
  stats.append(
    statRow('', 'Actual', 'Forecast', 'pitcher-stats__head'),
    statRow('fWAR', pitcher.actual.war.toFixed(2), pitcher.forecast_to_date.war.toFixed(2)),
    statRow('Innings', pitcher.actual.ip, pitcher.forecast_to_date.ip.toFixed(1)),
    statRow('ERA', pitcher.actual.era.toFixed(2), pitcher.forecast.era.toFixed(2)),
    statRow('FIP', pitcher.actual.fip.toFixed(2), pitcher.forecast.fip.toFixed(2)),
    statRow('K−BB%', percent(pitcher.actual.k_minus_bb_pct), percent(pitcher.forecast.k_minus_bb_pct)),
  );
  card.append(header, story, trackWrap, stats);
  return card;
}

function renderCards() {
  const pitchers = [...chartPitchers()];
  if (reportSort === 'surprise') pitchers.sort((a, b) => b.war_gap - a.war_gap);
  if (reportSort === 'workload') pitchers.sort((a, b) => b.actual.ip_value - a.actual.ip_value);
  if (reportSort === 'impact') pitchers.sort((a, b) => b.actual.war - a.actual.war);
  pitcherGrid.replaceChildren(...pitchers.map((pitcher, index) => pitcherCard(pitcher, index + 1, reportSort)));
  document.getElementById('reportsHeading').textContent = chartFilter === 'starters' ? 'Starter reports' : 'Reliever reports';
}

document.querySelectorAll('.report-sort button').forEach(button => {
  button.addEventListener('click', () => {
    reportSort = button.dataset.sort;
    document.querySelectorAll('.report-sort button').forEach(item => {
      const active = item === button;
      item.classList.toggle('active', active);
      item.setAttribute('aria-pressed', String(active));
    });
    renderCards();
  });
});

function isStarter(pitcher) {
  return pitcher.role === 'Starter' || pitcher.role === 'Swingman' || pitcher.starts >= 5;
}

function chartPitchers() {
  return feed.pitchers.filter(pitcher => chartFilter === 'starters' ? isStarter(pitcher) : !isStarter(pitcher));
}

document.querySelectorAll('[data-chart-filter]').forEach(button => {
  button.addEventListener('click', () => {
    chartFilter = button.dataset.chartFilter;
    document.querySelectorAll('[data-chart-filter]').forEach(item => {
      const active = item === button;
      item.classList.toggle('active', active);
      item.setAttribute('aria-pressed', String(active));
    });
    drawMap();
    updateMapDescription();
    renderCards();
  });
});

function drawMap() {
  if (!feed || !canvas.clientWidth) return;
  const ratio = Math.min(window.devicePixelRatio || 1, 2);
  const width = canvas.clientWidth;
  const height = canvas.clientHeight;
  canvas.width = Math.round(width * ratio);
  canvas.height = Math.round(height * ratio);
  context.setTransform(ratio, 0, 0, ratio, 0, 0);
  context.clearRect(0, 0, width, height);

  const mobile = width < 560;
  const pad = { left: mobile ? 42 : 58, right: mobile ? 15 : 34, top: 24, bottom: 43 };
  const plotWidth = width - pad.left - pad.right;
  const plotHeight = height - pad.top - pad.bottom;
  const visiblePitchers = chartPitchers();
  const starterView = chartFilter === 'starters';
  const forecastValues = visiblePitchers.map(pitcher => pitcher.forecast_to_date.war);
  const actualValues = visiblePitchers.map(pitcher => pitcher.actual.war);
  const min = Math.min(-.2, ...forecastValues, ...actualValues);
  const xMax = Math.max(starterView ? 4.8 : 1, ...forecastValues) * 1.08;
  const yMax = Math.max(starterView ? 3.5 : 1.6, ...actualValues) * 1.08;
  const x = value => pad.left + (value - min) / (xMax - min) * plotWidth;
  const y = value => pad.top + plotHeight - (value - min) / (yMax - min) * plotHeight;

  context.font = `600 ${mobile ? 9 : 10}px OswaldX, sans-serif`;
  context.fillStyle = '#718079';
  context.strokeStyle = '#ded8ca';
  context.lineWidth = 1;
  const yStep = yMax <= 2 ? .5 : 1;
  const xStep = xMax <= 2 ? .5 : 1;
  const tickLabel = tick => Number.isInteger(tick) ? String(tick) : tick.toFixed(1);
  for (let tick = 0; tick <= yMax; tick += yStep) {
    context.beginPath();context.moveTo(pad.left, y(tick));context.lineTo(width - pad.right, y(tick));context.stroke();
    context.fillText(tickLabel(tick), pad.left - 20, y(tick) + 3);
  }
  for (let tick = 0; tick <= xMax; tick += xStep) {
    context.fillText(tickLabel(tick), x(tick) - 3, height - pad.bottom + 18);
  }
  context.setLineDash([6, 6]);context.strokeStyle = '#76877e';context.lineWidth = 1.5;
  const parityMax = Math.min(xMax, yMax);
  context.beginPath();context.moveTo(x(min), y(min));context.lineTo(x(parityMax), y(parityMax));context.stroke();context.setLineDash([]);
  context.fillStyle = '#5f7068';context.font = `700 ${mobile ? 9 : 10}px OswaldX, sans-serif`;
  context.fillText('FORECAST fWAR BY NOW →', pad.left, height - 7);
  context.save();context.translate(11, height - pad.bottom);context.rotate(-Math.PI / 2);context.fillText('ACTUAL fWAR →', 0, 0);context.restore();

  const labelLimit = starterView ? visiblePitchers.length : (mobile ? 12 : 18);
  const labelIds = new Set([...visiblePitchers]
    .sort((a, b) => {
      const score = pitcher => pitcher.actual.war + Math.abs(pitcher.war_gap) * .9 + pitcher.actual.ip_value / 220;
      return score(b) - score(a);
    })
    .slice(0, labelLimit).map(pitcher => pitcher.id));
  plotPoints = [];
  const labelRects = [];
  [...visiblePitchers].sort((a, b) => b.actual.ip_value - a.actual.ip_value).forEach(pitcher => {
    const px = x(pitcher.forecast_to_date.war);
    const py = y(pitcher.actual.war);
    const radius = Math.min(13, 4 + Math.sqrt(pitcher.actual.ip_value) * .55);
    context.beginPath();context.arc(px, py, radius, 0, Math.PI * 2);
    context.fillStyle = pitcher.war_gap >= 0 ? 'rgba(197,46,61,.80)' : 'rgba(111,130,120,.72)';context.fill();
    context.strokeStyle = '#fffdf8';context.lineWidth = 1.5;context.stroke();
    plotPoints.push({ x: px, y: py, radius: radius + 8, pitcher });
    if (labelIds.has(pitcher.id)) {
      context.fillStyle = '#243b31';context.font = `700 ${mobile ? 9 : 10}px OswaldX, sans-serif`;
      const name = mobile ? pitcher.name.split(' ').at(-1) : pitcher.name;
      const textWidth = context.measureText(name).width;
      const labelX = px + radius + textWidth + 5 > width - pad.right
        ? px - radius - textWidth - 4
        : px + radius + 3;
      const offsets = [3, -8, 14, -19, 25];
      const labelY = offsets.map(offset => py + offset).find(candidate => {
        const rect = { left: labelX - 1, right: labelX + textWidth + 1, top: candidate - 9, bottom: candidate + 3 };
        if (rect.top < pad.top || rect.bottom > height - pad.bottom) return false;
        return !labelRects.some(placed => rect.left < placed.right && rect.right > placed.left && rect.top < placed.bottom && rect.bottom > placed.top);
      }) ?? py + 3;
      labelRects.push({ left: labelX - 1, right: labelX + textWidth + 1, top: labelY - 9, bottom: labelY + 3 });
      context.fillText(name, labelX, labelY);
    }
  });
}

function updateMapDescription() {
  if (!feed) return;
  const group = chartFilter === 'starters' ? 'Starters' : 'Relievers';
  const summary = chartPitchers()
    .slice(0, 8)
    .map(pitcher => `${pitcher.name}: ${pitcher.actual.war.toFixed(1)} actual fWAR, ${pitcher.forecast_to_date.war.toFixed(1)} forecast`)
    .join('. ');
  document.getElementById('impactMapDescription').textContent = `${group}. ${summary}`;
}

canvas.addEventListener('pointerup', event => {
  const rect = canvas.getBoundingClientRect();
  const x = event.clientX - rect.left;
  const y = event.clientY - rect.top;
  const point = [...plotPoints]
    .sort((a, b) => Math.hypot(x - a.x, y - a.y) - Math.hypot(x - b.x, y - b.y))
    .find(item => Math.hypot(x - item.x, y - item.y) <= item.radius);
  if (!point) return;
  const card = document.getElementById(`pitcher-${point.pitcher.id}`);
  if (!card) return;
  card.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' });
  card.classList.remove('is-target');
  requestAnimationFrame(() => card.classList.add('is-target'));
});

function updatedLabel(value) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.valueOf())) return '';
  return `Updated ${date.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}.`;
}

async function loadPitching() {
  try {
    const response = await fetch('../data/pitching.json', { cache: 'no-store' });
    if (!response.ok) throw new Error(`Pitching request returned ${response.status}`);
    feed = await response.json();
    if (!Array.isArray(feed.pitchers) || !feed.team_summary) throw new Error('Pitching data was incomplete');
    const summary = feed.team_summary;
    document.getElementById('actualWar').textContent = summary.actual_war.toFixed(1);
    document.getElementById('forecastWar').textContent = summary.forecast_war_to_date.toFixed(1);
    document.getElementById('teamGap').textContent = `${signed(summary.war_gap)} fWAR`;
    document.getElementById('teamStory').textContent = `Through ${feed.games_played} games, Boston’s staff is ${signed(summary.war_gap)} fWAR ahead of its prorated preseason forecast.`;
    document.getElementById('teamEra').textContent = summary.era.toFixed(2);
    document.getElementById('teamInnings').textContent = summary.innings.toFixed(1);
    document.getElementById('teamGames').textContent = feed.games_played;
    const scale = Math.max(summary.actual_war, summary.forecast_war_to_date) * 1.08;
    document.getElementById('teamTrackFill').style.width = `${summary.actual_war / scale * 100}%`;
    document.getElementById('teamTrackMark').style.left = `${summary.forecast_war_to_date / scale * 100}%`;
    updateMapDescription();
    document.getElementById('pitchingUpdated').textContent = updatedLabel(feed.generated_at);
    renderCards();
    ['forecastBoard', 'impactMapSection', 'pitcherReports', 'pitchingNote'].forEach(id => { document.getElementById(id).hidden = false; });
    status.hidden = true;
    requestAnimationFrame(drawMap);
  } catch (error) {
    console.error(error);
    status.textContent = 'The pitching forecast could not be loaded right now. Please try again soon.';
  }
}

await loadPitching();
window.addEventListener('resize', drawMap);
setInterval(() => { if (document.visibilityState === 'visible') loadPitching(); }, 300_000);
