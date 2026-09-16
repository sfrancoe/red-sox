# Hub Ball: Team → League → MLB leaders

## Objective

Let fans answer two questions in one place: **Who leads the league? Where does our team’s leader stand?** Keep the existing team leaderboard as the default, and make the wider view immediately discoverable.

This is an implementation handoff, not an implemented feature. Based on the canonical checkout `/Users/sfrancoe/Projects/Hub Ball`, `main` at `317f204`, inspected September 15, 2026, and the supplied beta screenshot. No live source validation was performed for this plan; source behavior checks below are required before implementation relies on them. Screenshot values are illustrative inputs, not verified current statistics.

## 1. Recommended experience

### A visible, persistent scope control

Place a three-segment control directly below the existing top navigation, above the season cards:

**[ Team ] [ AL ] [ MLB ]**

- Team is selected on each fresh entry to Leaders. Do not persist a broader scope across app launches. Keep the current selection during refresh and detail-sheet dismissal.
- Use `HubTeam.league` to label the middle segment AL or NL. Accessible names: “Team leaders,” “American League leaders,” “Major League Baseball leaders.”
- Above or immediately below it, use a small label: **“Compare leaders”**. In Team mode, supporting copy says **“See how your team stacks up in AL and MLB.”** Adapt AL to NL.
- Keep the control outside the scrolling season content so it remains reachable while browsing older years. One selection applies to every season card; do not add six separate category toggles.
- Retain the current theme, typography, category order, compact three-row presentation, and team record in Team mode. No onboarding modal or hidden overflow action.
- Switching teams resets to Team and updates the league label. Preserve the current category/year scroll anchor when switching scope where practical.

### Wider boards that keep your team in the story

In AL/NL or MLB mode, show the scope’s top three for each category. Include team abbreviations, and emphasize selected-team players with a subtle tint plus a text label so color is not the only signal.

If the selected team’s category leader is outside the top three, add a separated **“Your team leader”** comparison row with that player’s actual scope rank and scope-specific value. If already visible, label their existing row instead of repeating it. The focus player is the first existing team-leader row; disclose co-leaders in category detail when applicable.

Example layout, with placeholders deliberately used for unverified ranks:

```text
Compare leaders
        Team       [ AL ]       MLB

2026                         American League

OPS                         Qualified hitters ⓘ
 1  League leader · TEAM                 …
 2  Another player · TEAM                …
 3  Another player · TEAM                …
 ─────────────────────────────────────────
#N  Willson Contreras · BOS           .904
    Your team leader
                         See top 10 & team →
```

The `.904` comes from the screenshot only. Production must use the selected scope’s generated value. Never ship placeholder ranks.

- In a wider scope, replace the team win–loss record in the year header with “American League,” “National League,” or “MLB.” A team record would imply the wrong subject.
- Keep WAR, WHIP, HR, AVG, OPS, RBI in the same order across all modes.
- Provide **“See top 10 & team”** in wider-scope category sections. Open a sheet for that year/category/scope showing the top 10 plus the existing team top-three players and their scope ranks below, deduplicated. This is a bounded detail view, not an infinite player directory.
- The sheet includes the full category name, qualification explanation, source, data date, and a close button. The main screen uses a short qualifier near the category title; essential context must not require scrolling to the footer.
- If the focus player is ineligible, display their value with “Not qualified” instead of a rank. If identity or source data is missing, say “Comparison unavailable”; do not confuse that with ineligibility.
- For a traded player, a scope value can differ from the team value. Label “AL totals” or “MLB totals” and expose the team-only value in detail. Never attach a full-season rank to a team-stint value without explanation.

### Interaction and accessibility

Use native SwiftUI controls with at least 44-point touch targets. Permit two-line names and move team abbreviations to a secondary line at large Dynamic Type sizes. Use monospaced numbers, flexible rank widths, VoiceOver descriptions such as “Tied for seventh in the American League,” and Reduce Motion support. A short crossfade is enough; avoid animated rank races. Verify the scope control and detail gestures coexist with the parent’s horizontal tab-swipe gesture.

