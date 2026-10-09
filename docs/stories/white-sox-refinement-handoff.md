# White Sox refinements — implementation handoff

The following records the verified local candidate before release. Scott subsequently
approved publishing it and delivering build 120 only to him. Current release status
and Apple/Netlify evidence are recorded in the release receipt, not inferred from
this historical implementation snapshot.

This candidate is implemented and tested locally. It has not been pushed, deployed,
uploaded to App Store Connect, or distributed. Release approval is still required.

## Source and release boundary

- Checkout: `/Users/sfrancoe/Documents/Codex/2026-10-08/task/hub-ball-chart-refinements`
- Branch: `codex/white-sox-refinements`, based on canonical main
  `6ea6b4322a9fdb0c4da77458f60030b48e279f85`.
- Implementation remains uncommitted for review. Canonical
  `/Users/sfrancoe/Projects/Hub Ball` main, its 24 existing untracked files, and its
  existing stashes were preserved.
- The currently distributed Scott-only TestFlight build is **1.1 (119)**. It has
  the previous simultaneous chart and launch behavior. This checkout's unchanged
  build number is not evidence that build 119 contains these refinements.
- New optional sequencing/comparison fields require renderer capability **3**.
  Wire renderer remains `chart-trajectory`, version 1, schema 1. Old chart payloads
  without these fields and guess/reveal stories retain their existing behavior.
- Candidate local catalog revision:
  `release-ea2f71ab31254d1c96a6dc4b82eb447c`.
- Candidate immutable payload SHA-256:
  `6324811453827288472a78036847e5165dcdbf47cfd98b0b66d73c0c42eef2d1`.
- The old production payload/catalog history are retained. All 486 game points,
  final totals (41, 60, 84), and sources are unchanged.

## Behavior

The chart draws 2024, then 2025, then 2026. Finished seasons remain visible and
future seasons are initially absent. Each season takes two seconds to draw.
The 2026 series reaches Game 78 / 41 wins at 4.962963 seconds, holds for two
seconds, then finishes at eight seconds. During the hold an arrow draws toward
2024's final Game 162 / 41 endpoint over 0.3 seconds, followed by exactly two
smooth 0.8-second pulses at 65–100% strength. The arrow and endpoint remain
visible afterward. Reduced Motion presents the final chart and static comparison.

A small red replay triangle sits immediately above the horizontal axis at its
right end, inside a 44×44 target, labeled “Replay chart from the beginning.” Replay
resets during playback and after completion; Pause/Resume and Explore the data
remain available. Playback pauses outside the foreground.

The featured White Sox card appears once per cold AppModel launch after onboarding.
Watch retains its position and Dismiss sits immediately to its right; both have
48-point label targets. Watch expands the sheet and opens/autoplays the story;
Dismiss closes without playback. Back returns to the card. Tab changes and
foregrounding do not reoffer the card or reset the user's navigation. The previous
15-minute foreground postseason-popup/navigation reset was removed.

## Relevant implementation paths

- Native configuration and validation: `ios/Hub Ball/Hub Ball/TrajectoryStory.swift`
  and `StoryCatalog.swift`.
- Reusable frame/sequence/pulse calculations:
  `ios/Hub Ball/Hub Ball/TrajectorySequence.swift`.
- Native drawing, playback, accessible comparison and replay:
  `ios/Hub Ball/Hub Ball/TrajectoryStoryView.swift`.
- Model-owned cold-launch policy and offer:
  `ios/Hub Ball/Hub Ball/FeaturedStoryOfferView.swift`, `TeamSession.swift`,
  `AppTabView.swift`, and reusable card actions in `StoriesView.swift`.
- Content generator: `scripts/build_white_sox_story.py`.
- Validation and local staging: `scripts/story_content.py`, `publish_story.py`.
- Candidate content: `docs/stories/white-sox-story.json`,
  `data/stories/catalog-v1.json`, the immutable payload under
  `data/stories/whole-season-by-june/`, and bundled `story-catalog.json` /
  `story-seed-whole-season-by-june.json`.
