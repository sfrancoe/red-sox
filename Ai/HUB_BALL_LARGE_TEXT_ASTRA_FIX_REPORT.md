# Hub Ball enlarged text — Astra fixes and verification status

Date: September 21, 2026

**Status: code fixes implemented; final visual and interaction verification blocked. This is not an app-wide accessibility sign-off.**

Worktree: `/Users/sfrancoe/Projects/Hub Ball Large Text`  
Branch: `codex/hub-ball-large-text`  
Implementation commit: `d924513be537f74161947fddd1a5f1b93868f6df`  
Starting commit: `5e00de1d` (Luna's completion audit)

The owner authorized Astra to implement the remaining fixes directly. Work continued on the existing isolated branch. Earlier Luna screenshots and PASS entries describe older source; they do not establish that this implementation passes the required device matrix.

## Implemented fixes

### Player records and accessibility

- Expanded season records expose every statistic as an individually navigable label/value accessibility element. Their parent groups no longer discard the children and replace them with a summary of only three statistics.
- Career totals expose their actual values. Compact career rows and totals also have complete spoken descriptions, using the same metric lists as expanded records.
- Missing values are announced as unavailable, rather than incorrectly announced as zero.
- Full metric names, single-column records, and stacked season/team headings avoid forcing enlarged numbers and long identifiers into narrow cells. Sorting, all batting/pitching metrics, subtotal selection, and calculation helpers are retained.
- Expanded player directories show age and offer age sorting at phone widths, independently of the compact table's age-column breakpoint.
- At accessibility sizes, directory metadata stacks on tablets as well as phones. Player detail titles are visible in scrolling content rather than relying on a constrained navigation toolbar. Expanded biography labels no longer use a fixed 74-point column.
- Expanded career mode/scope controls stack. The back control has a 44-point target.

### Navigation and other dense controls

- Expanded app navigation uses a labeled page menu and a team/settings action, freeing vertical space previously occupied by the large team header and scrolling tab strip. The menu retains all available sections and their saved order, plus team context.
- Settings-section, standings-mode, pitching-role, and leaderboard-scope controls have expanded menu presentations. Existing selections and bindings are reused.
- Game 108 playback/music and speed controls stack at expanded sizes. Home Run Chase navigation and slider label/value layouts reflow; sliders now have explicit accessibility labels.
- Expanded leaders rows stack rank, name, and value, and no longer limit player names to two lines. Ordinary tablet standings ranks have sufficient minimum width for two digits.

### Game Recaps and Pitching

- The enlarged inning table uses semantic body text and proportionally scaled column widths, with horizontal scrolling for all innings and R/H/E/LOB totals. Accessibility labels identify the team and inning/statistic for each value.
- Expanded batting/pitching section headers, team selectors, player names/details, and label/value records stack instead of competing for horizontal space. Default batting/pitching section layouts remain on their previous paths.
- Expanded pitching comparisons show labeled Actual and Forecast values vertically for fWAR, innings, ERA, FIP, and K−BB%, instead of a compressed three-column grid.
- Standings freshness/source text and Recaps section headings scale in expanded layouts.

### Story reading

- The Brewers story now has a dedicated expanded reading presentation using the existing event cursor, games, cumulative hitter credits, and recorded pitching events. Essential information is visible in scalable text rather than confined to the drawing or fixed-size labels.
- It includes the score, date/inning, selected play description and contributions, full hitter names/RBI/runs/hits, runs without an RBI, and pitcher innings/strikeouts/hits/walks.
- A recorded-play disclosure lets the reader select another event using the existing cursor. Player-moment links and chapter/playback controls remain available. Combined-game totals are derived from the same source as the compact story.
- Expanded transport is inside scrolling content so a fixed footer does not consume the small landscape viewport. Default story/chart presentation remains on its previous path.
- Home Run Chase explanatory copy and comparison-bar label/value layouts also adapt at enlarged sizes. Existing chart calculations, data, projection logic, and story facts are retained.

## Checks actually completed

| Check | Result | Evidence |
|---|---|---|
| Debug simulator build of final source | PASS | `dist/astra-large-text-audit/debug-build.log` |
| Release generic iOS build of final source, signing disabled | PASS | `dist/astra-large-text-audit/release-build.log` |
| Home Run Chase engine tests | PASS | `bash scripts/test_chase_engine.sh` — engine tests passed. |
| Brewers story-data tests | PASS | `python3 scripts/test_brewers_shutouts.py` — 3 tests passed. |
| Player career data checks | PASS | `python3 scripts/test_player_careers.py` — 1,373 profiles across 30 teams passed. |
| Diff whitespace check | PASS | `git diff --check` before implementation commit. |
| Runtime inventory | OBSERVED | Only iOS 26.5 is installed. |
| New simulator interactions/screenshots | BLOCKED | Simulator computer-use tool twice reported that the Mac was locked and automatic unlock failed. No new interaction or visual PASS is claimed. |
| Spoken VoiceOver | UNVERIFIED | Code repairs are implemented, but a spoken reading/action pass has not run. |
| iOS 17 runtime | UNAVAILABLE | No installed iOS 17 runtime. A deployment-target-17 build does not prove runtime behavior. |

The tests above protect existing data/calculation behavior; they do not prove visual layout, accessibility focus order, or state retention. No new tests merely asserting layout constants were added.

## Exact remaining verification

First unlock the Mac, then install this branch's Debug build on simulators only and follow the original completion plan. Record original simulator text settings/orientations and restore them afterward. Do not infer passes from the previous audit.

1. Verify the new page menu reaches all ten sections, preserves selected page/team, and leaves usable content space on SE landscape. Check ordinary-size navigation remains intact.
2. On SE and Pro Max, inspect every section plus onboarding/settings, hitter and pitcher details, and all reachable stories at default and accessibility5. Scroll to lower content and activate the primary controls. Repeat the specified intermediate-size and landscape checks.
3. For Players specifically, capture a real season record and actual career totals (not merely the biography). Verify all metrics, long team names, missing values, sorting, age, search with keyboard, back navigation, and both record modes/scopes where available.
4. Check Recaps inning values and R/H/E/LOB at both horizontal extremes, including extra innings; check selecting the opposite team's batting/pitching and navigating to a player. Horizontal table scrolling must not change app sections.
5. Check expanded Pitching comparison records, leaderboard scope/detail sheets, standings modes/ranks/freshness, and all selectors and dismissal controls.
6. On the Brewers story, validate initial/selected/final play text, playback/pause, previous/next, progress slider, recorded-play selection, both games and combined chapter, all contributors, player sheets, sources, and share-sheet reachability without publishing. Verify Home Run Chase chapter/slider state and Game 108 playback/music/speed controls.
7. Complete iPad mini and 13-inch iPad coverage across all distinct layouts at default/accessibility5, portrait/landscape, and a supported narrow/resized window. Record real window dimensions; rotating the Simulator toolbar unsuccessfully is not a landscape pass.
8. Change text size and rotate while a list is filtered and while a recap/player/story is selected. Test background/foreground with the existing pause/retention rules. These need live interaction; code inspection alone is insufficient.
9. Perform the focused spoken VoiceOver pass, including every career metric and totals. Accessibility-tree inspection is useful but must be labeled separately. Test Display Zoom if available, separately from Dynamic Type and Simulator window magnification.
10. Complete the iPhone 17 default-section regression pass and changed-layout enlarged checks. Label any genuinely unavailable OS/system capability explicitly and leave its corresponding check open.

Keep the PASS/FAIL/UNVERIFIED ledger tied to the implementation commit and concrete screen/device/size/orientation/action evidence. Fix any failures and rerun affected checks before declaring the issue complete.

## Release status

No merge, push, deployment, archive, TestFlight upload, physical-device installation, dependency change, backend/data change, deployment-target change, or version/build-number change was performed. The code remains isolated for review and simulator verification.

The locked Mac is the current blocker for live verification. The user has been asked to unlock it; authorization for the remaining work already exists.
