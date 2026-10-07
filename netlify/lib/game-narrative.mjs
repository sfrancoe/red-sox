import { MLB_TEAMS } from '../functions/team-registry.mjs';

const CITY_BY_ID = new Map(MLB_TEAMS.map(team => [team.mlb_id, team.city_name]));

function ordinal(value) {
  const suffix = value % 100 > 10 && value % 100 < 14 ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' }[value % 10] || 'th');
  return `${value}${suffix}`;
}

function possessive(name) {
  return name.endsWith('s') ? `${name}’` : `${name}’s`;
}

function scoringAction(play) {
  const batter = play.batter || 'The batter';
  let event = (play.event || 'scoring play').toLowerCase();
  event = ({ 'sac fly': 'sacrifice fly', 'field error': 'error' })[event] || event;
  const runLabel = ({ 2: 'two-run ', 3: 'three-run ', 4: 'grand slam ' })[play.rbi] || '';
  if (play.rbi === 4 && event === 'home run') event = '';
  return `${possessive(batter)} ${runLabel}${event}`.trim();
}

const capitalize = text => text.charAt(0).toUpperCase() + text.slice(1);

// The city reads naturally ("put Boston ahead"), but two clubs from one city
// (Yankees–Mets, Cubs–White Sox) would be ambiguous, so fall back to the club.
function placeName(team, other) {
  const city = CITY_BY_ID.get(team.id);
  return city && city !== CITY_BY_ID.get(other.id) ? city : `the ${team.club_name}`;
}

function placePossessive(place) {
  return place.startsWith('the ') ? `${place}’` : `${place}’s`;
}

