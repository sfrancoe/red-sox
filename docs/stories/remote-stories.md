# Remote editorial Stories

Hub Ball ships the native `guess-reveal` renderer once. Subsequent stories fitting
that renderer arrive as validated JSON through the existing data gateway. A new
interaction primitive still needs an app release. Existing compiled Stories stay
available. There is no downloaded Swift, JavaScript, HTML, WebKit, arbitrary asset
loading, or remote layout execution in this implementation.

## Native ownership and contract

- `ios/Hub Ball/Hub Ball/StoryCatalog.swift`: schema 1, renderer version 1,
  identity checks, text/count/numeric limits and SHA-256 payload verification.
- `StoryCatalogStore.swift`: AppModel-owned catalog/content loading through APIClient;
  approved HTTPS origins `api.autumnlane.io` and `red-sox.netlify.app`; redirects refused.
  Debug alone accepts loopback `HUB_STORY_ROOT` for previews.
- `StoryContentCache.swift`: last verified catalog and per-story payloads, atomic writes,
  total 8 MiB / 40 stories, catalog 128 KiB, payload 512 KiB. Corruption is ignored.
- `RemoteStoryView.swift`: native guess, reveal, stat cards, comparable bars, optional
  item passport with detail sheets, source/methodology sheet, replay and skip-guess.
- `StoriesView.swift`, `TeamSession.swift`: team-aware cards and the existing visible
  refresh scheduler. Polling is 60 seconds while visible, paused in background;
  pull-to-refresh bypasses caches. This is foreground discovery, not guaranteed
  background delivery or a notification service.

Catalog entries contain a stable slug, immutable SHA-256 revision, publication date,
team IDs, renderer capability, title, summary and text fallback. No URL is supplied
by an entry: the client derives `stories/<id>/<hash>.json` from its fixed origin.
Unknown renderers show the fallback and an update hint. Unknown schema/malformed
catalogs retain the last verified catalog. A bad new payload retains the prior
verified story with a visible note. An older valid catalog is accepted for rollback.

Payloads require 2–4 choices, a correct choice ID, original answer copy and citations;
they may include up to 6 stat cards, 8 bars and a 1–60-item passport. `barMaximum`
is optional; use a meaningful common denominator where values represent a share
(the stadium story uses 30). Omitting it compares against the largest bar. Sources
are HTTPS links without credentials. No ads, tracking, copied media or executable
content are introduced. The models and Python validator share field bounds.

`story-catalog.json` and `story-seed-this-stadium.json` are bundled and hash-verified.
They provide the selected story on a fresh offline install and during the private
preview before the production gateway/catalog exists. Cached later revisions take
precedence. The private beta therefore does not require a production deployment.

## Gateway and publication

`netlify/functions/app-data.mjs` permits only `stories/catalog-v1.json` and strict
slug/hash payload paths through both `/data/` and `/api/data/`. It checks upstream
response size, schema and immutable hashes. The catalog uses client revalidation,
CDN max-age 30 seconds, no stale-while-revalidate, and a strong ETag. Payloads are
immutable with a one-year cache. Existing feed routes/cache policies are unchanged.

The gateway currently reads public GitHub main. Public activation consequently needs
one approved gateway deployment and publication of the catalog/payloads to that main.
Neither a local staging command nor an uploaded private app activates remote Stories.
After gateway activation, content-only publication can use the repository's existing
data-only deploy-skip behavior; no daily native build or Netlify function deploy is
needed. Users must have installed the one-time renderer bootstrap build. Build 117
has a hardcoded library and cannot discover this catalog.

Always publish verified immutable payloads before switching the catalog. Commit
payloads and the pointer together when using GitHub's atomic tree publication.
Retain old payloads for cache safety and rollback. The local tools below do not
commit, push, deploy or upload anything:

```sh
python3 scripts/build_stadium_story.py
python3 scripts/publish_story.py stage \
  --payload docs/stories/stadium-story.json \
  --summary 'Two Vilade swings: 356 feet and 340 feet. Guess which one left the yard, then take it around all 30 parks.' \
  --teams 139,147 --data-root data
python3 scripts/validate_stories.py
python3 scripts/preview_stories.py --port 55622 --fixtures
# Debug simulator: HUB_STORY_ROOT=http://127.0.0.1:55622/data
# Preview controls: /__fixture/next, offline, rollback, reset, malformed,
# unsupported, payload-failure, redirect. Controls only exist with --fixtures.
python3 scripts/publish_story.py rollback \
  --catalog data/stories/catalog-history/<previous-revision>.json --data-root data
```

`publish_story.py` validates all referenced payloads before an atomic pointer switch,
saves previous catalogs, and refuses rewriting a hash-named payload with different
bytes. A rollback creates a new catalog revision referencing the saved content.
The preview server binds only loopback, never calls upstream or paid APIs, and serves
only permitted story paths. Its second story is synthetic test data, not publication.

## Selected story, sources and rights

`docs/stories/stadium-story-source.json` is a compact factual provenance record for
Ryan Vilade's October 7, 2026 ALDS Game 3 (MLB game 849838). The official game feed
records the second-inning flyout at 356 ft / 95.2 mph / 31 degrees and the fourth-inning
home run at 340 ft / 97.1 mph / 37 degrees. MLB's editorial report provides the modeled
park counts, 6 of 30 versus 1 of 30, and identifies Yankee Stadium as the sole park
for the shorter ball. The 30 venue names come from MLB's 2026 registry.

