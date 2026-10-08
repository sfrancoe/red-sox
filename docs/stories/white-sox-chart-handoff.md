# White Sox chart: local release candidate

This implements Scott’s selected “A Whole Season of Wins. By June.” and a reusable
native remote-content renderer. Nothing in this task has been published, uploaded
or distributed. The canonical main checkout and its unrelated files are untouched.
The released version remains 1.1 (118); this checkout is a local preview, not a new
release source. The production story catalog still contains the Vilade story.

## What the reader gets

The White Sox’s cumulative wins for 2024, 2025 and 2026 draw automatically on
opening. Actual outcomes produce steps, never a smoothed or invented trajectory.
All three seasons share games 0–162 and wins 0–90. Eight seconds of playback include
a 0.9-second hold at Game 78, 41 wins, June 23, 2026. The chart then finishes at
41, 60 and 84 wins. Replay and pause are optional. Background/inactive time freezes
the elapsed clock; returning resumes without jumping. Reduced Motion immediately
shows the finished chart. Large text changes the layout; the chart’s accessible
axis/final-value summary and a complete data table support VoiceOver reading.
There is no sound, guess or mandatory reveal tap.

## Verified source

`scripts/build_white_sox_story.py` reads the official MLB schedules for team 145,
2024–2026. It includes only settled final regular-season games, deduplicates by
gamePk, orders by officialDate/doubleheader number/start time/gamePk, and checks
every winner-derived running record against leagueRecord. All 486 games reconcile.

| Season | Distinct final games | Wins | Losses |
| --- | ---: | ---: | ---: |
| 2024 | 162 | 41 | 121 |
| 2025 | 162 | 60 | 102 |
| 2026 | 162 | 84 | 78 |

| 2026 milestone | Game | Date | Record | gamePk |
| --- | ---: | --- | --- | ---: |
| Matches 2024 total | 78 | June 23 | 41–37 | 824584 |
| Passes 2024 total | 80 | June 26 | 42–38 | 824582 |
| Passes 2025 total | 117 | August 9 | 61–56 | 824564 |

`docs/stories/white-sox-story-source.json` preserves the ordered factual results,
retrieval timestamp, official source URLs and SHA-256 of each full response.
Raw responses are ignored local evidence under `dist/chart-story/sources`.
The original authored payload is `docs/stories/white-sox-story.json` (36,030 bytes),
SHA-256 `19053fba60d898c3a17ef01f1f4f5e6d246778208b27d9c45a93d28f34a6a8e7`.
It contains original text/chart data and sources, with no copied photos, video,
logos or music.

## Renderer and compatibility

`TrajectoryStory.swift` defines `chart-trajectory` renderer version 1, requiring
native capability 2. Transport schema remains 1. Line, step and grouped-bar modes
are generic; no team, season or baseball data is hardcoded into the renderer.
`scripts/story_content.py` mirrors validation. See `remote-stories.md` for exact
limits: fixed axes, finite ordered points, approved palette, bounded series/points,
bounded duration/holds and the existing 512 KiB payload cap.

`StoryDocument` dispatches between the retained guess/reveal model and charts.
The existing stores, two approved API hosts, redirect refusal, hash validation,
atomic last-good cache, bounded eviction, local preview, immutable publication
and rollback all remain. The bundled catalog and two seed files support a fresh
cold offline install. The preview-only catalog is under `dist/chart-story/data`;
it preserves the existing Vilade entry. No production catalog was changed.

Build 118 cannot render charts; it safely shows this entry’s summary and update
hint. This was tested against the preserved unchanged build-118 simulator app,
not only a capability assertion in new code. One further native update is needed.
After users install it, future stories within the chart contract can arrive as
remote JSON without a daily TestFlight update. New interaction primitives still
require a binary update. Discovery is foreground polling/refresh, not guaranteed
background notification delivery.

## Verification evidence