function gameSummary(favorite, opponent, venue, scoring) {
  const place = placeName(favorite, opponent);
  let awayScore = 0;
  let homeScore = 0;
  const annotated = scoring.map(play => {
    const beforeFavorite = favorite.side === 'away' ? awayScore : homeScore;
    const beforeOpponent = favorite.side === 'away' ? homeScore : awayScore;
    awayScore = play.away_score || 0;
    homeScore = play.home_score || 0;
    return {
      ...play,
      beforeFavorite,
      beforeOpponent,
      afterFavorite: favorite.side === 'away' ? awayScore : homeScore,
      afterOpponent: favorite.side === 'away' ? homeScore : awayScore,
    };
  });

  if (favorite.runs > opponent.runs) {
    const deficits = annotated.map(play => play.afterOpponent - play.afterFavorite);
    const largestDeficit = Math.max(0, ...deficits);
    const deficitIndex = deficits.lastIndexOf(largestDeficit);
    const goAhead = annotated.filter(play => play.afterFavorite > play.beforeFavorite
      && play.beforeFavorite <= play.beforeOpponent && play.afterFavorite > play.afterOpponent);
    const winningPlay = goAhead.at(-1);
    const walkoff = winningPlay && favorite.side === 'home' && winningPlay.inning_num >= 9
      && winningPlay === annotated.at(-1);
    let first;
    if (walkoff) {
      first = `${winningPlay.batter || favorite.club_name} delivered a walk-off ${(winningPlay.event || 'hit').toLowerCase()} in the ${ordinal(winningPlay.inning_num)} inning as the ${favorite.club_name} rallied past the ${opponent.club_name}, ${favorite.runs}–${opponent.runs}, at ${venue}.`;
    } else if (largestDeficit >= 2) {
      first = `The ${favorite.club_name} erased a ${largestDeficit}-run deficit to beat the ${opponent.club_name}, ${favorite.runs}–${opponent.runs}, at ${venue}.`;
    } else if (opponent.runs === 0) {
      first = `The ${favorite.club_name} shut out the ${opponent.club_name}, ${favorite.runs}–${opponent.runs}, at ${venue}.`;
    } else {
      first = `The ${favorite.club_name} beat the ${opponent.club_name}, ${favorite.runs}–${opponent.runs}, at ${venue}.`;
    }

    const details = [];
    if (largestDeficit >= 2) {
      const lowPoint = annotated[deficitIndex];
      const rallyPlay = annotated.slice(deficitIndex + 1).find(play => play.afterFavorite > play.beforeFavorite);
      if (rallyPlay) {
        const remaining = rallyPlay.afterOpponent - rallyPlay.afterFavorite;
        const effect = remaining === 0 ? 'tied the game'
          : remaining < 0 ? `put ${place} ahead`
            : `cut the deficit to ${remaining === 1 ? 'one' : remaining}`;
        details.push(`${capitalize(place)} trailed ${lowPoint.afterOpponent}–${lowPoint.afterFavorite} before ${scoringAction(rallyPlay)} in the ${ordinal(rallyPlay.inning_num)} ${effect}.`);
      }
    }
    const tyingPlay = annotated.slice(deficitIndex + 1).find(play => play.afterFavorite > play.beforeFavorite
      && play.beforeFavorite < play.beforeOpponent && play.afterFavorite === play.afterOpponent);
    if (walkoff && tyingPlay && tyingPlay !== winningPlay) {
      const timing = winningPlay.inning_num - tyingPlay.inning_num === 1 ? 'one inning later' : 'later';
      details.push(`${scoringAction(tyingPlay)} tied it in the ${ordinal(tyingPlay.inning_num)}, and ${winningPlay.batter || favorite.club_name} completed the comeback ${timing}.`);
    } else if (largestDeficit < 2 && winningPlay && !walkoff) {
      // A walk-off's opening sentence already names the winning play.
      details.push(`${scoringAction(winningPlay)} in the ${ordinal(winningPlay.inning_num)} put ${place} ahead for good.`);
    }
    return [first, ...details].join(' ');
  }

  const largestLead = Math.max(0, ...annotated.map(play => play.afterFavorite - play.afterOpponent));
  if (favorite.runs === 0) {
    return `The ${favorite.club_name} were shut out by the ${opponent.club_name}, ${opponent.runs}–${favorite.runs}, at ${venue}.`;
  }
  const first = largestLead >= 2
    ? `The ${favorite.club_name} couldn’t hold a ${largestLead}-run lead and fell to the ${opponent.club_name}, ${opponent.runs}–${favorite.runs}, at ${venue}.`
    : `The ${favorite.club_name} fell to the ${opponent.club_name}, ${opponent.runs}–${favorite.runs}, at ${venue}.`;
  const details = [];
  const opponentGoAhead = annotated.filter(play => play.afterOpponent > play.afterFavorite
    && play.beforeOpponent <= play.beforeFavorite && play.afterOpponent > play.beforeOpponent).at(-1);
  if (opponentGoAhead) {
    details.push(`${scoringAction(opponentGoAhead)} in the ${ordinal(opponentGoAhead.inning_num)} put the ${opponent.club_name} ahead for good.`);
  }
  // Most runs on one play; a later inning breaks ties, else the first such play.
  const highlight = annotated.filter(play => play.afterFavorite > play.beforeFavorite)
    .reduce((best, play) => {
      if (!best) return play;
      const runs = play.afterFavorite - play.beforeFavorite;
      const bestRuns = best.afterFavorite - best.beforeFavorite;
      return runs > bestRuns || (runs === bestRuns && play.inning_num > best.inning_num) ? play : best;
    }, null);
  if (highlight) {
    details.push(`${capitalize(placePossessive(place))} biggest swing came on ${scoringAction(highlight)} in the ${ordinal(highlight.inning_num)}.`);
  }
  return [first, ...details].join(' ');
}

