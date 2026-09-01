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
  'matchup', 'batter',
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

function possessive(name) {
  return name.endsWith('s') ? `${name}’` : `${name}’s`;
}

function scoringAction(play) {
  const batter = play.batter || 'Boston';
  let event = (play.event || 'scoring play').toLowerCase();
  event = ({ 'sac fly': 'sacrifice fly', 'field error': 'error' })[event] || event;
  const runLabel = ({ 2: 'two-run ', 3: 'three-run ', 4: 'grand slam ' })[play.rbi] || '';
  if (play.rbi === 4 && event === 'home run') event = '';
  return `${possessive(batter)} ${runLabel}${event}`.trim();
}

function gameSummary(boston, opponent, venue, scoring) {
  let awayScore = 0;
  let homeScore = 0;
  const annotated = scoring.map(play => {
    const beforeBoston = boston.side === 'away' ? awayScore : homeScore;
    const beforeOpponent = boston.side === 'away' ? homeScore : awayScore;
    awayScore = play.away_score || 0;
    homeScore = play.home_score || 0;
    return {
      ...play,
      beforeBoston,
      beforeOpponent,
      afterBoston: boston.side === 'away' ? awayScore : homeScore,
      afterOpponent: boston.side === 'away' ? homeScore : awayScore,
    };
  });

  if (boston.runs > opponent.runs) {
    const deficits = annotated.map(play => play.afterOpponent - play.afterBoston);
    const largestDeficit = Math.max(0, ...deficits);
    const deficitIndex = deficits.lastIndexOf(largestDeficit);
    const goAhead = annotated.filter(play => play.afterBoston > play.beforeBoston
      && play.beforeBoston <= play.beforeOpponent && play.afterBoston > play.afterOpponent);
    const winningPlay = goAhead.at(-1);
    const walkoff = winningPlay && boston.side === 'home' && winningPlay.inning_num >= 9
      && winningPlay === annotated.at(-1);
    let first;
    if (walkoff) {
      first = `${winningPlay.batter || 'Boston'} delivered a walk-off ${(winningPlay.event || 'hit').toLowerCase()} in the ${ordinal(winningPlay.inning_num)} inning as the Red Sox rallied past the ${opponent.club_name}, ${boston.runs}–${opponent.runs}, at ${venue}.`;
    } else if (largestDeficit >= 2) {
      first = `The Red Sox erased a ${largestDeficit}-run deficit to beat the ${opponent.club_name}, ${boston.runs}–${opponent.runs}, at ${venue}.`;
    } else if (opponent.runs === 0) {
      first = `The Red Sox shut out the ${opponent.club_name}, ${boston.runs}–${opponent.runs}, at ${venue}.`;
    } else {
      first = `The Red Sox beat the ${opponent.club_name}, ${boston.runs}–${opponent.runs}, at ${venue}.`;
    }

    const details = [];
    if (largestDeficit >= 2) {
      const lowPoint = annotated[deficitIndex];
      const rallyPlay = annotated.slice(deficitIndex + 1).find(play => play.afterBoston > play.beforeBoston);
      if (rallyPlay) {
        const remaining = rallyPlay.afterOpponent - rallyPlay.afterBoston;
        const effect = remaining === 0 ? 'tied the game'
          : remaining < 0 ? 'put Boston ahead'
            : `cut the deficit to ${remaining === 1 ? 'one' : remaining}`;
        details.push(`Boston trailed ${lowPoint.afterOpponent}–${lowPoint.afterBoston} before ${scoringAction(rallyPlay)} in the ${ordinal(rallyPlay.inning_num)} ${effect}.`);
      }
    }
    const tyingPlay = annotated.slice(deficitIndex + 1).find(play => play.afterBoston > play.beforeBoston
      && play.beforeBoston < play.beforeOpponent && play.afterBoston === play.afterOpponent);
    if (walkoff && tyingPlay && tyingPlay !== winningPlay) {
      const timing = winningPlay.inning_num - tyingPlay.inning_num === 1 ? 'one inning later' : 'later';
      details.push(`${scoringAction(tyingPlay)} tied it in the ${ordinal(tyingPlay.inning_num)}, and ${winningPlay.batter || 'Boston'} completed the comeback ${timing}.`);
    }
    return [first, ...details].join(' ');
  }

  const largestLead = Math.max(0, ...annotated.map(play => play.afterBoston - play.afterOpponent));
  if (boston.runs === 0) {
    return `The Red Sox were shut out by the ${opponent.club_name}, ${opponent.runs}–${boston.runs}, at ${venue}.`;
  }
  if (largestLead >= 2) {
    return `The Red Sox couldn’t hold a ${largestLead}-run lead and fell to the ${opponent.club_name}, ${opponent.runs}–${boston.runs}, at ${venue}.`;
  }
  return `The Red Sox fell to the ${opponent.club_name}, ${opponent.runs}–${boston.runs}, at ${venue}.`;
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
    const { about, result, matchup } = plays.allPlays[index];
    const half = about.halfInning;
    return {
      inning: `${half[0].toUpperCase()}${half.slice(1)} ${about.inning}`,
      inning_num: about.inning, half,
      batter: matchup?.batter?.fullName || '', event: result.event || '', rbi: result.rbi || 0,
      description: result.description || result.event || 'Scoring play',
      away_score: result.awayScore, home_score: result.homeScore,
    };
  });
  return validateFeed({
    game_pk: payload.gamePk,
    game_date: game.datetime.dateTime,
    ...teams, innings, scoring_plays: scoring,
    summary: gameSummary(boston, opponent, game.venue?.name || 'the ballpark', scoring),
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
