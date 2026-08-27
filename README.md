# Red Sox Records

Visual stories built from Boston Red Sox box scores. No framework, no bundler, no
backend — plain ES modules and `<canvas>`, with game logs pulled from the free
[MLB Stats API](https://statsapi.mlb.com/).

## Stories

| Story | What it shows |
|---|---|
| **Four Roads, One Record** (`stories/four-roads/`) | Four straight seasons (2023-26) reached the identical record after 108 games, then split toward four completely different endings. |

The **Newspaper Headlines** tab tracks Red Sox headlines and short descriptions
from The Boston Globe and Boston Herald in parallel desktop columns and mobile
tabs. Every item links to the original article.

## Run it locally

ES modules and `fetch()` both need a real HTTP origin, so `file://` will not work:

```bash
bash scripts/build_site.sh
cd _site && python3 -m http.server 8765
# open http://localhost:8765
```

## Refresh the data

```bash
python3 scripts/fetch_seasons.py          # all seasons
python3 scripts/fetch_seasons.py 2026     # one season
python3 scripts/fetch_globe_news.py       # Globe headline metadata
python3 scripts/fetch_herald_news.py      # Herald headline metadata
```

Writes the generated files in `data/`. Standard library only — no dependencies
to install. GitHub Actions refreshes MLB data daily and checks both newspaper
pages every five minutes. It commits only when content changes; Netlify
redeploys on that commit.

## Deploy

Netlify builds with `bash scripts/build_site.sh` and publishes `_site/`, which
contains only the public files — `scripts/`, docs, and CI config stay out of the
served site.

## Layout

```
index.html              landing page
src/                    shared chart + audio engine, styles
stories/<slug>/         one folder per story
data/                   generated JSON — do not hand-edit
assets/fonts/           self-hosted woff2
scripts/                fetch, build, package
```

## A note on accuracy

Every game in `data/` comes from the MLB Stats API. The fetch script also
re-checks the claim the first story is built on — the same 57-51 record after 108
games, four years running — and records the result in `data/meta.json` as
`premise_holds`. If that ever goes false, the story text needs rewriting rather
than the check being ignored.
