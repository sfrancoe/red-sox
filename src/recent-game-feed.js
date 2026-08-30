// MLB -> the same presentation shape as scripts/fetch_recent_game.py.
// The scheduled JSON remains the fallback; a final no longer needs a deploy.
const API = 'https://statsapi.mlb.com';
const BOS = 111;
const LIVE_FIELDS = [
  'gamePk', 'gameData', 'datetime', 'dateTime', 'status', 'abstractGameState',
  'codedGameState', 'teams', 'away', 'home', 'id', 'name', 'teamName', 'clubName',
  'abbreviation', 'record', 'leagueRecord', 'wins', 'losses', 'venue', 'liveData',
  'linescore', 'innings', 'num', 'runs', 'hits', 'errors', 'boxscore', 'players',
  'batters', 'pitchers', 'person', 'fullName', 'position', 'stats', 'batting',
  'pitching', 'plateAppearances', 'gamesPitched', 'note', 'atBats', 'rbi',
  'baseOnBalls', 'strikeOuts', 'leftOnBase', 'inningsPitched', 'earnedRuns',
  'homeRuns', 'numberOfPitches', 'plays', 'allPlays', 'scoringPlays', 'about',
  'halfInning', 'inning', 'result', 'description', 'event', 'awayScore', 'homeScore',
].join(',');