On iPad retain the existing multiple-season layout, but allow extra vertical space for comparison rows. Do not compress the existing fixed-height grid until names or qualification labels become unreadable; use scrolling cards or fewer columns as needed.

## 2. What exists and why a new dataset is necessary

| Existing location | Relevant behavior |
| --- | --- |
| `ios/Hub Ball/Hub Ball/SeasonLeadersView.swift` | Phone/tablet layouts; renders three rows per category and enumerates ranks locally. |
| `SeasonLeaders.swift` in the same directory | Decodes team `seasons.json`; players currently have name/value, without stable player IDs or actual ranks. |
| `SeasonLeadersStore.swift` | Fetches team seasons and metadata together; has no scope state or independent comparison-loading state. |
| `HubTeam.swift`, `config/mlb-teams.json` | Already contain league membership and team identity. |
| `AppTabView.swift` | Recreates selected content with `.id(team.id)` when teams change. |
| `scripts/fetch_seasons.py` | Boston generation, including batting leaders and bWAR. |
| `scripts/fetch_team_leaders.py` | Registry expansion-team generation; separate workflows/scripts also exist for Yankees, Mets, and Rays. |
| `netlify/functions/app-data.mjs` | Explicit allowlist for production data paths; proxies generated files from GitHub. |
| `docs/app-backend.md` | Data-only commits can skip deployment; new gateway paths require a backend deployment. |

Combining existing team top threes cannot produce accurate AL/MLB ranks. Fetch complete eligible populations, rank before truncating, and generate one shared comparison dataset. Leave the existing team payload contract intact so installed builds continue working.

## 3. Ranking contract: decide this before drawing ranks

These are product rules; confirm source support with saved fixtures.

| Category | Order | Eligibility in the wider boards |
| --- | --- | --- |
| HR, RBI | Highest first | All regular-season hitters with valid values. |
| AVG, OPS | Highest first | Source-confirmed qualified hitters for that season and scope. |
| WHIP | Lowest first | At least **40 IP**, matching the current team screen; label “Min. 40 IP” in every scope. |
| WAR | Highest first | Baseball Reference bWAR, consistent with the existing combined batting/pitching concept; no new playing-time cutoff. |

WHIP is deliberately a Hub Ball comparison pool including relievers. Do not describe it as the official qualified pitching leaderboard. Retaining 40 IP avoids silently removing a team leader such as a reliever when switching scope. Early-season empty boards should say “No pitchers have reached 40 IP.” Do not silently lower the threshold.

Additional invariants:

1. Regular season only; keep each displayed year independent. Fetch all displayed years at launch, not just the current season. Determine the union of existing team season keys rather than hardcoding 2026 or assuming every team has identical history.
2. Use stable MLB person IDs for MLB data and stable source player IDs for bWAR. Verified cross-source ID mapping is required where joining; never rely solely on names. Unmapped identities must be logged and visibly unavailable, not guessed.
3. MLB represents each player’s combined MLB season. AL/NL represents production in that league in that season. Team continues to represent existing team production. Check source split/aggregate semantics, especially cross-league trades, before coding this assumption into requests.
4. Never double-count aggregate rows plus team stints. Never average stint AVG, OPS, or WHIP. Use verified source aggregates or recompute from underlying counting components. Convert innings to integer outs; `40.2` means 40 innings and two outs.
5. Resolve league-specific qualification using verified source behavior, including trade cases and any official exception handling. Do not approximate eligibility with current roster membership or assume an API flag means the same thing at every scope.
6. WAR aggregation must avoid counting two-way-player components twice, retain source precision, and map historical team/league identities. Do not substitute fWAR if bWAR becomes unavailable.
7. Rank at authoritative source precision before display formatting. Preserve ties at that precision using competition ranking: 1, 2, 2, 4. Alphabetical/ID sorting stabilizes display only and does not break ties. Use `T-2` when helpful. Limit summaries to three players and detail to 10, with a “More players tied” disclosure when the cutoff splits a tie; detail can expand the cutoff tie group.
8. Null or invalid values are not zero. Distinguish empty eligible pools, missing coverage, and fetch errors.
9. A player's team abbreviation describes that season/scope, not necessarily their present roster. Show “Multiple teams” where appropriate.
10. Generate focus-player identity references and comparison values from a coherent snapshot. If existing Team data is newer, disclose separate timestamps; do not imply identical snapshots.

