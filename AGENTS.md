# AGENTS.md — Red Sox Records

Instructions for AI coding agents working in this repo. Read this before changing
anything. If you are Claude Code, `CLAUDE.md` covers the same ground in more detail.

---

## What this project is

A small static site of **visual stories built from Boston Red Sox box scores**. Each
story is a self-contained animated graphic. The first, *Four Roads, One Record*, traces
four seasons that arrived at the identical record after 108 games and then diverged.

This is a **storytelling** project, not an analytics tool. The bar for a change is:
*does this make someone feel something about a number?* Precision matters because the
story depends on it — but the output is a graphic, not a dashboard.

Hosting is Netlify, auto-deploying from `main`. **A merged PR ships to production.**

---

## Stack

Plain ES modules + `<canvas>`. Python 3 standard library for the data fetch. No
framework, no bundler, no backend, no dependencies of any kind.

```
index.html                  landing page — one card per story
src/chart.js                SHARED engine: canvas, animation, scrub, controls
src/audio.js                SHARED Web Audio engine (createAudio factory)
src/styles.css              story-page styles + @font-face
src/home.css                landing-page styles
stories/four-roads/         index.html + story.js (CONFIG: colors, labels, beats)
stories/war-room/           unlisted DESIGN MOCKUP — see rule 7
data/seasons.json           GENERATED — per-game arrays, keyed by year
data/meta.json              GENERATED — generated_at, source, premise check
scripts/fetch_seasons.py    MLB API + Baseball Reference → data/*.json
scripts/story_facts.py      prints real milestones so story copy can be fact-checked
scripts/build_site.sh       assembles _site/ for Netlify
scripts/build_single_file.py → dist/*.html, one portable file for sharing
assets/fonts/               Anton + Oswald woff2, self-hosted
```

Data flows one way: **Python writes `data/*.json` → the browser fetches it at runtime.**
`story.js` holds presentation config and wires it to `initStory` from `src/chart.js`.

---

## Rules

These are the mistakes agents actually make here. They are not style preferences.

**1. Do not add a build toolchain or any dependency.** No npm, webpack, Vite, React, no
charting library, no CDN `<script>` tags. The zero-dependency setup is the point, and
the CSP on shared builds blocks external hosts anyway. If a change seems to need a
package, say so and stop — do not install it.

**2. Never hand-edit `data/seasons.json` or `data/meta.json`.** They are generated, and
the daily CI refresh overwrites them. To change data, change `scripts/fetch_seasons.py`.
`diff` and `seq` must always agree and be the same length — both are built from the same
walk, so editing one by hand desynchronizes them silently.

**3. Test over HTTP, never `file://`.** ES module imports and `fetch()` of the JSON both
require a real HTTP origin; `file://` fails with opaque CORS errors. Do not claim a
change works based on reading the code:

```bash
bash scripts/build_site.sh && (cd _site && python3 -m http.server 8765)
# → http://localhost:8765
```

If you have no browser available, say that you could not verify it rather than implying
you did.

**4. `initStory({ DATA, CONFIG, YEARS })` takes a destructured parameter.** A
`"use strict"` directive inside that function body is a **syntax error**. ES modules are
already strict. Do not add one.

**5. Leave the iOS audio unlock alone.** [`src/audio.js:199`](src/audio.js) plays a
1-sample silent buffer inside `start()`, which runs from the overlay's tap handler. It
looks like dead code. It is what makes sound work on iPhone. Likewise, do not add
autoplay — audio cannot start without a user gesture on iOS, and the big center Play
button exists to be both the call-to-action and that gesture.

**6. Accuracy is the product.** If real data contradicts a story's copy, **fix the copy**,
not the data. After any data refresh, run `python3 scripts/story_facts.py` and confirm the
narrative beats in `story.js` still match the real peaks, valleys, streaks and records.

**7. `stories/war-room/` is a mockup, not a finished story.** Its WAR values are real but
**frozen** into `story.js`, and the overnight movement deltas are **invented** so the UI
has something to show. It is unlisted on the landing page on purpose. Do not wire it up,
cite its numbers, or present it as live. Making it real means extending
`fetch_seasons.py` to emit `data/war.json` plus a dated history file.

**8. Prefer extending `src/chart.js` with options over forking it.** The engine is shared
across stories. One chart per page — it keeps state in module/function scope.

**9. Do not commit `_site/` or `dist/`.** Both are generated and gitignored.

**10. Ask before anything paid.** No paid APIs or services without checking first.

---

## The premise check

The first story rests on one claim: **57-51 after 108 games, four seasons running.**
`fetch_seasons.py` re-verifies it on every run, prints `CONFIRMED` or `DOES NOT HOLD` in
the CI log, and records `premise_holds` in `meta.json`.

**If that flips to false, the story copy is wrong and must be rewritten.** Do not paper
over it, and do not adjust the checkpoint or the expected record to make it pass. The
graphic makes a factual claim; the check is what keeps it honest.

---

## Things that look wrong but are not

Before "simplifying" any of these, read the comment above them. Each cost real debugging.

- **Curve geometry is built once per resize, then truncated** (`buildSegs` +
  `splitBezier` in `src/chart.js`). Growing the line by re-fitting a spline each frame
  makes the tip wobble, because every knot's tangent depends on its neighbours. At 26
  games/sec that read as stutter. De Casteljau truncation of a fixed curve is the fix.
- **The scoreboard is memoized through a `shown{}` cache.** The render loop runs every
  frame but the text changes a few times a second; writing unconditionally caused a style
  recalc per frame.
- **The display series is smoothed, and game 108 is pinned.** `disp[108] = 6` forces the
  exact convergence point. The underlying `diff` array is untouched and stays exact.
- **Results are derived from the API's running `leagueRecord`, not a win flag.** If the
  record did not move, the game did not count. MLB marks postponed and cancelled games
  `Final` too; counting those is how you get a 167-game season.

---

## Conventions

**JavaScript** — 2-space indent, ES modules, no build step. `camelCase` for
functions/vars, `UPPER_CASE` for config constants.

**Python** — 4-space indent, type hints on signatures, stdlib only. Network calls retry
with backoff and fail loudly; a silent bad fetch is worse than a red build.

**Mobile first.** These get opened on phones and texted around.

---

## Adding a story

1. `mkdir stories/<slug>/` with `index.html` + `story.js`
2. `story.js` imports `initStory` from `../../src/chart.js` and supplies `CONFIG`
3. Add a `<li>` card to the root `index.html`
4. If it needs new data, extend `scripts/fetch_seasons.py` — never hand-write data files