- Full real native suite: 36 tests / 14 suites passed, including real HTTP discovery
  after catalog changes with seeds disabled, exact cumulative data, emphasis timing,
  all three chart kinds, malformed data, capability gating, replay/foreground clock,
  cold offline seed, and downloaded-cache offline reopening.
- Small iPhone SE: autoplay/remote load/replay/foreground/offline; maximum text size,
  Reduced Motion, source and data sheets; normal completed preview.
- iPad: the same flows, plus remote synthetic line/bar rendering checks.
- Preserved build 118: new catalog entry opens the update fallback without a chart.
- Python unit aggregate: 117 tests passed (CLI simulator drivers excluded).
- All 10 Node test scripts passed; HTTP modules used a local built-site server,
  and X spending-cap tests used mocks. No paid discovery calls.
- Story/gateway/Netlify-ignore checks passed. Static site builds 1,718 files.
- Local packaging preflight: 14 pass, zero fail; existing manual review notes remain.
- Unsigned Release simulator build is recorded under `dist/chart-story/release-build.log`.

Logs, xcresults, raw response fixtures and screenshots live under ignored
`dist/chart-story` and `dist/large-text-ui`. Physical iPhone installation and actual
VoiceOver gestures are not claimed; accessibility labels and data are exposed in
the UI hierarchy and verified screenshots.

## Local preview and repeatable checks

```sh
python3 scripts/test_trajectory_story.py
python3 scripts/test_story_content.py
python3 scripts/test_hub_ball.py --suite TrajectoryStoryTests
python3 scripts/preview_stories.py --data-root dist/chart-story/data --fixtures --port 59244
```

Launch the Debug simulator with `HUB_STORY_ROOT=http://127.0.0.1:59244/data`.
`HUB_STORY_NO_SEED=1` proves downloaded discovery; omit it for cold offline seeds.
Use `scripts/test_large_text_ui.sh DEVICE RUN_NAME StoryUITests/testTrajectory…`
with both `HUB_UI_STORY_ROOT` and `HUB_UI_API_ROOT` pointing to the loopback origin.
Fixtures never forward real backend or paid API calls. `chart-line`/`chart-bar`
fixture controls generate explicitly synthetic local samples, never published.

## Release steps after new explicit approval

1. Read the current canonical release manifest, App Store Connect build inventory,
   registered worktrees, and latest remote main. Reconcile generated changes without
   overwriting unrelated files. Reserve the next unused build number (119 if still
   unused), updating Debug/Release CURRENT_PROJECT_VERSION and the manifest together.
2. Merge the local chart implementation into canonical main only within the new
   publication authorization. Revalidate source facts and the final story contract.
3. Stage the authored payload with the existing local publisher, retaining Vilade:
   `python3 scripts/publish_story.py stage --payload docs/stories/white-sox-story.json
   --summary 'Three seasons. One scale. Chicago matched its entire 2024 win total by
   Game 78 in 2026.' --teams 145 --data-root data` (one shell command).
4. Publish the SHA-named immutable payload first, leaving the existing public catalog
   pointer unchanged. Verify public raw bytes and exact SHA before publishing the
   new catalog and history. Synchronize the bundled catalog with that final catalog.
   The existing production gateway already accepts transport schema 1; no new
   service or backend renderer is required. Verify both API hosts and `/api/data`
   and `/data`, strong ETags/304, cache behavior, and staged rollback readiness.
5. Run native/content/UI checks, `python3 scripts/check_hub_ball_release.py`, and
   packaging preflight from the clean declared canonical main release. Follow the
   existing hub-ball-testflight skill for a signed archive and upload. It performs
   its own identity/version/archive and audience checks. Do not upload this preview
   as another build 118.
6. If distribution is authorized, keep the explicitly approved audience; Scott-only
   is the previous audience. Verify Apple processing and actual group membership,
   with no Family/external/public expansion. Update release notes for autoplay and
   new chart capability. Archive/upload/phone testing remain future steps.

The required next approvals cover new public publication and a new TestFlight
upload/distribution; prior approvals applied to Vilade/build 118 only.
