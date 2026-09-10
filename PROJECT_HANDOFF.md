# MLB Apps / Hub Ball — Project Handoff

**Prepared:** September 7, 2026  
**Repository:** <https://github.com/sfrancoe/red-sox>  
**Local checkout:** `/Users/sfrancoe/Projects/MLB Apps`  
**Current branch:** `codex/redsox-markets`

## Purpose of this document

**Deferred product idea (September 8, 2026):** See [X content — idea to revisit](docs/x-content-future-direction.md) for the user's preferred official-embed plus in-app-browser concept and unresolved permission questions.

This is a technical handoff for reviewing the current project and planning the expansion from four supported MLB teams to all 30 teams. It describes the code as it exists in this checkout, including uncommitted work. It is more current than `README.md` and `CLAUDE.md`, which still primarily describe the original Red Sox storytelling site.

Before changing code, read `AGENTS.md`. It contains project-specific constraints and deployment safety rules.

**Product naming was superseded on September 8, 2026.** The canonical product map is
[`docs/PRODUCTS.md`](docs/PRODUCTS.md). Hub Ball is active, Boston Baseball Hub is the
legacy App Store identity, and the standalone Yankees app is retired. Yankees references
below describe team support within Hub Ball unless explicitly marked historical.

## Executive summary

The repository now contains two related product surfaces:

1. A dependency-free static website built with HTML, CSS, JavaScript ES modules, and Canvas.
2. The active multi-team SwiftUI iPhone/iPad application, **Hub Ball**.

There are two App Store identities: active **Hub Ball** (`com.sfrancoe.HubBall`) and
legacy **Boston Baseball Hub** (`com.sfrancoe.Red-Sox-Records`). The legacy source is
kept in Git history instead of a duplicate working-tree project.

The shared backend is not a conventional application server. Python scripts fetch public data and commit generated JSON into Git. Netlify serves the static website and provides several JavaScript serverless functions that proxy either generated JSON or live upstream data. The native app reads from `https://red-sox.netlify.app`.

The current multi-team app supports:

| Team | MLB ID | API key | Data path |
|---|---:|---|---|
| Boston Red Sox | 111 | `redsox` | root `data/` files |
| New York Yankees | 147 | `yankees` | `data/yankees/` |
| New York Mets | 121 | `mets` | `data/mets/` |
| Tampa Bay Rays | 139 | `rays` | `data/rays/` |

The main scaling problem is duplication. Yankees, Mets, and Rays each have nearly identical Python fetchers and GitHub Actions workflows. The five repeated fetcher families alone total about 3,900 lines for those three teams. Repeating this structure for 26 more teams would be expensive to build, review, and maintain.

## Important current state

This checkout is not clean. At the time of this handoff it contains:

- 51 modified tracked files, totaling approximately 1,543 insertions and 1,272 deletions.
- Untracked Rays workflows, Rays fetchers, Rays generated data, home-screen code, and Red Sox odds work.
- Changes spanning the website, Netlify functions, both iOS projects, generated data, documentation, and tests.

Do not discard or overwrite these changes. Inspect `git status --short` and `git diff` before editing. The untracked Rays work is especially important because it may not yet exist on `main` or production.

## Technology and dependency policy

### Website and functions

- Plain HTML and CSS.
- Browser JavaScript uses native ES modules.
- Animated story graphics use `<canvas>`.
- Audio uses the Web Audio API.
- Netlify Functions use `.mjs` modules and the platform runtime.
- There is no `package.json`, npm dependency tree, framework, or bundler.

### Data generation

- Python 3.12 in GitHub Actions.
- Python standard library only.
- MLB data primarily comes from the public MLB Stats API.
- Some news feeds are RSS; some newspaper pages require custom HTML/JSON extraction.
- Generated JSON is committed to the repository.

### Native applications

