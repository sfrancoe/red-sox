# October provider contract

Read-only checks against MLB Stats API on September 26, 2026, returned HTTP 200 for
the game-type catalog and postseason schedules. The captured schedule fixtures are
in `scripts/fixtures/postseason-2025.json` and `scripts/fixtures/postseason-2026.json`.

- `gameTypes=F,D,L,W` returns Wild Card, Division Series, League Championship Series,
  and World Series games. The captured seasons contain 47 (2025) and 53 (2026) game
  entries; these are fixture observations, not application constants.
- Schedule fields include `seriesGameNumber`, `gamesInSeries`, `seriesDescription`,
  `description`, status, team IDs, scores, `isWinner`, and `ifNecessary`. A stable
  series key uses season, round, league, and the provider's described bracket slot;
  it does not use the current pair of participants.
- MLB's published 12-team rules define first-round byes, the No. 3/6 and No. 4/5
  Wild Card pairings, and which Wild Card winner each top seed faces. Those
  season-versioned rules connect the provider's A/B slot labels to the next round;
  no advancement is inferred from participant order or game wins alone. MLB's 2026
  schedule confirms the best-of-three Wild Card, best-of-five Division Series, and
  best-of-seven League Championship and World Series lengths.
- The 2026 schedule includes synthetic names such as `AL 4/5 Winner` and
  `NL Wild Card #3`, with `startTimeTBD: true` and placeholder timestamps. These
  remain unresolved slots, and the dummy clock time is never presented as a start.
- A named participant in a future schedule is not treated as a confirmed qualifier.
  The envelope reports qualification as unknown until a postseason game establishes
  participation. If a provider bracket-slot label is missing or unrecognized,
  `nextSlots` stays unknown rather than inferring a bracket edge from team names.
- Adding `hydrate=linescore,broadcasts` returned historical linescore inning data
  and TV broadcast records. The same fixed hydration is used for the overview; the
  app shows broadcast names only when MLB includes them in the schedule response.
- Series wins use unique completed games with a supported MLB team on both sides,
  a final completion code, numeric unequal scores, and an agreeing unique winner flag.
  Canceled, postponed, suspended, unresolved, duplicate-conflicting, and malformed
  results do not add wins.

Source endpoints and format rules: [MLB game types](https://statsapi.mlb.com/api/v1/gameTypes),
[official postseason format FAQ](https://www.mlb.com/news/mlb-playoff-format-faq),
[2026 official schedule and series lengths](https://www.mlb.com/news/2026-mlb-playoff-and-world-series-schedule),
[2025 postseason schedule](https://statsapi.mlb.com/api/v1/schedule?sportId=1&season=2025&gameTypes=F,D,L,W&hydrate=linescore,broadcasts),
[2026 postseason schedule](https://statsapi.mlb.com/api/v1/schedule?sportId=1&season=2026&gameTypes=F,D,L,W&hydrate=linescore,broadcasts).
