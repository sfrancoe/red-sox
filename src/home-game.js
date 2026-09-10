const API = 'https://statsapi.mlb.com';
const BOS = 111;

export function easternDate(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(now);
  const date = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${date.year}-${date.month}-${date.day}`;
}

export function selectHomeGame(schedule, previousGamePk = null) {
  const games = (schedule.dates || []).flatMap(day => day.games || []);
  const live = games.find(game => game.status?.abstractGameState === 'Live');
  if (live) return live;
  if (!previousGamePk) return null;
  return games.find(game => game.gamePk === previousGamePk
    && game.status?.abstractGameState === 'Final') || null;
}

function team(side) {
  const record = side.leagueRecord || {};
  return {
    id: side.team.id,
    abbreviation: side.team.abbreviation,
    record: record.wins == null || record.losses == null ? '—' : `${record.wins}-${record.losses}`,
    runs: side.score ?? 0,
  };
}

export function normalizeHomeGame(game) {
  const isLive = game.status?.abstractGameState === 'Live';
  const inning = [game.linescore?.inningState, game.linescore?.currentInningOrdinal].filter(Boolean).join(' ');
  return {
    game_pk: game.gamePk,
    game_date: game.gameDate,
    venue: game.venue?.name || '',
    away: team(game.teams.away),
    home: team(game.teams.home),
    is_live: isLive,
    status: isLive ? (inning || game.status?.detailedState || 'Live') : 'Final',
    gameday_url: `https://www.mlb.com/gameday/${game.gamePk}`,
  };
}

export async function fetchHomeGame(previousGamePk = null, now = new Date(), request = fetch) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  try {
    const date = easternDate(now);
    const url = `${API}/api/v1/schedule?sportId=1&teamId=${BOS}&date=${date}&hydrate=linescore,team`;
    const response = await request(url, { cache: 'no-store', signal: controller.signal });
    if (!response.ok) throw new Error(`Live game request returned ${response.status}`);
    const game = selectHomeGame(await response.json(), previousGamePk);
    return game ? normalizeHomeGame(game) : null;
  } finally {
    clearTimeout(timeout);
  }
}
