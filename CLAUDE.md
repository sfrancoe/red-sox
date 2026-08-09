# CLAUDE.md — Red Sox Records

## Project Overview

A small static site of **visual stories built from Boston Red Sox box scores**. Each
story is a self-contained animated graphic. The first one, *Four Roads, One Record*,
traces four seasons that arrived at the identical record after 108 games and then
diverged.

This is a **storytelling** project, not an analytics tool. The bar for each story is:
*does this make someone feel something about a number?* Precision matters because the
story depends on it — but the output is a graphic, not a dashboard.

**Primary developer:** Scott Francoe
**GitHub repo:** https://github.com/sfrancoe/red-sox (private)
**Hosting:** Netlify (auto-deploys from `main`)
**Local path:** `~/Projects/Red-Sox` (i.e. `/Users/sfrancoe/Projects/Red-Sox`)

---

## Tech Stack

- **No framework, no bundler, no backend.** Plain ES modules + `<canvas>`.
- **Data:** MLB Stats API (`statsapi.mlb.com`) — free, no key, no rate limit worth worrying about.
- **Fetch script:** Python 3, **standard library only** (so CI needs no `pip install`).
- **Hosting:** Netlify, publishing `_site/`.
- **Refresh:** GitHub Actions cron, daily at 11:00 UTC.

Deliberately dependency-free. If a change wants npm, question it first.

---

## Project Structure

```
red-sox-records/
├── index.html                  # landing page — one card per story
├── src/
│   ├── chart.js                # SHARED engine: canvas, animation, scrub, controls
│   ├── audio.js                # SHARED Web Audio engine (createAudio factory)
│   ├── styles.css              # story-page styles + @font-face
│   └── home.css                # landing-page styles
├── stories/
│   └── four-roads/
│       ├── index.html          # page shell + markup
│       └── story.js            # CONFIG (colors, arc labels, beats) + wiring
├── data/
│   ├── seasons.json            # GENERATED — do not hand-edit
│   └── meta.json               # GENERATED — generated_at, source, premise check
├── assets/fonts/               # Anton + Oswald woff2 (self-hosted, no CDN)
├── scripts/
│   ├── fetch_seasons.py        # MLB API → data/*.json
│   ├── build_site.sh           # assemble _site/ for Netlify
│   └── build_single_file.py    # → dist/*.html, one portable file for sharing
├── netlify.toml
└── .github/workflows/refresh-data.yml
```

---

## Development

```bash
# Serve locally — ES modules need http://, NOT file://
bash scripts/build_site.sh && (cd _site && python3 -m http.server 8765)
# → http://localhost:8765

# Refresh the data by hand
python3 scripts/fetch_seasons.py            # all default seasons
python3 scripts/fetch_seasons.py 2026       # just one

# Portable single-file build (for sharing / Claude artifacts)
python3 scripts/build_single_file.py
```

> **`file://` will not work.** ES module imports and `fetch()` of the JSON both need a
> real HTTP origin. Always go through the local server.

---

## Data Model

`data/seasons.json` is keyed by year. Each season:

| field | meaning |
|---|---|
| `diff` | array, games above/below .500 after each game |
| `seq` | string of `W`/`L`, one char per game |
| `record` | `"W-L"` at the last completed game |
| `end_game` | number of completed games (162 = final) |
| `in_progress` | `true` while the season is unfinished |
| `checkpoint_record` | `"W-L"` after game 108 |

`diff` and `seq` must always agree and be the same length — `fetch_seasons.py` builds
both from the same walk, so don't edit either by hand.

---

## The Premise Check

The whole first story rests on one claim: **57-51 after 108 games, four seasons running.**
`fetch_seasons.py` re-verifies this on every run and prints `CONFIRMED` or
`DOES NOT HOLD` in the CI log, and records `premise_holds` in `meta.json`.

**If that ever flips to false, the story copy is wrong and must be rewritten.** Don't
paper over it. The graphic makes a factual claim; the check is what keeps it honest.

---

## Adding a Story

1. `mkdir stories/<slug>/` with `index.html` + `story.js`
2. `story.js` imports `initStory` from `../../src/chart.js` and supplies `CONFIG`
3. Add a `<li>` card to the root `index.html`
4. If it needs new data, extend `scripts/fetch_seasons.py` — never hand-write data files

The engine in `src/` is shared. Prefer extending it with options over forking it.

---

## Conventions

### JavaScript
- 2-space indent, ES modules, no build step
- `camelCase` functions/vars, `UPPER_CASE` for config constants
- The chart engine keeps its state in module/function scope — one chart per page
- No dependencies. No CDN links (the CSP on shared builds blocks them anyway).

### Python
- 4-space indent, type hints on signatures, stdlib only
- Network calls retry with backoff and fail loudly — a silent bad fetch is worse than a red build

---

## Hard Constraints

1. **Never hand-edit `data/*.json`.** They are generated; the next CI run overwrites them.
2. **No paid APIs or services** without asking Scott first.
3. **Don't add a build toolchain** (npm/webpack/vite) without a real reason — the
   zero-dependency setup is the point.
4. **Accuracy is the product.** If real data contradicts a story's copy, fix the copy.
5. Do not commit `_site/` or `dist/` — both are generated and gitignored.

---

## Notes for Claude

- Audio cannot start without a user gesture on iOS. The big center Play button exists
  to be both the obvious call-to-action and that gesture — don't "helpfully" add autoplay.
- The play overlay primes WebAudio with a silent buffer inside the tap handler. That
  line looks pointless; it is what makes sound work on iPhone. Leave it.
- `initStory({DATA, CONFIG, YEARS})` takes a destructured parameter, so a `"use strict"`
  directive inside it is a syntax error. ES modules are strict already.
- Test in a real browser before claiming something works. `python3 -m http.server` plus
  Playwright catches the module/CORS/canvas failures that static reading misses.
- Mobile first here, unlike em-dashboard — these get opened on phones and texted around.