- SwiftUI.
- Minimum iOS deployment target: iOS 17.0.
- Swift language setting: Swift 5.
- Targets iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`).
- No external Swift package dependencies were observed.

Do not introduce npm, React, Vite, webpack, a charting library, CDN scripts, pip dependencies, or a paid API without explicit approval.

## Repository layout

```text
MLB Apps/
├── AGENTS.md                     Required operating and safety rules
├── CLAUDE.md                     Older overview focused on the original site
├── README.md                     Public-facing overview; partly out of date
├── PROJECT_HANDOFF.md            This document
├── index.html                    Static-site landing/home page
├── src/                          Shared browser JS and CSS
├── stories/                      Canvas-based visual stories
├── data/                         Generated JSON served to web/native clients
├── scripts/                      Python fetchers, tests, and build scripts
├── netlify/functions/            Netlify serverless functions
├── netlify.toml                  Netlify build, routing, and cache configuration
├── .github/workflows/            Scheduled data/news refresh jobs
├── ios/
│   ├── Hub Ball/                 Current multi-team Hub Ball app
│   └── IPAD_REVIEW.md            iPad review notes
├── app-store/                    App Store metadata and release checklist
├── docs/                         Data-source and backend documentation
├── assets/fonts/                 Self-hosted Anton and Oswald fonts
├── _site/                        Generated static build; gitignored
└── dist/                         Generated portable builds; gitignored
```

## Product 1: static website

### Page structure

The root `index.html` is the landing/home page. Additional pages live in directories so Netlify can expose clean paths:

- `news/index.html`
- `recent-game/index.html`
- `schedule/index.html`
- `standings/index.html`
- `pitching/index.html`
- `x-posts/index.html`
- `privacy/index.html`
- `herald/index.html`

Shared web behavior and styling live in `src/`. Important modules include:

- `src/chart.js`: shared Canvas animation engine.
- `src/audio.js`: shared Web Audio engine.
- `src/home.js` and `src/home-game.js`: newer home-page behavior.
- `src/recent-game.js` and `src/recent-game-feed.js`: game recap UI and feed handling.
- `src/schedule.js`, `src/standings.js`, `src/pitching.js`, `src/news.js`, and `src/x-posts.js`: page-specific rendering.
- `src/site-shell.css`: common page shell.
- Feature-specific `.css` files sit beside their JS modules.

### Visual stories

`stories/four-roads/` contains the finished story **Four Roads, One Record**. Its `story.js` supplies colors, copy, labels, and narrative beats to the shared `initStory` engine in `src/chart.js`.

`stories/war-room/` is an unlisted mockup. Its WAR values are frozen and its overnight deltas are invented for presentation. It must not be presented as live or factual without building a real data pipeline.

### Website build

The website is not compiled or bundled. `scripts/build_site.sh` copies the public files into `_site/`. Netlify runs:

```bash
bash scripts/build_site.sh
```

and publishes `_site/`.

For local development, build and use an HTTP server:

```bash
bash scripts/build_site.sh
cd _site
python3 -m http.server 8765
```

Then open `http://localhost:8765`. Do not test with `file://`; ES-module imports and JSON `fetch()` calls require an HTTP origin.

`scripts/build_single_file.py` produces portable HTML under `dist/`. Neither `_site/` nor `dist/` should be committed.

## Product 2: multi-team Hub Ball iOS app

The current app lives at:

```text
ios/Hub Ball/Hub Ball.xcodeproj
ios/Hub Ball/Hub Ball/
```

Its directory, target, scheme, product, and navigation branding are all “Hub Ball.” It
supports switching among multiple teams.

### Entry and navigation

- `HubBallApp.swift`: SwiftUI `@main` entry point.
- `ContentView.swift`: initial application content.
- `AppTabView.swift`: main navigation, sidebar, tab availability, onboarding, selected-team persistence, and root view switching.
- `TeamSettingsView.swift`: team selection UI.
- `HubTeam.swift`: the central team enum and current team metadata.
- `AppTheme.swift`: shared visual tokens and team-sensitive styling.

The selected team is stored with `@AppStorage`. `AppTabView` passes a `HubTeam` into team-aware views and stores. Changing teams recreates the selected content using `.id(team.id)`.

### Feature layering

Most native features have a model, store, and view:

```text
Schedule.swift        ScheduleStore.swift        ScheduleView.swift
RecentGame.swift      RecentGameStore.swift      RecentGameView.swift
Standings.swift       StandingsStore.swift       StandingsView.swift
Pitching.swift        PitchingStore.swift        PitchingView.swift
SeasonLeaders.swift   SeasonLeadersStore.swift   SeasonLeadersView.swift
NewsFeed.swift        HeadlinesStore.swift       HeadlinesView.swift
                      XPostsStore.swift           XPostsView.swift
Players.swift         PlayersStore.swift         PlayersView.swift
```