### Required source feasibility check

Before UI implementation, build a small stdlib probe and save representative response fixtures. Confirm MLB request parameters, pagination and total counts, league filters, aggregate rows, qualification, traded players, and player IDs. Inspect both existing bWAR feeds for historical coverage, stable IDs, league fields, and aggregate/stint representation. Source URLs are already referenced in the existing fetch scripts; their current behavior is not established by this plan.

If a historical season or bWAR category cannot be sourced reliably, keep Team available and show explicit comparison unavailability for that category/year. Document the gap in the PR. Do not fabricate history, silently mix providers, or present partial populations as complete rankings. Default request headers first; follow the repository’s exact User-Agent fallback only if needed. No paid source or new dependency.

## 4. Data architecture

Add `scripts/fetch_league_leaders.py` and shared pure ranking helpers if useful. Fetch hitting, pitching, and bWAR once per season/source, deriving AL, NL, and MLB outputs from validated full populations. Avoid a source fetch per team/category/toggle.

Generate shared **`data/leaderboards/<year>.json`** files. Fetch the newest visible year first in the app, then older visible years as needed. One year file contains all three wider scopes, so AL ↔ MLB is an in-memory switch after loading.

Proposed versioned contract:

- `schema_version`, `season`, `generated_at`, source-specific `as_of` and provenance.
- `coverage`: explicit availability for each scope/category, with safe user-facing reason codes.
- `scopes.al|nl|mlb.categories.war|whip|hr|avg|ops|rbi`:
  - eligibility policy and short display label;
  - complete population count;
  - ranked eligible entries, numeric canonical value and formatted display value;
  - stable player ID/provider, season team IDs/abbreviations, rank and tie metadata.
- `team_contexts.<team_id>.<category>`: references to existing team top-three identities plus their eligibility and scope values, including nonqualified comparison players. Generate this mapping alongside the same source snapshot, without changing legacy consumers.

Start with the compact complete ranked population per year: it simplifies focus-player lookup and tie handling and avoids extra endpoints. Measure actual uncompressed and compressed payload sizes in the source spike; if excessive, publish top-10-plus-cutoff-ties and precomputed comparison rows for all supported teams, retaining complete-population ranking on the generator. Never infer a rank from a truncated file.

Validate all categories before atomically replacing a successful year artifact. A refresh failure retains the previous valid snapshot and fails visibly in CI. Retained data keeps its original timestamp. Cache completed historical seasons; refresh the active season daily through one workflow using the existing `site-data-writes` concurrency group. Support explicit historical refresh for stat corrections.

## 5. Implementation sequence

### A. Establish the data contract and fixtures

Implement the feasibility probe, ranking helpers, generated schema, and tests for the hard cases above. Avoid broad refactoring of the existing team generators. Confirm context-player selection matches legacy Team rows; report mismatches caused by differing snapshots.

### B. Publish the shared backend path

Add exact generated paths to `ALLOWED_PATHS` in `netlify/functions/app-data.mjs`; retain strict path validation. Cover both `/api/data/leaderboards/<year>.json` and legacy `/data/leaderboards/<year>.json` routes in `scripts/test_app_data.mjs`. Update allowed years during season rollover.

