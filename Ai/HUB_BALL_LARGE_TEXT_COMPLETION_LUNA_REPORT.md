# Hub Ball enlarged-text completion report

Date: 2026-09-21

Branch: codex/hub-ball-large-text

Worktree: /Users/sfrancoe/Projects/Hub Ball Large Text

Final implementation commit: edf075cff31820bd155261247467054af914861a

## Outcome

The completion plan is implemented on the existing isolated branch. Default-size layouts remain on their existing compact/grid/table paths. Enlarged layouts now use readable, reachable alternatives instead of shrinking text or suppressing content.

The final completion fixes were:

- Players directory: number moves below the player name on narrow phones; metadata stacks when width is constrained; search uses an intrinsic minimum height; enlarged iPad filters scroll horizontally instead of squeezing; biography values stop truncating; mode/scope controls have enlarged hit targets.
- Players career records: accessibility sizes use stacked season-record cards with full team names, level, every batting/pitching metric, season subtotals, career totals, and horizontally reachable sort controls. The compact frozen-column table remains unchanged at default sizes.
- Home Run Chase: expanded Chapter 4 exposes the calculated projection and all-time rank as visible text below the sliders.
- Nine Pitches: enlarged playback/reset controls can grow with their labels, and pitch accessibility labels include the result.
- Newspapers: enlarged source selection is horizontally reachable rather than squeezed into broken columns.
- X Posts: enlarged Recent/Liked selection is horizontally reachable rather than truncating the mode labels.

## Verification

Runtime available: iOS 26.5 only. All simulator evidence below is under:

/Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/

### PASS

- Debug simulator build after the final changes.
- Release generic iOS build after the final changes, with CODE_SIGNING_ALLOWED=NO. No archive, upload, or device installation was performed.
- Build metadata unchanged: marketing version 1.0; current project version/build 63.
- iPhone SE audit simulator, iOS 26.5, portrait, accessibility-extra-extra-extra-large (accessibility 5):
  - Home, Game Recaps, Standings, Schedule, Newspapers, X Posts, Players, Pitching, Leaders, and Stories.
  - Settings/team selection and restored Boston Red Sox state.
  - Players directory, filtered search with the keyboard visible, player biography, career records, sort controls, and totals.
  - Boston Nine Pitches playback/reset and Game 108 playback/restart/music/speed controls.
  - Milwaukee Who Built the 42 playback, chapter buttons, progress slider, player links, sources/share controls.
  - New York Home Run Chase chapter navigation and projection sliders/output.
- iPhone 16 Pro Max audit simulator, iOS 26.5: default large, xxxLarge, accessibility 3, and accessibility 5 Home evidence; existing live checks for Recaps, Standings, X Posts, onboarding, and settings are retained in the prior audit set.
- iPad Pro 13-inch audit simulator, iOS 26.5, portrait, accessibility 5: Home, Players directory, player biography/career records, expanded filters, sort controls, and totals.
- iPhone 17 simulator, iOS 26.5: default Home and accessibility-5 Home/Players/Stories screenshots.
- Before/after/default-size evidence is present in the prior audit set and the new completion set.

### Evidence screenshots

- iPhone SE Home access 5: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-se/home-access5-final.png
- iPhone SE Players access 5: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-se/players-access5.png
- iPhone SE career access 5: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-se/player-career-access5.png
- iPhone SE filtered search with keyboard: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-se/players-search-keyboard-access5.png
- iPhone SE Newspapers access 5: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-se/newspapers-access5-final.png
- iPhone SE X Posts access 5: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-se/xposts-access5-final.png
- iPhone SE Nine Pitches before playback: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-se/nine-pitches-before.png
- iPhone SE Nine Pitches after playback: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-se/nine-pitches-after-play.png
- iPhone SE Game 108 access 5: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-se/game108-access5.png
- iPhone SE Brewers story access 5: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-se/brewers-shutout-access5.png
- iPhone SE Home Run Chase projection access 5: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-se/home-run-chase-access5-projection.png
- iPhone 16 Pro Max default Home: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-16-pro-max/home-large.png
- iPhone 16 Pro Max access 5 Home: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-16-pro-max/home-access5.png
- iPad Pro 13 access 5 player career: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/ipad-pro/player-career-access5.png
- iPhone 17 default Home: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-17/home-large.png
- iPhone 17 access 5 Players: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-17/players-access5.png
- iPhone 17 access 5 Stories: /Users/sfrancoe/Projects/Hub Ball Large Text/dist/large-text-completion-audit/iphone-17/stories-access5.png

## Verification ledger

| Check | Result | Evidence/action |
|---|---|---|
| Debug simulator build | PASS | xcodebuild Debug iphonesimulator build |
| Release generic build | PASS | xcodebuild Release iphoneos generic build, CODE_SIGNING_ALLOWED=NO |
| Default-size appearance | PASS | iPhone 16 Pro Max default Home screenshot and prior baseline/final pair |
| SE all ten sections at access 5 | PASS | Live CUA navigation plus AX tree checks |
| SE onboarding/settings/details at access 5 | PASS | Settings/team flow and Players detail live checks; onboarding retained from prior audit |
| iPhone 16 Pro Max intermediate sizes | PASS | large, xxxLarge, access 3, access 5 Home evidence; prior section checks |
| iPhone 17 primary default | PASS | Default Home screenshot |
| iPhone 17 Home/Players/Stories access 5 | PASS | Simulator screenshots |
| iPad Pro 13 portrait access 5 | PASS | Home, directory, biography/career live checks and screenshots |
| Boston, Milwaukee, New York story controls at access 5 | PASS | Live chapter/playback/slider/source/share checks |
| Filtered Players search with keyboard | PASS | Live SE search field and keyboard AX tree |
| Phone landscape SE and iPhone 16 Pro Max | UNVERIFIED | No final landscape interaction/screenshot captured |
| iPad mini and iPad Pro landscape | UNVERIFIED | iPad Pro portrait was exercised; the attempted toolbar rotation did not change the captured orientation |
| Resized/narrow iPad window | UNVERIFIED | No resizable-window pass completed |
| Text-size changes while filtered/selected/inside details | UNVERIFIED | Individual states were checked, but the full change-in-place matrix was not completed |
| Background/foreground lifecycle | UNVERIFIED | Not fully exercised for every selected/filtered state |
| VoiceOver spoken-output pass | UNVERIFIED | Accessibility trees and labels were checked through simulator automation; actual VoiceOver speech was not independently audited |
| Display Zoom | UNVERIFIED | No separate Display Zoom configuration was available in this run |
| iOS 17 runtime | UNVERIFIED | Only iOS 26.5 is installed on this host |

## Explicit non-actions

No merge, deploy, TestFlight upload, build-number change, physical-device install, or production release action was performed.
