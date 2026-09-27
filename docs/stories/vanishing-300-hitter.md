# The vanishing .300 hitter

Native, offline MLB story, available through the global Stories button between the team selector and playoffs. The global library also links to the existing Boston, Milwaukee and Yankees stories. Team Stories pages keep their existing team-specific content.

## Current handoff — September 27, 2026

- Canonical checkout: `/Users/sfrancoe/Projects/Hub Ball`, branch `main`. Work from here for the next phone update. The chat’s original `/Users/sfrancoe/Projects/MLB Apps` checkout is archived and must not be used for releases or device installation.
- Hub Ball 1.0 build **75** was installed on Scott’s wired **iPhone 17** (`B3886736-9848-5385-A29E-9E9E7774EE91`) on September 27, 2026. Build 68 introduced the story; build 69 removed the baseball icon from the global team selector; build 70 tried a sixteen-second ambient melody. Build 71 tried a solo piano piece; build 72 removes music and its controls. Build 73 introduced compact stat cards. Build 74 stacks their labels and figures, and the first two open sorted player lists. Build 75 adds three-letter season-team abbreviations beside those players. Build 76 shortens the chart build to five seconds and moves replay into the chart. The homepage’s own baseball graphic remains.
- All changes from `codex/vanishing-hitter-story` were fast-forwarded into canonical main. Its managed worktree at `/Users/sfrancoe/.codex/worktrees/vanishing-hitter-story/MLB Apps` remains available, but is behind main’s release commits. Do not reinstall its older build. No push or TestFlight upload was performed for this work.
- Accepted visual choices: smaller single-line headline on both launch and story screens; line-only animation with peak/final/selected markers after completion; shared Stories entry; no baseball in the shared team selector; stacked stat cards (Peak · 1999 / 55, 2026 YTD / 7, vs Peak / −87%) with tappable peak and YTD rosters. Red Sox, Stories and 2026 Playoffs fit one row at standard iPhone text size; the accessible fallback can still use two rows.
- Current figures: **55 in 1999, seven in 2025, seven in 2026 YTD, −87%**. Exactly .300 counts. The older .301+ definition and six-player ending are superseded. 2026 is explicitly provisional, dated before September 27 games; never silently relabel it final.
- Verification completed: all 51 year taps, replay, methodology, source reconciliation and cutoff tests; standard header navigation and Red Sox/Cubs screenshots. Earlier compact and large-text checks also passed. Scott asked to remove the soundtrack entirely. Build 72 runs the story silently.
- Release workflow: read `AGENTS.md`, increment both Xcode build configurations and `config/hub-ball-release.json` together for a new phone build, commit intended files, run `python3 scripts/check_hub_ball_release.py`, then `bash scripts/install_hub_ball.sh --device B3886736-9848-5385-A29E-9E9E7774EE91`. Recheck connected devices first. Do not upload to TestFlight merely to update the wired phone.
- Leave the unrelated untracked planning/review documents and `docs/design/players-ipad-responsive.png` alone. They were present before this work and are not part of these changes.

## Definition and provenance

`MLB300HitterData.swift` contains generated counts from MLB’s qualified-hitter season totals. The cutoff is officially displayed AVG >= .300, **including exactly .300**. Every year was recalculated from MLB Stats API on September 27, 2026; the original .301+ handoff is superseded. The peak is 55 in 1999. Both 2025 and 2026 YTD have seven, a rounded 87% decline from the peak. 2024 also had seven.

Run `python3 scripts/fetch_hitter_story.py` to refresh all 51 years. It saves source URLs, retrieval time, displayed averages, hits, at-bats and plate appearances for every qualified player in `data/mlb300-hitters.json`, then regenerates the Swift season array and the two roster cards. The roster generator looks up each player's season team in MLB's year-specific leaderboard, then converts MLB's shorter labels to three-letter abbreviations where needed. Requests must all succeed, with complete leaderboards and unique player IDs, before output is written. Review the snapshot label and story copy after each refresh; the app does not fetch or update this data automatically.

Qualification uses MLB’s `playerPool=QUALIFIED` rather than a fixed 502-PA cutoff. This preserves MLB’s treatment of shortened seasons and batting-title exceptions. MLB’s combined season totals count each traded player once. Use the displayed average, not an unrounded H/AB comparison: a displayed .300 qualifies even if its underlying fraction is slightly lower.

## Components

- `MLB300HitterStory.swift`: full-screen presentation, launch overlay, stat cards, native vector chart, inspector, controls and methodology.
- `MLB300HitterData.swift`: dedicated season module and timing functions.
- `MLB300HitterPlayers.swift`: generated, sorted local player lists for the 1999 peak and 2026 YTD cards, sourced from the archived MLB leaderboard snapshot; year-specific team abbreviations come from MLB's season records.
- `StoriesView.swift`: optional team scope; nil shows the global library.

The primary path trims from zero to one over five seconds using monotonic elapsed time. The build shows only the line, with no year dots. Once complete, markers highlight the peak, final year, and tapped year. Reduced Motion reveals the completed chart immediately. A small red play button near the bottom of the chart resets the clock; the former full-width replay footer is gone. The story has no soundtrack or audio controls. Returning from the background shows the completed chart.

The Peak and 2026 YTD cards open scrollable player lists with three-letter season teams, sorted by official displayed average, highest first. The decline card is informational; 55 to 7 is a rounded 87% decrease, despite the requested mockup showing −81%. Every year can be selected by tapping its x-position or hovering, with a discrete Season slider for fine selection and VoiceOver. All values are also available in the methodology list. Long content scrolls at larger Dynamic Type sizes.

## Verification

Run `python3 scripts/test_hitter_story_source.py` to check the inclusive cutoff, complete/unique source rows, and reconciliation of all 51 counts. Run `bash scripts/test_hitter_story_data.sh` for series invariants and boundary timing.

Run the existing native UI harness with these methods:

```sh
bash scripts/test_large_text_ui.sh SIMULATOR_UUID hitter-story \
  testHitterStoryPlaybackAndAllSeasons \
  testHitterStoryGlobalNavigation \
  testHitterStoryLargeText \
  testHitterBackgroundAndCompactHeader \
  testHitterStatCardRosters
```

Debug routes: `-show-hitter-story` and `-show-story-library`.

## Future seasons

The user authorized including 2026 before the final games on September 27. It is explicitly marked YTD in the card, axis, endpoint callout, year inspector, accessibility descriptions and methodology. The chart retains 2025’s final seven, then adds 2026’s provisional seven. The ending is “Seven so far. Will it end at seven again?”

After the last games, fetch official qualified season totals again, apply the displayed AVG >= .300 cutoff, and update the count if needed. Only then remove the provisional flag and revise the snapshot date, narrative, question, methodology and tests to final-season wording. This snapshot does not refresh automatically.

## Verified in this implementation

- iPhone 17 Pro simulator: global navigation, full-screen launch/dismiss, year-by-year taps against the MLB-derived counts (extended to 51 points for the dated 2026 snapshot), five-second completion, in-chart replay, methodology sheet, and largest Dynamic Type layout.
- Compact iPhone simulator: largest-text header with the Diamondbacks label, silent launch, background/return behavior, and on-chart year selection.
- iPhone 17 Pro simulator: both stat-card sheets open, with the 1999 and 2026 player lists sorted by displayed batting average.
- Swift checks: season continuity, endpoints, peak, decline, and timing boundaries.

UI evidence is generated under `dist/hitter-preview/` and result bundles under `dist/large-text-ui/`; neither directory is committed. The development build 75 was installed and launched on Scott’s iPhone. No TestFlight release has been made for this story.
