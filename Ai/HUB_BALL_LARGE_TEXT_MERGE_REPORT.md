# Hub Ball large-text integration into main

September 22, 2026

## Integration

- Canonical checkout: `/Users/sfrancoe/Projects/Hub Ball`, branch `main`.
- Latest GitHub data integrated from `e3576b4a` by merge `0f1089c5`.
- Large-text branch through `764dcb7f` integrated by merge `c308dd59`.
- Both merges completed without conflicts. Updated generated feeds and bundled player data came from GitHub; none were manually edited.
- The 14 previously unpublished main commits were reviewed. They include recap caching/retry and outage recovery, scheduling, player sorting and tablet layouts, onboarding menu order, privacy declarations/preflight checks, and the related news-refresh/backend reliability changes. Existing tests covering those changes passed again on merged main.
- Pre-existing untracked planning documents and `docs/design/players-ipad-responsive.png` were preserved and excluded from commits. Historical report whitespace was normalized without changing the findings.

## Validation on merged main

- Canonical release checker: PASS, version 1.0, build 63. All registered worktree build numbers checked.
- Unsigned generic-device Release build: PASS.
- Debug simulator build plus native UI regression checks: PASS.
- iPhone 16 Pro Max, iOS 26.5: all 15 batting and 13 pitching career total metrics reachable and fully visible; position/sort pickers and story cards; recap horizontal scrolling through LOB and player navigation; Home/Players/Standings text-clipping audit.
- iPhone SE 3, iOS 26.5: player pickers/story cards and text-clipping audit.
- Ten regression/preflight commands: zero failures. These cover news fetching, preflight validation, the MLB backend, player career data, Brewers story data, Chase calculations, ScheduleStore, RecentGameStore, real HTTP caching, and local app preflight.
- Local app preflight: 15 passed, five existing review warnings, zero failed, two skipped. This is not public App Store submission approval.
- Static-site packaging: PASS.
- Story facts rechecked after data integration: all four years remain 57–51 at game 108; the narrative beat values remain consistent.

Evidence in the canonical checkout:

- `dist/merge-large-text-audit/release-build.log`
- `dist/merge-large-text-audit/regression-results.json` and associated command logs
- `dist/merge-large-text-audit/story-facts.log`
- `dist/merge-large-text-audit/site-build.log`
- `dist/large-text-ui/merged-main-promax.xcresult`
- `dist/large-text-ui/merged-main-se.xcresult`

## Candidate and acceptance status

Version/build remain 1.0 (63). No new archive, TestFlight upload, tester notification, or physical-device install was performed as part of this integration. TestFlight distribution awaits the owner's audience choice; an upload must use an unused build number verified against Apple.

The earlier [fix report](HUB_BALL_LARGE_TEXT_ASTRA_FIX_REPORT.md) documents the broader five-simulator audit and the remaining spoken VoiceOver, Display Zoom, iOS 17, data-edge-case, and exhaustive acceptance coverage. Merging the fixes does not turn those open checks into passes.