Add `AppBackend.sharedDataURL(_:)` using the existing `dataRoot`, including `HUB_DATA_ROOT` and DEBUG/release behavior. Do not use a selected-team prefix or bypass the gateway with raw source URLs. `scripts/build_site.sh` already copies the whole data directory.

### C. Add Swift models and independent loading

Add a scope enum (`team`, `league`, `mlb`) and versioned comparison models. Keep legacy decoding compatible. Use stable IDs for new rows and supplied ranks, not array indices. Update the existing store or a small dedicated store with per-year loading/error/cache state. Comparison failure must never blank an already-loaded Team screen.

Load legacy team content first; prefetch the newest comparison year after it renders. Requests should be cancellable, deduplicated, and protected against stale responses after team/year changes. Cache by season and schema version, not team; team context is a projection. Keep last successful content during refresh with an honest timestamp and a retry affordance. A cold offline launch may show an explicit unavailable state if no usable URL cache exists; do not promise durable offline storage without implementing it.

### D. Build the scope UI and comparison sheet

Implement the persistent control, dynamic AL/NL label, scope-aware year headers, shared row rendering, highlighted focus rows, qualification labels, and top-10 sheet. Update both phone and tablet layouts. Remove the hardcoded current-year styling check while touching the year header; derive it from date/season state.

On comparison loading, retain the scope control and year/category structure with loading placeholders. On failure, keep the chosen scope and show “League leaders unavailable” with Retry and Back to Team. Never show team rows under an MLB heading. Partial category coverage should leave other categories usable.

### E. Verify and release in order

1. Run generator, schema and gateway tests. Review source-backed sample ranks, including the screenshot’s OPS question using freshly generated data.
2. Serve generated files over HTTP and use `HUB_DATA_ROOT` for simulator verification. Exercise iPhone and iPad, large type, VoiceOver, team switching, all scopes, history, slow requests, refresh failure, and cutoff ties.
3. Build the native app and run focused decoding/state tests for new functionality using the project’s existing test conventions. Capture screenshots for Team, AL, MLB, and the comparison sheet.
4. Publish generated data and gateway allowlist changes to canonical `main`, wait for the required backend deployment, and verify production responses for both release and legacy route forms before distributing the app. Data-only refreshes afterward follow the existing gateway model.
5. Follow the canonical release process for any eventual installation/TestFlight request; run `python3 scripts/check_hub_ball_release.py` and use the approved install/release scripts. This planning task does not authorize or require a build upload.

## 6. Acceptance checklist

- [ ] A fresh Leaders visit shows the familiar team top-three lists and an obvious Team / AL-or-NL / MLB control.
- [ ] One tap shows real wider leaders and the team leader’s actual rank, even outside the top 10.
- [ ] A player already in the summary is highlighted once; detail includes context for all three team leaders.
- [ ] AL and NL teams work; switching teams cannot display the previous team’s context or the wrong league.
- [ ] Every existing season is supported or has a specific, honest coverage message.
- [ ] WHIP consistently shows the 40-IP minimum; qualified batting and bWAR provenance are clear.
- [ ] Ties, source precision, two-way players, trades, multiple-team rows, and ineligible/missing players have fixture-based tests.
- [ ] Full populations are fetched and validated before ranks are assigned; a fourth-place team player can still appear on a wider board.
- [ ] Legacy team payloads still decode; comparison failures do not disable Team.
- [ ] AL ↔ MLB switches do not issue redundant source requests; refreshes retain usable content and accurate timestamps.
- [ ] Production gateway paths work before native distribution; phone/tablet and accessibility verification is recorded.

## Scope boundary

Ship the three scopes, all six categories, available historical coverage, team comparison rows, and the bounded detail sheet together. Leave arbitrary league selection, player search, percentile charts, favorites, notifications, and live pitch-by-pitch refresh for later. The feature succeeds when a fan can go from “Contreras leads us in OPS” to “Here is where he stands across the league” in one tap.