export async function fetchJSON(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  try {
    const response = await fetch(url, { cache: 'no-store', signal: controller.signal });
    if (!response.ok) throw new Error(`Game request returned ${response.status}`);
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

function isFinal(status) {
  // Postponements/cancellations can also have abstract state "Final".
  return status?.abstractGameState === 'Final' && ['F', 'O'].includes(status.codedGameState);
}

export function latestFinal(schedule) {
  return (schedule.dates || []).flatMap(day => day.games || [])
    .filter(game => isFinal(game.status))
    .sort((a, b) => a.gameDate.localeCompare(b.gameDate) || a.gamePk - b.gamePk)
    .at(-1);
}

function playerRows(box, role) {
  const ids = box[role === 'batting' ? 'batters' : 'pitchers'] || [];
  return ids.flatMap(id => {
    const player = box.players?.[`ID${id}`];
    const stats = player?.stats?.[role];
    if (!stats?.[role === 'batting' ? 'plateAppearances' : 'gamesPitched']) return [];
    const keys = role === 'batting'
      ? ['atBats', 'runs', 'hits', 'rbi', 'baseOnBalls', 'strikeOuts', 'leftOnBase']
      : ['inningsPitched', 'hits', 'runs', 'earnedRuns', 'baseOnBalls', 'strikeOuts', 'homeRuns', 'numberOfPitches'];
    return [{
      name: player.person?.fullName || 'Player',
      position: player.position?.abbreviation || '',
      note: stats.note || '',
      ...Object.fromEntries(keys.map(key => [key, stats[key] ?? 0])),
    }];
  });
}

function ordinal(value) {
  const suffix = value % 100 > 10 && value % 100 < 14 ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' }[value % 10] || 'th');
  return `${value}${suffix}`;
}

function gameSummary(boston, opponent, venue, innings) {
  const score = `${Math.max(boston.runs, opponent.runs)}–${Math.min(boston.runs, opponent.runs)}`;
  const outcome = boston.runs > opponent.runs
    ? (opponent.runs === 0 ? 'shut out' : 'beat')
    : (boston.runs === 0 ? 'were shut out by' : 'fell to');
  const first = `The Red Sox ${outcome} the ${opponent.club_name}, ${score}, at ${venue}.`;
  const labels = innings.filter(inning => inning[opponent.side]?.runs > 0).map(inning => ordinal(inning.num));
  const joined = labels.length < 3 ? labels.join(' and ') : `${labels.slice(0, -1).join(', ')}, and ${labels.at(-1)}`;
  const totals = `${boston.hits} hit${boston.hits === 1 ? '' : 's'} and ${boston.errors} error${boston.errors === 1 ? '' : 's'}.`;
  const second = labels.length
    ? `The ${opponent.club_name} scored in the ${joined} ${labels.length === 1 ? 'inning' : 'innings'}; the Red Sox finished with ${totals}`
    : `The Red Sox finished with ${totals}`;
  return `${first} ${second}`;
}

export function validateFeed(feed) {
  if (!feed?.game_pk || !Number.isFinite(Date.parse(feed.game_date)) || typeof feed.summary !== 'string'
      || !Array.isArray(feed.innings) || !feed.innings.length || !Array.isArray(feed.scoring_plays)
      || ![feed.away?.id, feed.home?.id].includes(BOS)) {
    throw new Error('Recent game data was incomplete');
  }
  for (const team of [feed.away, feed.home]) {
    if (!team?.abbreviation || !team.name || !['runs', 'hits', 'errors'].every(key => Number.isFinite(team[key]))
        || !Array.isArray(team.batting) || !team.batting.length || !Array.isArray(team.pitching) || !team.pitching.length) {
      throw new Error('Recent game box score was incomplete');
    }
  }
  return feed;
}

export function buildLiveFeed(payload) {
  const { gameData: game, liveData: live } = payload;
  if (!isFinal(game?.status)) throw new Error('Game is not final yet');
  const teams = {};
  for (const side of ['away', 'home']) {
    const team = game.teams[side];
    const totals = live.linescore.teams[side];
    const record = team.record?.leagueRecord;
    teams[side] = {
      side, id: team.id, name: team.name,
      club_name: team.teamName || team.clubName || team.name,
      abbreviation: team.abbreviation,
      record: record?.wins != null && record?.losses != null ? `${record.wins}-${record.losses}` : '—',
      runs: totals.runs, hits: totals.hits, errors: totals.errors,
      batting: playerRows(live.boxscore.teams[side], 'batting'),
      pitching: playerRows(live.boxscore.teams[side], 'pitching'),
    };
  }
  const boston = teams.away.id === BOS ? teams.away : teams.home;
  const opponent = teams.away.id === BOS ? teams.home : teams.away;
  const innings = live.linescore.innings;
  const plays = live.plays;
  // Do not replace a complete saved game with a partially populated final.
  if (!Array.isArray(plays?.scoringPlays) || !Array.isArray(plays?.allPlays)) throw new Error('Scoring plays unavailable');
  const scoring = plays.scoringPlays.map(index => {
    const { about, result } = plays.allPlays[index];
    const half = about.halfInning;
    return {
      inning: `${half[0].toUpperCase()}${half.slice(1)} ${about.inning}`,
      description: result.description || result.event || 'Scoring play',
      away_score: result.awayScore, home_score: result.homeScore,
    };
  });
  return validateFeed({
    game_pk: payload.gamePk,
    game_date: game.datetime.dateTime,
    ...teams, innings, scoring_plays: scoring,
    summary: gameSummary(boston, opponent, game.venue?.name || 'the ballpark', innings),
    gameday_url: `https://www.mlb.com/gameday/${payload.gamePk}`,
  });
}

export async function fetchLatestGame(now = new Date(), request = fetchJSON) {
  // Use Boston's calendar date even for visitors in other time zones.
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(now);
  const date = Object.fromEntries(parts.map(part => [part.type, part.value]));
  const end = `${date.year}-${date.month}-${date.day}`;
  const start = new Date(`${end}T12:00:00Z`);
  start.setUTCDate(start.getUTCDate() - 14);
  const schedule = await request(`${API}/api/v1/schedule?sportId=1&teamId=${BOS}&startDate=${start.toISOString().slice(0, 10)}&endDate=${end}&gameType=R`);
  const game = latestFinal(schedule);
  if (!game) throw new Error('No recent completed game found');
  const live = await request(`${API}/api/v1.1/game/${game.gamePk}/feed/live?fields=${LIVE_FIELDS}`);
  if (live.gamePk !== game.gamePk) throw new Error('Game response did not match schedule');
  return buildLiveFeed(live);
}

export function isOlderGame(candidate, current) {
  return current && (Date.parse(candidate.game_date) < Date.parse(current.game_date)
    || (candidate.game_date === current.game_date && candidate.game_pk < current.game_pk));
}