Additional views include `HomeView`, `StoriesView`, `MarketsView`, and `Game108GraphView`.

### Team capabilities

`HubTeam.swift` currently hard-codes one Swift enum case per supported team and uses repeated `switch` statements for:

- MLB team ID.
- Full, short, and city names.
- Abbreviations.
- API key and data-directory name.
- Newspaper source selection.
- Feature availability.

All four teams currently support the Home tab. Player profiles and published stories are Red Sox-only. Other tabs are generally shown for every team.

### Native data access

`AppBackend.swift` centralizes URLs:

- Production generated data: `https://red-sox.netlify.app/api/data/...`
- Production live endpoints: `https://red-sox.netlify.app/api/<endpoint>?team=<key>`
- Debug generated data can be redirected with the `HUB_DATA_ROOT` environment variable.

Boston generated files sit at the data root for historical compatibility. Other teams are nested under a team slug.

### iOS build

Open the `.xcodeproj` directly in Xcode or build from the command line:

```bash
xcodebuild \
  -project "ios/Hub Ball/Hub Ball.xcodeproj" \
  -scheme "Hub Ball" \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Current settings include marketing version `1.0`, build number `8`, and bundle identifier `com.sfrancoe.HubBall`.

## Legacy product identity: Boston Baseball Hub

The prior Boston-only App Store identity is canonically named **Boston Baseball Hub**
and retains bundle identifier `com.sfrancoe.Red-Sox-Records` until retirement. It has no
duplicate source tree in the current checkout. If a critical maintenance release is
needed, recover the appropriate source from Git history in a temporary worktree.

The former standalone Yankees app is retired. Yankees feeds remain part of the data
architecture because the Yankees are a selectable team inside Hub Ball.

## Data architecture

### Generated files

Boston uses legacy root paths such as:

```text
data/schedule.json
data/recent-game.json
data/standings.json
data/pitching.json
data/seasons.json
data/meta.json
data/players.json
```

The additional teams use namespaced paths:

```text
data/yankees/{schedule,recent-game,standings,pitching,seasons,meta}.json
data/mets/{schedule,recent-game,standings,pitching,seasons,meta}.json
data/rays/{schedule,recent-game,standings,pitching,seasons,meta}.json
```

Each team directory also contains team-specific news JSON. Source availability differs by market.

Do not hand-edit generated JSON. Change the corresponding fetcher, run it, validate its output, and commit both code and generated output as appropriate.

### Fetch scripts

Boston's older scripts use unqualified names such as:

- `fetch_schedule.py`
- `fetch_recent_game.py`
- `fetch_standings.py`
- `fetch_pitching.py`
- `fetch_seasons.py`

Yankees, Mets, and Rays each have a separate copy of those fetchers, such as `fetch_yankees_schedule.py` and `fetch_rays_pitching.py`. Most differences are team ID, display name, slug, output path, and user-agent string.

News is less uniform. New York teams use NY Times, NY Post, Daily News, and Athletic sources. Tampa Bay currently uses Tampa Bay Times and Athletic. Boston uses Globe, Herald, Athletic, and MassLive fetchers.

### Serverless functions

Important functions in `netlify/functions/` include:

- `app-data.mjs`: allowlisted proxy for generated JSON stored on the repository's `main` branch.
- `mlb-data.mjs`: team-aware live MLB data gateway.
- `x-posts.mjs`: team-specific X-list filtering and response generation.
- `x-discovery.mjs`: team-aware X discovery configuration.
- `redsox-odds.mjs`: current Red Sox odds endpoint.
- `redsox-markets.mjs`: Red Sox market normalization/endpoint.

`netlify.toml` maps functions to `/api/...`, controls caching, and publishes `_site/`. Generated-data and iOS-only commits may skip a static-site rebuild, while function or privacy-page changes still deploy.

### Production dependency

The native app always uses `https://red-sox.netlify.app` in production. A team is not ready merely because its local JSON exists. Before an app build exposes a new team:

1. Commit and publish its generated `data/<team>/` files.
2. Add the team to relevant Netlify function configuration and allowlists.
3. Merge/deploy to production.
4. Verify representative production responses, including `/data/<team>/standings.json` and `/api/x-posts?team=<team>`.
5. Only then expose the team in the native picker.

