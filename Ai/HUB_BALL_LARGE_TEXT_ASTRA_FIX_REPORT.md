# Hub Ball enlarged text — fixes and native UI verification

Date: September 22, 2026

**Status: discovered code defects fixed and representative native UI checks completed. Full acceptance remains open for the explicit manual and unexercised cases below. This is not certification of every iPhone/iPad or every accessibility setting.**

Worktree: `/Users/sfrancoe/Projects/Hub Ball Large Text`
Branch: `codex/hub-ball-large-text`
Latest app implementation commit: `f2194ebe`
Latest native-test refinement: `708ce096`
Earlier implementation commits: `d924513b`, `1dac56ba`
Starting point: `5e00de1d` (Luna completion audit)

The owner authorized direct fixes and then explicitly authorized native Xcode UI tests. That removed the earlier Simulator-gesture blocker. The tests now use real XCTest taps, scrolling, rotation, text entry, sliders, sheets, background/foreground, and iPad window controls. The prior report's statements that native UI automation was pending or main-content scrolling was blocked are superseded.

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

### Follow-up fixes from live iPhone SE testing

- The enlarged page menu uses the available width. Removing the adjacent gear prevents the Standings heading from breaking mid-word; Teams and settings remains available within the menu and was opened successfully.
- Enlarged recap game selection is a semantic-font menu with the same selection bindings and full accessible game descriptions. Default-size game chips remain unchanged.
- Recap date/status and freshness content stack at enlarged sizes, preventing the date from fragmenting in a narrow column.
- The default nine-inning score table now accounts for all page/card/table padding. All nine innings and R/H/E/LOB are visible on the 375-point SE display. Additional innings retain horizontal scrolling; that interaction has not yet been verified.

### Story reading

- The Brewers story now has a dedicated expanded reading presentation using the existing event cursor, games, cumulative hitter credits, and recorded pitching events. Essential information is visible in scalable text rather than confined to the drawing or fixed-size labels.
- It includes the score, date/inning, selected play description and contributions, full hitter names/RBI/runs/hits, runs without an RBI, and pitcher innings/strikeouts/hits/walks.
- A recorded-play disclosure lets the reader select another event using the existing cursor. Player-moment links and chapter/playback controls remain available. Combined-game totals are derived from the same source as the compact story.
- Expanded transport is inside scrolling content so a fixed footer does not consume the small landscape viewport. Default story/chart presentation remains on its previous path.
- Home Run Chase explanatory copy and comparison-bar label/value layouts also adapt at enlarged sizes. Existing chart calculations, data, projection logic, and story facts are retained.

### Additional defects found and fixed with native UI tests

- **Unreachable lower player metrics:** nested lazy stacks produced unstable estimated heights and repeated scrolling without reaching the remaining career totals. The small player-detail shell and each 13/15-metric group now use eager stacks; season records remain lazy. All 15 batting and 13 pitching total values were subsequently reached on SE and Pro Max, with each metric required to fit fully in the visible content area.
- **Pitching scroll instability:** the small outer page shell is eager while the pitcher records remain lazy. The Actual/Forecast section is reachable after selecting Relievers.
- **Directory controls:** enlarged position, sort field, and sort direction use native menu pickers. This resolves the clipped sort label flagged by Apple's audit. The directory has one player iteration with the layout selected inside each row, avoiding inconsistent row reuse across layout changes.
- **Standings metrics:** at accessibility sizes the full label stacks above its value, avoiding a squeezed Winning percentage column.
- **Story cards:** enlarged cards place the icon above the title and summary. The full width is available for reading rather than splitting a title such as NINE PITCHES beside a large icon.
- **Brewers playback:** the enlarged playback label has its own full-width row, with Previous/Next beneath. Continue story wraps between words rather than breaking inside Continue.
- **Page-heading hit area:** the entire expanded heading rectangle responds to taps.
- **Narrow iPad windows:** on iPadOS 26, narrow content reserves space above the custom heading for system window controls. A real 375-point-wide window was tested and restored using native Window Controls / Zoom.
- **Repeatable checks:** a generated UI-test project, XCTest suite, test runner, and real system text-size coordinator are checked in. The release Xcode project is unchanged. A Debug-only onboarding reset permits testing the actual completion write; Release has no reset behavior.

## Verification method and evidence

Runtime for all native UI cases: **iOS/iPadOS 26.5**; Xcode 26.6; Debug simulator builds. Data is the app's existing bundled/live/cached data, including Roman Anthony, Payton Tolle, recent Boston games, and the recorded Brewers story. It is not a new adversarial fixture set. Default means `.large`; maximum means `.accessibility5`. Intermediate checks use `.xxxLarge` and `.accessibility3`.