The passport represents only the 340-foot ball. The six parks for the first ball are
not individually identified by the report, so their identities are not invented.
Modeled park results are estimates, not guaranteed alternative game outcomes.
Original prose, SwiftUI flight motifs and stamps avoid copying MLB media, article
text, video, music or logos. Citation does not grant media reuse rights; new stories
must record provenance and confirm permissions before introducing third-party assets.

## Verification and release

```sh
python3 scripts/validate_stories.py
python3 scripts/test_story_content.py
node scripts/test_story_gateway.mjs
node scripts/test_app_data.mjs
python3 scripts/test_hub_ball.py --suite StoryContentTests
HUB_UI_STORY_ROOT=http://127.0.0.1:55622 HUB_UI_API_ROOT=http://127.0.0.1:55622 \
  bash scripts/test_large_text_ui.sh <simulator-id> <run-name> StoryUITests
```

The native suite checks cold offline seed, same-binary discovery, rollback, partial
failure, malformed/oversized/hash-invalid content, compatibility fallbacks, approved
origins, quiet cancellation, bounded cache/corruption and real HTTP redirect refusal.
UI tests use actual native catalog networking to discover a second story in the same
installed binary, reopen it after HTTP 503/relaunch, then remove it by catalog rollback.
They also test skip/replay, park details, sources, largest Dynamic Type and Reduce Motion.
Screenshots and accessibility trees are exported from XCTest results. Compact iPhone
and iPad are checked. Real VoiceOver gestures and physical-device installation remain
separate from these automated checks.

For TestFlight, use `/Users/sfrancoe/.codex/skills/hub-ball-testflight/SKILL.md` from the
canonical checkout on local main. Bump both Xcode configurations and the release
manifest together, preserve unrelated work, commit the intended release, run the
skill's `check` then `upload`, and verify Apple processing and exact group access.
A Scott-only preview must use the verified existing `Hub Ball Internal` group alone;
do not add it to Family, enable a public link, submit external review or expire builds.

Before wider rollout: approve/publish the gateway and content, verify both production
hosts/routes, then promote the tested bootstrap to the intended users. Next-day stories
within `guess-reveal` need source reconciliation, validation, preview, content publication
and a same-binary discovery check. The proposed pitcher-assignment and run-allocation
interactions are not implemented; add native primitives in a later binary if selected.


## Chart capability (local implementation; not released)

`chart-trajectory` renderer version 1 needs native capability 2. Build 118 only
supports capability 1 and shows the entry's factual fallback and update hint.
The catalog and transport payload schema remain 1, so the existing gateway can
serve these immutable payloads after publication is authorized. The chart has
its own typed model; it does not weaken guess/reveal validation.

`TrajectoryStory.swift` defines the declarative contract. A payload supplies
`title`, `kicker`, `intro`, `conclusion`, sources and methodology, plus a `chart`:
`kind` (`line`, `step`, `bar`), `durationSeconds`, `xAxis`, `yAxis`, `series`,
and `emphasis`. Each axis supplies its label, fixed minimum/maximum, and ticks.
Each series supplies a slug ID, label, approved palette color, and strictly
increasing `{x,y}` points spanning the x axis. Each emphasis supplies ID,
`x`, `y`, `holdSeconds`, title and detail. No formula, executable content,
arbitrary color, asset URL or team/year logic enters the renderer.

Bounds: 1–6 series; 2–600 points per series and at most 2,000 total; 2–8 sorted
unique ticks per axis; finite axis values within ±1,000,000; every point within
the fixed axes; 2–20 seconds total including at most eight 0–2 second holds,
with at least one second of sweep time. Bars have at most 60 points per series
and a zero baseline within the y axis. Bars reveal grouped values as the x axis
advances; step plots hold each actual value until the next point; line plots
interpolate directly between points. Neither line nor step paths are smoothed.
Sources and text use the existing bounded HTTPS contract and immutable SHA-256
checks. The transport cap remains 512 KiB.

`TrajectoryStoryView.swift` starts silent playback on opening, retains the final
chart, supports replay/pause, freezes elapsed time outside the foreground, and
resumes without a jump. Reduced Motion immediately shows the completed chart.
The Canvas has a spoken axis description and final-series summary; Explore the
data exposes every exact plotted value as accessible text. Sources remain
optional to open. All existing story and cache behavior is retained.

The White Sox preview is generated by `scripts/build_white_sox_story.py` from
`docs/stories/white-sox-story-source.json`; raw official responses are local
research evidence under ignored `dist/chart-story/sources`. `--refresh` retrieves
all three official schedules and reconciles every running record. This script
never publishes. The draft catalog is under ignored `dist/chart-story/data`,
retains the Vilade story, and is used only by loopback preview. The production
`data/stories/catalog-v1.json` is unchanged. The bundled bootstrap catalog includes
both stories for a fresh offline install.

Validation: `python3 scripts/test_trajectory_story.py`, `TrajectoryStoryTests`
in the real native test target, and `StoryUITests/testTrajectory*` in the existing
UI test runner. `testBuild118ChartShowsUpdateFallback` is run specifically with
the preserved build-118 simulator app, never against the new renderer.

Read-only fixture controls `chart-line` and `chart-bar` generate explicitly
synthetic local renderer checks in memory. They are never written into the
production catalog or included as bundled stories.