export function gameNarratives(payload) {
  const game = payload.gameData || {}, live = payload.liveData || {};
  const lines = live.linescore || {};
  const liveGame = game.status?.abstractGameState === 'Live';
  const confirmedFinal = game.status?.abstractGameState === 'Final' && ['F', 'O'].includes(game.status?.codedGameState);
  if (!liveGame && !confirmedFinal) return {};
  const scoring = (live.plays?.scoringPlays || []).map(index => live.plays?.allPlays?.[index]).filter(Boolean)
    .map(play => ({ inning_num: play.about?.inning || 0, batter: play.matchup?.batter?.fullName || '',
      event: play.result?.event || '', rbi: play.result?.rbi || 0,
      away_score: play.result?.awayScore || 0, home_score: play.result?.homeScore || 0 }));
  const result = {};
  for (const side of ['away', 'home']) {
    const other = side === 'away' ? 'home' : 'away';
    const describe = key => ({ ...lines.teams?.[key], ...game.teams?.[key], side: key,
      club_name: game.teams?.[key]?.teamName || game.teams?.[key]?.clubName || game.teams?.[key]?.name });
    const favorite = describe(side), opponent = describe(other);
    if (!favorite.id || !favorite.club_name || !opponent.club_name || !Number.isFinite(favorite.runs) || !Number.isFinite(opponent.runs)) continue;
    const venue = game.venue?.name || 'the ballpark';
    const inning = lines.currentInningOrdinal || ordinal(lines.currentInning || 1);
    const situation = lines.inningState === 'Middle' ? `after the top of the ${inning}`
      : lines.inningState === 'End' ? `after the ${inning}` : `in the ${(lines.inningHalf || '').toLowerCase()} of the ${inning}`;
    let summary;
    if (!liveGame) summary = gameSummary(favorite, opponent, venue, scoring);
    else if (favorite.runs === opponent.runs) summary = `The ${favorite.club_name} and ${opponent.club_name} are tied, ${favorite.runs}–${opponent.runs}, ${situation} at ${venue}.`;
    else {
      const ahead = favorite.runs > opponent.runs;
      summary = `The ${favorite.club_name} ${ahead ? 'lead' : 'trail'} the ${opponent.club_name}, ${Math.max(favorite.runs, opponent.runs)}–${Math.min(favorite.runs, opponent.runs)}, ${situation} at ${venue}.`;
    }
    const facts = [];
    const innings = (lines.innings || []).length;
    if (!liveGame && innings > 9) facts.push(`The game went ${innings} innings.`);
    const box = live.boxscore?.teams?.[side] || {};
    const batters = [...new Set([...(box.battingOrder || []), ...(box.batters || [])])]
      .map(id => box.players?.[`ID${id}`]).filter(Boolean);
    const top = [...batters].sort((a, b) => (b.stats?.batting?.hits || 0) - (a.stats?.batting?.hits || 0))[0];
    if (top?.stats?.batting?.hits >= 2) facts.push(`${top.person.fullName} ${liveGame ? 'has' : 'had'} ${top.stats.batting.hits} of the ${favorite.club_name}’ ${favorite.hits} hits${liveGame ? ' so far' : ''}.`);
    const homers = batters.filter(player => player.stats?.batting?.homeRuns > 0);
    if (homers.length) {
      const count = homers.reduce((sum, player) => sum + player.stats.batting.homeRuns, 0);
      const names = homers.map(player => player.person.fullName + (player.seasonStats?.batting?.homeRuns != null ? ` (${player.seasonStats.batting.homeRuns})` : '')).join(', ');
      facts.push(`The ${favorite.club_name} ${liveGame ? 'have hit' : 'hit'} ${count} home run${count === 1 ? '' : 's'}: ${names}.`);
    }
    const starter = box.players?.[`ID${box.pitchers?.[0]}`];
    const stats = starter?.stats?.pitching;
    if (!liveGame && stats?.inningsPitched != null && stats.earnedRuns != null && stats.strikeOuts != null) {
      facts.push(`${starter.person.fullName} worked ${stats.inningsPitched} innings, allowed ${stats.earnedRuns} earned run${stats.earnedRuns === 1 ? '' : 's'}, and struck out ${stats.strikeOuts}.`);
    }
    result[favorite.id] = { summary, facts: facts.slice(0, 5) };
  }
  return result;
}
