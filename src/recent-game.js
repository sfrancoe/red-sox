const score = document.getElementById('recentGameScore');

async function loadGame() {
  try {
    const response = await fetch('../data/recent-game.json', { cache: 'no-store' });
    if (!response.ok) throw new Error(`Recent game request returned ${response.status}`);
    const feed = await response.json();
    if (!feed.game_pk || !feed.away || !feed.home) throw new Error('Recent game data was incomplete');
    score.textContent = `${feed.away.name} ${feed.away.runs}, ${feed.home.name} ${feed.home.runs}`;
  } catch (error) {
    console.error(error);
    score.textContent = 'The most recent score could not be loaded right now.';
  }
}

await loadGame();
setInterval(() => {
  if (document.visibilityState === 'visible') loadGame();
}, 300_000);