Otherwise installed devices will show missing or cross-team data even when local tests pass.

## Automation and deployment

GitHub Actions currently uses separate workflows for Boston and each additional team.

- Game/schedule/standings/pitching feeds run approximately every two hours.
- Season/leader feeds run daily.
- Newspaper feeds run every 5–10 minutes depending on source/team.
- All write-capable jobs share the `site-data-writes` concurrency group.
- Jobs commit changed JSON back to `main` using the GitHub Actions bot.
- Many jobs use `git pull --rebase` before pushing to reduce collisions.
- Netlify auto-deploys relevant changes from `main`.

Separate per-team workflows are workable for four teams but would become unwieldy at 30 teams. A matrix job or a single registry-driven refresh command is the natural replacement.

## Tests and current verification status

The following tests passed in this working tree on September 7, 2026:

```text
scripts/test_app_data.mjs
scripts/test_mlb_data.mjs
scripts/test_x_discovery.mjs
scripts/test_x_posts.mjs
scripts/test_redsox_odds.mjs
scripts/test_yankees_data.py
scripts/test_mets_data.py
scripts/test_rays_data.py
scripts/test_open_players.py
scripts/test_players.py
```

The Hub Ball Xcode project also completed a Debug build for the generic iOS Simulator with code signing disabled.

These browser-oriented tests were invoked without the required local HTTP server and failed only because nothing was listening on port 8765:

```text
scripts/test_recent_game.mjs
scripts/test_schedule.mjs
scripts/test_home_game.mjs
```

That is an environmental precondition, not evidence of an application assertion failure. Re-run them after building `_site/` and starting `python3 -m http.server 8765` from that directory.

This verification did not include live production endpoint checks, simulator UI interaction, visual regression testing, App Store preflight, or a fresh run of every network fetcher.

## Current issues and risks

### 1. Per-team code duplication

This is the largest technical issue. Five fetcher families are copied for each team, workflows are copied per team, Netlify configuration repeats team keys and allowed paths, tests are largely team-specific, and the Swift team enum contains repeated switches.

Consequences:

- Fixes must be applied in several places.
- Teams can drift subtly in output shape or behavior.
- Adding 26 teams multiplies files and scheduled jobs.
- Every future review requires much more context.

### 2. There is no single source of truth for team metadata

Team identity is currently repeated across Swift, Python, JavaScript functions, tests, workflow filenames, news-source definitions, X filters, and output paths. An incorrect MLB ID, slug, abbreviation, or path in one layer can produce cross-team or missing data.

### 3. The working tree mixes several unfinished efforts

Rays support, Hub Ball UI changes, home-game functionality, odds/markets work, website redesign, data refreshes, and App Store metadata changes are all present together on `codex/redsox-markets`. This makes review, rollback, deployment sequencing, and attribution difficult.

### 4. Rays availability must be verified in production

Rays files and workflows are currently untracked locally. Their presence in this checkout does not guarantee that production serves them. The app must not rely on them until the files and Netlify configuration are merged, deployed, and checked on `red-sox.netlify.app`.

### 5. Product architecture is in transition

The repo began as a Red Sox storytelling website, briefly gained a Yankees-specific app,
and now contains the multi-team Hub Ball app. The product decision is settled in
`docs/PRODUCTS.md`: Hub Ball is active, Boston Baseball Hub is legacy, and the standalone
Yankees app is retired.

Questions that need resolution:

- Which features should every team receive?
- Are Red Sox-only stories and player profiles acceptable inside a general app?

### 6. News and X cannot be generalized as mechanically as MLB data

Schedule, standings, recaps, pitching, and leaders can be driven by MLB team IDs. News and social feeds require market-specific sources, filters, aliases, exclusions, and editorial validation. Ambiguous names such as Giants, Cardinals, Rangers, Nationals, Angels, and Athletics increase false-positive risk.

### 7. Boston has legacy path exceptions

Boston data lives at the root while every other team uses a subdirectory. This compatibility exception complicates generic code and testing. It should either be deliberately retained behind one abstraction or migrated carefully with backward-compatible routing.

### 8. CI scale and commit contention