- Contract: `docs/stories/remote-stories.md`.
- Native tests: `HubBallTests/TrajectoryRefinementTests.swift` and
  `TrajectoryStoryTests.swift` under `ios/Hub Ball/`.
- UI tests: `ios/Hub Ball/LargeTextUITests/TrajectoryRefinementUITests.swift`.
- Python tests: `scripts/test_trajectory_story.py`; gateway tests:
  `scripts/test_story_gateway.mjs`.

## Verification and evidence

- Native: **40 tests in 15 suites passed**. Evidence:
  `dist/refinements/native-final.log` and `native-derived/test-results.log`.
- Python: **118 unit tests passed**. Evidence:
  `dist/refinements/python-unit-tests.log`.
- Story validator, six trajectory tests, five content tests, and Node story
  gateway checks passed. Capability 3 reaches both gateway catalog routes, with
  immutable hashes and bounded caching preserved.
- Final unsigned Release simulator build passed:
  `dist/refinements/release-final-build.log`.
- Small iPhone SE: all five refinement cases have passing proof across final
  focused runs. `dist/large-text-ui/refinements-se-verified.xcresult` covers
  replay during/after playback, foreground/back, milestone preview and largest
  text/Reduced Motion. `refinements-se-final-focus.xcresult` covers launch,
  Dismiss, tabs, foreground, next cold launch, and real onboarding.
- iPad: `dist/large-text-ui/refinements-ipad-verified.xcresult` passes launch,
  Dismiss/navigation, real onboarding, milestone preview and replay/back/
  foreground. `refinements-ipad-final-focus.xcresult` passes largest text,
  Reduced Motion, replay, static accessible comparison and opening the data
  table (one test, zero failures; final command exit 0). All five requested
  cases therefore have passing evidence on both devices across focused runs.
- Earlier failed attempts remain in `dist/large-text-ui/`. Parent accessibility
  identifiers and undersized action targets were corrected. Other failures were
  test assumptions about team-menu ordering, a reused older test runner, and
  scrolling outside the iPad's floating sheet. Passing focused runs supersede
  those attempts; this is not a claim that every earlier test bundle passed.
- Physical-device installation, spoken VoiceOver gestures, and older OS runtimes
  were not run. No signed archive or TestFlight upload was performed.
- Xcode's stalled SDK metadata probes were stopped individually to permit builds
  to continue. Unrelated processes and canonical work were not changed.

## Native previews saved privately in Library

| Preview | Library ID |
| --- | --- |
| Launch card | `libfile_afa57fd9e6e081918fa748881a7279d7` |
| Phone at the Game 78 comparison | `libfile_ec3196c037c48191a355559f8c167a43` |
| iPad at the Game 78 comparison | `libfile_cec505757e648191a9d10135e7d3b14f` |
| Largest text / Reduced Motion | `libfile_73ab8428da4c81919cdbd7ff37b756f6` |

Files are `dist/refinements/previews/white-sox-refined-*.png`. Exact file IDs and
persisted Library identities are in `dist/refinements/library-preview-receipt.json`.
The milestone screenshots use a Debug-only frozen time; production playback is
animated. These are native simulator captures, not generated mockups.

## Follow-up release sequence, after explicit approval

1. Review this candidate and its previews. Check fresh Apple build inventory,
   choose a new build number, and integrate the reviewed local changes into the
   canonical release path without disturbing existing work.
2. Run the release skill and required signed/device checks, archive, and upload
   the native capability-3 bootstrap. Preserve Scott-only distribution unless
   the user explicitly changes the audience.
3. Publish the validated immutable payload before the new catalog, then verify
   hashes, minimum-version filtering, existing story compatibility and rollout.
   Older clients must retain their last supported catalog/seed.
4. If needed, roll the catalog back to its retained previous revision. Native
   capabilities remain reusable for subsequent remotely supplied chart stories.

This task remains available for implementation or release follow-ups.