Results and screenshot/tree attachments are under `dist/large-text-ui/`. Each `.xcresult` preserves test assertions, timing, and failure information; each exported `*-evidence/manifest.json` maps screenshots to test steps. See [native test instructions](</Users/sfrancoe/Projects/Hub Ball Large Text/ios/Hub Ball/LargeTextUITests/README.md>) and [actual test-result ledger](HUB_BALL_LARGE_TEXT_NATIVE_TEST_LEDGER.md). Evidence is gitignored and remains local to this worktree.

### Device and interaction coverage

| Check | Verified scope / evidence bundle |
|---|---|
| SE 3: all ten sections, default and maximum | Native navigation, three vertical scrolls, portrait/landscape screenshots for every section. `se-full2` maximum; `se-final` default. This samples each section; it does not inspect every lower row. |
| iPhone 16 Pro Max: all ten sections, default and maximum | Same native section/scroll/rotation checks. `promax-finish`. |
| iPhone 17: all ten sections, default and maximum | `iphone17-sections` maximum; `iphone17-default-final` default. |
| iPad mini: all ten sections, default and maximum | Portrait/landscape navigation and scroll sampling. `mini-sections-final`. |
| 13-inch iPad: all ten sections, default and maximum | Full-width portrait/landscape sampling. `ipad13-sections`. |
| Hitter/pitcher career totals | Fully visible values for all 15 batting / 13 pitching metrics on SE (`se-final`) and Pro Max (`promax-final`). Mini also reached all metrics after the scroll repair (`mini-career-fix`), before the stricter fully-visible assertion was added. |
| Career scope, sorting, detail return | Both MLB/minor-league scope, Year sort action, rotation/background, and return to retained Anthony search: SE (`se-coverage`), Pro Max (`promax-finish`), iPhone 17 (`iphone17-coverage`), mini (`mini-finish`). |
| Recap horizontal table/player link | Native scrolling reaches LOB without switching sections, then opens Roman Anthony from batting. SE (`se-full2`), Pro Max (`promax-core`), mini (`mini-core`). Default SE nine-inning fit was verified in the previous live audit. |
| Search keyboard/lifecycle | Keyboard visible, entered query retained through rotation/background: SE (`se-full2`), Pro Max (`promax-core`), mini (`mini-core`). |
| Actual system text-size changes | Anthony search and Chase slider retained across default → maximum → default without relaunching each flow. Pro Max (`promax-live-size2`), final app on iPhone 17 (`iphone17-live-final`). Original system text preferences restored; final values were rechecked on all five simulators, and native test teardown restored portrait. |
| Intermediate sizes | Players pickers, Recaps scrolling, Standings at xxxLarge/accessibility3: SE (`se-review`), Pro Max (`promax-review`). |
| Standings/Pitching/Leaders controls | Wild Card, Relievers, reachable Actual/Forecast, MLB leaderboard scope, category detail sheet and Close: SE (`se-final`); updated Pro Max (`promax-finish`). |
| Player filters/sort and story cards | Age ascending/descending, Pitchers, menu navigation to Stories, clipping audit. SE (`se-review`), Pro Max (`promax-finish`), mini (`mini-finish`), iPad 13 (`ipad13-finish`). |
| Settings | Teams and settings, Page Order, scrolling, Done: SE (`se-review`), Pro Max (`promax-finish`), iPad 13 (`ipad13-finish`). |
| Onboarding | Select Arizona Diamondbacks, complete Follow after rotation at default/xxxLarge/accessibility3/accessibility5: SE (`se-onboarding-visible`, with the entire Follow button visible), Pro Max (`promax-onboarding-final`), iPhone 17 (`iphone17-onboarding-final`), mini (`mini-finish`), iPad 13 (`ipad13-onboarding`). |
| Narrow iPad | Real 375 × 958-point window, Players/search/pickers/scrolling, full-width restoration: `ipad13-finish`. Additional Recaps/Standings captures: `ipad13-narrow-final`. |
| Game 108 / Nine Pitches | SE native playback/pause/reset/speed and background pause: `se-full2`. |
| Brewers story | SE Next play, progress to final play, combined chapter, cumulative contributors, bottom sources button and sheet dismissal: `se-final`. |
| Home Run Chase | Slider changes and value retention through rotation/background: SE (`se-full2`), Pro Max (`promax-review`), mini (`mini-core`). |
| Apple text-clipping audit | Home, Players, Standings displayed regions pass on SE (`se-review`), Pro Max (`promax-native-picker`, `promax-review`), mini (`mini-finish`), iPad 13 (`ipad13-review`). Story-card regions also audited in the picker/card tests. No audit issue was suppressed. |

