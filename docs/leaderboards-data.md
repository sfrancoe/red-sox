# League leaderboard data

`scripts/fetch_league_leaders.py` publishes one complete, versioned population
per season under `data/leaderboards/`. It obtains regular-season AL, NL, and
MLB hitter/pitcher populations from the MLB Stats API, ranks at source
precision, and uses competition ranks for ties. AVG and OPS use the source's
`QUALIFIED` pool; WHIP uses Hub Ball's explicit 40-IP (120-out) minimum.

Run `python3 scripts/probe_league_leaders.py --season YEAR` before enabling a
new season. The saved fixture captures request shape, complete-population count,
person IDs, and Baseball Reference provider columns for review.

WAR comparison is intentionally unavailable in schema version 1. Baseball
Reference daily bWAR has provider identifiers but not a verified MLB-person-ID
crosswalk in this project. A name join is prohibited: publish and test a stable
crosswalk (including traded and two-way cases) before marking WAR available.
The app preserves Team leaders when any comparison category is unavailable.