The current design creates multiple scheduled workflows that all commit generated files to the same branch. Thirty teams could mean hundreds of fetch commands, overlapping schedules, frequent rebases, noisy commits, and pressure on GitHub Actions and upstream sources.

### 9. Generated data is mixed with source code and app resources

Generated JSON is intentionally versioned. Hub Ball consumes the published team feeds;
there is no longer a second set of bundled Yankees resources to synchronize.

### 10. Documentation drift

`README.md` and `CLAUDE.md` still describe a small Red Sox static site and do not explain the full multi-team/native/backend system. Treat this file and the actual code as the more current starting point, but verify decisions against `git diff` because the checkout contains unfinished changes.

## Recommended architecture for all 30 teams

The lowest-maintenance approach is to generalize the four known-good teams before adding the remaining 26.

### Shared team registry

Create one canonical, machine-readable registry containing at least:

```text
slug
MLB team ID
full name
short name
city
abbreviation
league and division
primary/secondary colors
data path
feature flags
news sources
X list/filter terms and exclusions
```

Because Swift cannot directly import Python or JavaScript configuration, either generate language-specific artifacts from one registry or choose one authoritative file and validate that the other layers match it. Do not maintain 30 independent handwritten switch trees without cross-layer validation.

### Generic fetch commands

Replace copied scripts with shared implementations that accept a team slug, for example:

```bash
python3 scripts/fetch_team.py rays schedule
python3 scripts/fetch_team.py mets all
python3 scripts/fetch_team.py --all mlb-data
```

Keep news adapters pluggable because each publisher behaves differently.

### Matrix-based automation

Use a small number of GitHub Actions workflows with a team matrix or a single all-team command. Prefer one final commit per refresh class rather than one commit per team. Retain concurrency protection and fail loudly if any team returns mismatched identity or malformed data.

### Parameterized tests

Validate every configured team for:

- Correct MLB team ID and identity.
- Required generated files and JSON shape.
- No opponent data presented as the selected team.
- Correct schedule/recap home-away selection.
- Division and Wild Card inclusion.
- Production endpoint availability.
- News/X relevance and source attribution when those features are enabled.

### Staged rollout

1. Stabilize and deploy the existing Rays work.
2. Generalize the four supported teams without changing behavior.
3. Add all teams for deterministic MLB-backed features.
4. Deploy and verify production data before exposing them in the app.
5. Add curated news and X support as a separate editorial/data-quality phase.

## Non-obvious constraints

- `data/seasons.json` and `data/meta.json` are generated; never hand-edit them.
- In season data, `diff` and `seq` must have the same length and derive from the same completed-game walk.
- The Four Roads story depends on a premise check: 57–51 after 108 games for four seasons. If the check fails, change the story copy, not the underlying data or checkpoint.
- `src/audio.js` contains a one-sample silent-buffer operation needed to unlock audio on iOS. Do not remove it or add autoplay.
- Do not insert a `"use strict"` directive inside the destructured `initStory({ DATA, CONFIG, YEARS })` function. ES modules are already strict, and that placement is a syntax error.
- The Canvas curve is built once and truncated with De Casteljau splitting to avoid tip wobble. Do not replace it with per-frame spline fitting.
- The scoreboard DOM is memoized to avoid a style recalculation every animation frame.
- Display-series smoothing pins game 108, while the underlying data remains exact.
- MLB results are derived from changes in the API's running `leagueRecord`, not merely a `Final` status or win flag, because postponed/cancelled entries can otherwise be counted incorrectly.
- Accuracy takes priority over narrative convenience.
- A merged change to `main` can ship through Netlify automatically.
- Ask before using any paid service or API.

## Suggested first review for Claude

1. Read `AGENTS.md` fully.
2. Inspect `git status --short` and the full diff before editing.
3. Determine which current changes are complete, experimental, or ready to split into commits.
4. Verify Rays files and endpoints against production before treating Rays as shipped.
5. Compare the Yankees, Mets, and Rays fetch scripts to identify the smallest safe shared API.
6. Propose a team registry and migration sequence without changing generated JSON by hand.
7. Preserve the existing four-team behavior with parameterized tests before adding more teams.

The immediate goal should not be “copy Tampa Bay 26 times.” It should be “make the fifth team a configuration change,” then apply that mechanism to the remaining clubs.
