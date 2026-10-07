# Hub Ball review validation and cleanup

October 6, 2026. Prepared by Codex for Scott.

Work remains on `codex/hub-ball-architecture-audit` in `/Users/sfrancoe/Projects/Hub Ball`. The three review commits were read in full and tested. **Validation is not fully green: rotation checks and recap Batting navigation remain unresolved. See the follow-up validation section for the latest results.** Cleanup commit: `b49fc08fd`. Additional commits: `2460f9f0f` (CDN ceiling) and `fc344dfed` (safe UI harness and navigation targets). Nothing was merged, pushed, deployed, uploaded, or installed on a physical device. Build 117 remains the declared release.

## Review commit findings

- `e5b8a1aa6`: implementation matches the cancellation fix. A restarted scheduler job awaits the cancelled job, and cancelled work does not update `lastAttempt`. The new `schedulerRetriesARefreshCancelledByLeaving` test passes.
- `0558ee1d1`: implementation and tests restore the go-ahead, biggest-swing, and walk-off wording, including club names for same-city matchups. The backend recap assertions pass.
- `5fa09c850`: normal, aged, expired, and invalid-date feed cases match the stated cache policy and pass. One edge case was found: `cacheHeaders` has a 300-second floor but no 86,400-second ceiling. With `now=2026-10-07T00:00:00Z` and `generated_at=2026-10-07T00:01:00Z`, it returns `max-age=86460`. A future timestamp therefore violates the later production acceptance ceiling. This was reproduced locally. A separate follow-up commit, `2460f9f0f`, now caps the lifetime at 86,400 seconds, with future-date and near-expiry regression tests. It is separate from the behavior-preserving cleanup commit.

## Cleanup commit

Removed unused scene-phase environment values from Home, Standings, October, and the postseason scorecard. Removed the ignored `StandingsView` team initializer and updated both callers. Removed the ineffective cancellation check in synchronous prediction persistence, corrected the nested catch indentation in `RecentGameStore`, and changed all five Netlify `FALLBACK_USER_AGENT` contact URLs to `https://api.autumnlane.io`. The existing exact User-Agent test expectation was updated accordingly. No deferred architectural changes were made.

## Initial validation results

- Native Swift Testing: **22 tests in 12 suites passed**, both before and after cleanup, using `python3 scripts/test_hub_ball.py`.
- Backend: **all seven `.mjs` test scripts passed**, before and after cleanup. Paid X requests use mocks.
- Python: **37 unit tests across eight scripts passed**, plus all 11 standalone adapter, registry, and generated-data checks. The latter cover all 30 teams and 1,367 player profiles.
- Web: both HTTP module checks passed against a locally built site.
- Swift 6 Release simulator build: **passed before and after cleanup**. This is not a device archive or release build distribution. Existing warnings remain for an unused Markets color, a deprecated SeasonLeaders `onChange` overload, and skipped AppIntents metadata extraction; no concurrency diagnostic was reported.
- UI, full 31-case iPhone 16 Pro Max suite: **18 passed, 11 failed, 2 skipped**. The skips are the iPad-only window case and live text-size changes that require the separate coordinator.
- UI, targeted iPad Pro run: **1 passed, 2 failed**. Architecture navigation passed; all-sections accessibility navigation and postseason rotation settling failed.
- UI after cleanup: architecture navigation passed again on iPad; an isolated retry of postseason landscape still timed out waiting for the app frame to rotate.

The all-sections tests launch normally, which opens the postseason cover, then attempt to operate the underlying Page menu. The failure log reports an unavailable menu; the screenshot confirms that the cover is still open. The iPad screenshot also shows clipped postseason statistics at the largest text size. These require separate test/layout review and are not fixed by the cleanup commit. They have not been established as regressions introduced by Claude's three commits.

The phone failures were:

| Test | Failed assertion or action |
| --- | --- |
| `testAllSectionsAccessibility5` | Native Page menu unavailable for scrolling. |
| `testAllSectionsDefault` | Home button not hittable. |
| `testHitterBackgroundAndCompactHeader` | Header button not hittable. |
| `testHitterStoryGlobalNavigation` | Hitter story card did not appear after tapping the header. |
| `testHomeRunChaseProjection` | Could not reveal Chapter 4. |
| `testPlayerMenusAndStoryCards` | Page navigation could not find Stories; player sorting/filtering assertions had already passed. |
| `testPlayoffsBracketAndGlobalNavigation` | Expected Wild Card navigation bar did not appear. |
| `testRecapScrollingAndPlayerNavigation` | LOB totals not visible after horizontal scrolling. |
| `testSelectorsAndDetailSheets` | Native Page menu unavailable for scrolling. |
| `testSettingsMenus` | Native Page menu unavailable for scrolling. |
| `testTextClippingAudit` | Apple's accessibility audit reported clipped text while the postseason cover was displayed. |

These are recorded failures, not an assertion that all eleven are product defects. Update test launch/navigation assumptions separately, then isolate the remaining layout and scrolling failures. Do not treat the current UI run as a passing release gate.

