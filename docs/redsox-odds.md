# Red Sox homepage odds

The web homepage and native Home tab display the Red Sox moneyline and run line from
DraftKings. The browser and app call `/api/redsox-odds`; the Odds-API.io credential
stays in the Netlify function and is never shipped to either client.

Set `ODDS_API_IO_KEY` in the Netlify environment. The function requests only pending
MLB games available from DraftKings, keeps the first three Boston games, and caches
the normalized response at the CDN for five minutes. If the key, source, game, or
individual market is unavailable, the homepage says the line is not posted instead
of inventing a price.

Odds are presented for information only. The homepage does not link to a sportsbook,
accept wagers, create accounts, or handle money.

Run `node scripts/test_redsox_odds.mjs` to verify odds normalization.
