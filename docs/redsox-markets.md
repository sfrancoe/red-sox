# Fenway Forecast — Boston iOS markets

The Boston app’s Markets tab combines public Kalshi and Polymarket data. It is an informational view: no account connection, order placement, deposits, or trading credentials.

## Experience

- Eyes on October opens the tab with Polymarket’s postseason, AL East, and World Series probabilities.
- Market board: compact spreadsheet rows with market, chance, source, type, game, date, time, and volume columns. Provider and category filters narrow the table; horizontal scrolling reveals more columns on phones. Tap a row for details.
- Market detail: history, bid/ask quotes, source rules, and original market link.
- Freshness: retrieval timestamp, two-minute refresh while active, partial-provider notices, and a labeled saved snapshot when refresh fails.

The new endpoint is `/api/redsox-markets`. Add `history=<market/token ID>&provider=Kalshi|Polymarket&days=1|7` for history. All upstream hosts are fixed; IDs are validated. Responses are cached for 120 seconds at the CDN. No dependencies or paid data products were added.

## Accuracy decisions

Kalshi prices are midpoints of valid two-sided yes bids/asks. Missing, inverted, or empty books produce an unavailable price, never a made-up probability. Kalshi history uses hourly bid/ask midpoints.

Polymarket uses the published outcome price and the matching outcome token’s history. When Boston is the second outcome, both token selection and bid/ask inversion follow that outcome. Do not assume outcome zero means Boston.

Only Red Sox game events and Red Sox-specific season questions appear. Closed markets and prior-date games are excluded. Manager speculation is excluded so it does not overwhelm the team outlook. Settlement rules can differ even when both providers describe the same game.

Probability changes use percentage points across the available historical observations. No synthetic history is generated; charts with fewer than two points show an empty state. The vertical scale adjusts to observed prices and displays explicit percentage labels. Kalshi contract volume and Polymarket dollar volume retain separate units.

## Verification

`node scripts/test_redsox_markets.mjs` tests relevance, price normalization, reversed outcomes, missing books, chronological history, and partial/total outages with fixtures.

Live checks successfully fetched both providers, upcoming Boston game quotes, and both historical sources. Native simulator launch checks cover iPhone 17, iPad Pro, and iPad mini. Debug-only launch arguments `-show-markets`, `-local-markets` (localhost:8768), and `-market-detail` support direct inspection. Release builds always use the production HTTPS endpoint and normal launch behavior.

Interactive Simulator clicks were unavailable while the host Mac was locked; screenshots and native builds were verified. Boston build 4 includes the compact Eyes on October table, spreadsheet market board, and red background matching the other tabs.

## Primary API references

- https://docs.kalshi.com/getting_started/quick_start_market_data
- https://docs.kalshi.com/api-reference/market/get-market-candlesticks
- https://docs.polymarket.com/market-data/discover-markets
- https://docs.polymarket.com/market-data/prices-order-books
- https://docs.polymarket.com/api-spec/clob-openapi.yaml