The stock UI shell runner fails with `OPTIONS[@]: unbound variable` when no methods are supplied under the system Bash. Explicit test names bypass that launcher problem. For the completed UI validation runs, an ignored copy of the test source injects a local API proxy; that proxy returns 503 for X discovery without forwarding it, while other API routes use the existing free backend. Product sources and committed UI assertions were not altered for this setup. The initial unprotected run was interrupted during navigation checks.

Evidence is local and ignored by Git: `dist/architecture-review-validation/` holds native, backend, Python, Release, and proxy logs; `dist/large-text-ui/review-phone-safe.xcresult`, `review-ipad-safe.xcresult`, `review-cleanup-navigation.xcresult`, and `review-ipad-rotation-retry.xcresult` hold the completed UI results. Matching `*-evidence/` folders contain exported screenshots and accessibility trees. The local proxy was stopped after testing.

## Follow-up validation and test harness

The test harness now starts a local, standard-library proxy for both ordinary UI runs and the live text-size coordinator. It returns 503 for X discovery without forwarding the request, permits only listed free API routes, and fails unknown routes closed. Three new offline proxy tests pass. Missing proxy configuration stops UI test setup before app launch. The stock shell runner's empty-array failure is also fixed.

UI tests now dismiss the normal-launch postseason cover when testing underlying pages, use the current Stories and Switch team buttons, expect the completed-game scorecard, and target the recap inning table by an accessibility identifier. These changes preserve product navigation and layout. The product-source change is only that test identifier.

Latest completed checks:

- Final native run: **22 tests / 12 suites passed** (`native-final.log`).
- Final Swift 6 Release simulator build: **passed** (`release-final.log`), with the same existing warnings listed above.
- CDN ceiling and feed-age tests: **passed** (`test_x_discovery-final.log`).
- Proxy tests: **3 passed** (`test_ui_test_proxy.log`); no real upstream requests.
- The 11-case targeted phone rerun (`fixes-targeted`) had **6 passes and 5 failures**. Hitter header/navigation, player menus/stories, selectors/detail sheets, settings, and the text-clipping audit passed. This clipping audit covers Home, Players, and Standings; it does not clear the postseason clipping previously observed.
- Live system text-size changes on iPhone SE: **passed**, including changing to maximum accessibility size and back while retaining state (`review-live-size-final`).
- Postseason button coverage: **passed** in `review-scorecard-final`. That run identified duplicate Done button labels in the scorecard test; its query was subsequently scoped to the scorecard.
- Final navigation rerun (`review-navigation-final`): **1 passed, 1 failed**. Playoff-to-scorecard navigation passed. Recap horizontal scrolling and LOB visibility passed; the test then failed locating the Batting section, before player-detail navigation could be verified. This remaining failure is not established as an architecture regression.

Rotation remains unresolved: the updated all-sections tests at default and maximum text size, plus the Home Run Chase projection test, time out waiting for a landscape app frame. Earlier iPad postseason rotation also timed out. Do not weaken these assertions or treat the suite as a passing release gate. The full suite has not been rerun after the test-harness adjustments. The earlier postseason statistics clipping still needs a dedicated layout review.

New UI result bundles and exported evidence are under `dist/large-text-ui/`; native, Release, backend, and Python logs are under `dist/architecture-review-validation/`. These directories are ignored by Git. All changes remain on the audit branch; no production verification or release preparation has been performed.

## Deferred follow ups

1. **iPad multi-window observers:** shared `AppModel` jobs use shared observer strings. Review per-window identities and visibility accounting so one window cannot stop another's refresh.
2. **Serialized decoding:** measure whether the shared `APIDecoder` actor delays unrelated responses before changing its isolation or concurrency strategy.
3. **Offline loading:** review `waitsForConnectivity` and the 60-second resource timeout so offline screens can show useful state promptly.
4. **Duplicate player stores:** consolidate the per-team `PlayersStore` owned by `TeamSession` with the separate cache in `AppModel`, preserving detail-view state.
5. **Recap fallback:** retain the on-device fallback through the server rollout; delete it one release after the server version ships.

The future-date CDN ceiling was subsequently fixed in `2460f9f0f`. UI results above describe the initial validation; see the rerun addendum below for current findings.

## After Scott approves and merges

Wait for the Netlify production deployment, then verify:

- `https://api.autumnlane.io/api/mlb/game?team=redsox&gamePk=824708`: under 100 KB uncompressed, schema 2, and narratives keyed by both participating team IDs.
- `/api/x-discovery?team=redsox&z=1`: HTTP 400. The valid `team=redsox` route: HTTP 200 and CDN lifetime consistent with feed age, bounded at 86,400 seconds with the specified 300-second floor.
- Observe Netlify logs for at most one paid X call per allowed team per UTC day. Do not manufacture extra paid calls to establish the limit.
- The old `red-sox.netlify.app` hostname continues serving the same endpoints for installed builds.
- Record an Instruments Time Profiler trace during a live game and verify no JSON decoding on the main thread. Prior process sampling is supporting evidence, not this required trace.

Only then prepare build 118 from canonical `main` through the normal release checks. Stop before TestFlight upload for Scott's approval. These production and release steps have not been performed in this pass.
