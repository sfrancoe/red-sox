# Hub Ball enlarged-text handoff for Astra

Date: 2026-09-21

Branch: `codex/hub-ball-large-text`

Worktree: `/Users/sfrancoe/Projects/Hub Ball Large Text`

Base: `bfdd5d94` (`main` at the start of the task)

## What was done

Implemented all three stages from `docs/HUB_BALL_LARGE_TEXT_LUNA_PLAN.md` in three reviewable commits:

1. `df5560d3 Improve Home layouts for enlarged text`
2. `339b89c6 Remove enlarged-text suppression from core screens`
3. `d42bfd9e Complete enlarged-text layouts across app journey`

The implementation keeps the default-size presentation intact and switches to expanded reading layouts at `.xxxLarge` and above. It does not add a text-size cap or change data fetching, models, backend routes, deployment target, or release version.

### Stage 1 — Home and typography

- Added semantic Dynamic Type reference styles to the custom app fonts.
- Replaced the Home masthead overlay/hard-coded top gap with real layout space.
- Added expanded stacked records for last game, standings, and upcoming games.
- Preserved all existing values: R/H/E/LOB/SB, summaries, favorite highlighting, delayed data, starters, watch information, and navigation actions.

### Stage 2 — formerly capped screens

- Game Recaps now uses a single expanded reading column, stacked batting/pitching records, and a horizontally scrollable inning line score with R/H/E/LOB totals.
- Standings now shows one full team record at a time and retains league/division/wild-card context.
- X Posts uses one selected feed, wrapping post bodies and stacking metadata/actions.
- Onboarding is scrollable, keeps the largest accessibility size, and leaves team selection plus “Follow this team” reachable.
- Removed the affected production `.dynamicTypeSize(...)` restrictions.
- Expanded tab swipes are edge-only so horizontal tables do not accidentally change app pages.

### Stage 3 — remaining journey

- Navigation labels, settings, Players, Schedule, Newspapers, Leaders, and Pitching received expanded layouts.
- Players uses readable directory records, stacked biography fields, and taller aligned career rows.
- Schedule uses the existing schedule model as a chronological expanded list, including all remaining games and doubleheaders.
- Stories/detail screens keep vertical scrolling and reachable playback controls. Game 108 adds a scalable season-values summary beside the chart; story controls use readable touch targets.

## Validation completed

### Builds

- Debug simulator build passed with `xcodebuild` and dedicated DerivedData at `dist/large-text-derived-stage3`.
- Release generic iOS device build passed with signing disabled at `dist/large-text-derived-release`.
- Existing unrelated warnings remain in `MarketsView.swift`, `SeasonLeadersView.swift`, and App Intents metadata extraction.

### Device and text-size combinations

- Audit iPhone 16 Pro Max, iOS 26.5: Home at `large`, `xxxLarge`, `accessibility3`, and `accessibility5`; Recaps, Standings, X Posts, and onboarding at `accessibility5`.
- Audit iPhone SE, iOS 26.5: Home, Players, Schedule, Settings, Stories, and Game 108 playback at `accessibility5`; Home at `large`.
- iPhone 17, iOS 26.5: Home at `large` and `accessibility5`.
- iPad mini A17 Pro, iPadOS 26.5: Home at `large` and `accessibility5`.
- iPad Pro 13-inch M5, iPadOS 26.5: Home at `large` and `accessibility5`.

Simulator content-size settings were restored after testing. No physical device was installed, and nothing was merged, deployed, or uploaded to TestFlight.

### Actual simulator interactions

Using the visible Simulator UI and accessibility tree, I:

- Opened Recaps, Standings, X Posts, Players, Schedule, Settings, Stories, and Game 108.
- Opened onboarding, expanded the team picker, selected a different team, and completed “Follow this team.”
- Verified all Home metric groups, full standing records, schedule entries, player records, settings team/favorite actions, and Game 108 season values were exposed.
- Started story playback and verified the control changed from Play to Pause.

## Screenshots and audit report

Artifacts are in the gitignored `dist/large-text-audit/` directory:

- Before: `baseline/iphone16promax-default-home.png`
- Before: `baseline/iphone16promax-accessibility5-home.png`
- After Home: `final/iphone16promax-large-home.png`, `final/iphone16promax-xxxlarge-home.png`, `final/iphone16promax-accessibility3-home.png`, `final/iphone16promax-accessibility5-home.png`
- After core screens: `final/iphone16promax-accessibility5-recaps.png`, `final/iphone16promax-accessibility5-standings.png`, `final/iphone16promax-accessibility5-xposts.png`, `final/iphone16promax-accessibility5-onboarding.png`
- After Stage 3: `final/iphoneSE-accessibility5-players.png`, `final/iphoneSE-accessibility5-schedule.png`, `final/iphoneSE-accessibility5-settings.png`
- Device matrix Home pairs: `matrix/`
- Full audit: `dist/large-text-audit/report.md`

## Still outstanding

- Runtime validation was on iOS/iPadOS 26.5 only; iOS 17 runtime behavior is unverified.
- Landscape rotation, resized/narrow iPad windows, keyboard-visible player search, Display Zoom, and a dedicated spoken VoiceOver pass remain.
- Some chart/canvas labels remain fixed inside their drawings because they are coordinate-based. Game 108 and Pitching have adjacent scalable summaries; the remaining story charts may need the same treatment if largest-size story reading is a priority.
- The current branch is ready for review; do not merge or release until the remaining verification items are accepted.