The older successful cases above remain relevant to unchanged flows. Retests for the repaired layouts are identified separately. **A passing screenshot-producing case is evidence for its assertions and captured state, not blanket visual or accessibility approval.**

### Selected visual evidence

These images were inspected directly; the complete native attachments preserve other scroll positions.

- Brewers transport: [before](</Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-ui/se-full2-evidence/DF25E244-EA76-4C7B-BEAE-57AFCF52B0E6.png>) / [after](</Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-ui/se-final-evidence/FBDD800B-3EC3-4246-A1E2-1B785E343E06.png>).
- [Expanded story titles and summaries on iPad](</Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-ui/ipad13-finish-evidence/98A0B2D6-A00C-4E32-9F99-6CCA71A1959A.png>).
- [375-point iPad window with unobstructed Players heading](</Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-ui/ipad13-review-evidence/DDBB9855-1CF8-4928-B17C-C86EC294100A.png>).

- [SE maximum-text landscape with the full Follow button visible](</Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-ui/se-onboarding-visible-evidence/66F4EA2E-4CFC-4CC3-84A4-C754CE5EAB7A.png>).

### Builds and existing regression checks

- Final source: Debug Simulator build **PASS**, `dist/large-text-ui/final-debug-build.log`.
- Final source: unsigned generic-device Release build **PASS**, `dist/large-text-ui/final-release-build.log`.
- Earlier in this repair: Chase engine tests **PASS**; Brewers story data **3 tests PASS**; player careers **1,373 profiles across 30 teams PASS**. Those calculations/data were not changed by these follow-up layout fixes.
- Python runners compile, shell runner syntax and `git diff --check` pass.

### Failed attempts and their disposition

Initial runs exposed genuine scrolling/layout failures; those were fixed and the affected cases rerun. Several other failures were test-harness issues: tapping an offscreen default tab, swiping below a short system menu, capturing a rotation mid-animation, tapping a collapsed iPad window-control group, and pinning onboarding completion false with a launch argument. The retained result bundles show those failures. Do not count every bundle as a passing suite, and do not count skipped live-size cases as passes. The test now scrolls the actual native menu, waits for rotation, uses named window controls, and resets onboarding once rather than overriding its saved value.

## Completion-plan mapping

| Work package | Implementation / validation disposition |
|---|---|
| Players | All metrics and totals remain available; native scrolling, sorting/scope, filter return, keyboard, and live-size checks pass. Exhaustive data variants and spoken reading remain open. |
| Story/chart reading | Expanded alternatives and repaired controls implemented; each reachable story has a targeted interaction check. The remaining control/state matrix stays open. |
| App-wide layouts | Ten sections sampled on five simulators at default/maximum and portrait/landscape; targeted selectors, Settings, onboarding and narrow-window checks added. Uncommon content/error states remain open. |
| Verification | Builds and the recorded native cases pass as specified; historical failures are retained in the ledger. Full plan acceptance remains partial for the precise items below. |

## Remaining acceptance work — do not mark these passed

1. **Spoken VoiceOver:** labels/values and Apple's clipping audit were checked, but spoken output, focus order, rotor actions, and duplicate announcements were not heard and verified. Run the focused phone/iPad VoiceOver journey from the completion plan.
2. **iOS/iPadOS 17:** only 26.5 is installed. The deployment target remains 17; a successful build is not an older-runtime pass. Run the smoke journey when that runtime is available.
3. **Display Zoom:** no Display Zoom configuration was exercised. Dynamic Type and simulator magnification are separate settings.
4. **Adversarial/data-state cases:** extra innings, exhaustive missing-value/multi-team career variants, doubleheaders/TBD schedules, empty/error/Retry and stale feeds were not driven through a dedicated native fixture matrix. Recent recap coverage used nine-inning games.
5. **Full completion-plan breadth:** the native suite does not exhaust every story/player sheet, share/music/Reduce Motion action, every lower record, every intermediate category, every default-size detail, or every narrow-window layout. Search/Chase state retention is verified; it does not prove every feed/game/player selection survives every transition. These remain acceptance work, not claimed environment-only blockers.

No known failure from the targeted final layout checks is being recategorized as an OS limitation. These coverage limits are why the issue is not given an unrestricted app-wide sign-off.

## Release status

No merge, push, deployment, archive, TestFlight upload, physical-device installation, version/build-number change, dependency, generated-data, or backend change occurred. The fixes and test infrastructure remain on the isolated branch. Release remains a separate action from simulator verification.
