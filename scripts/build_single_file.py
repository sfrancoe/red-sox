#!/usr/bin/env python3
"""Bundle a story into ONE portable .html file (fonts, CSS, JS and data inlined).

Useful for sharing a story where a URL will not do — emailing it, dropping it into
a Claude artifact, or handing someone a file that works offline.

This is a deliberately dumb bundler: it knows this project's exact module shape
(story.js imports chart.js, chart.js imports audio.js) rather than parsing an
arbitrary dependency graph. If the import structure changes, update this.

    python3 scripts/build_single_file.py            # every story
    python3 scripts/build_single_file.py four-roads # one story
"""
from __future__ import annotations

import base64
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"


def inline_fonts(css: str) -> str:
    """Swap url('../assets/fonts/x.woff2') for a base64 data URI."""
    def sub(m: re.Match) -> str:
        path = ROOT / "assets" / "fonts" / pathlib.Path(m.group(1)).name
        if not path.exists():
            print(f"  ! missing font {path.name}, leaving as-is", file=sys.stderr)
            return m.group(0)
        b64 = base64.b64encode(path.read_bytes()).decode()
        return f"src:url(data:font/woff2;base64,{b64})"
    return re.sub(r"src:url\('([^']+\.woff2)'\)(?: format\('woff2'\))?", sub, css)


def strip_modules(js: str) -> str:
    """Remove import/export keywords so the code can run in a classic <script>."""
    js = re.sub(r"^\s*import\s+.*?;\s*$", "", js, flags=re.M)
    js = re.sub(r"^\s*export\s+(?=function|const|let|class)", "", js, flags=re.M)
    return js


def build(slug: str) -> pathlib.Path:
    story_dir = ROOT / "stories" / slug
    html = (story_dir / "index.html").read_text()
    css = inline_fonts((ROOT / "src/styles.css").read_text())
    audio_js = strip_modules((ROOT / "src/audio.js").read_text())
    chart_js = strip_modules((ROOT / "src/chart.js").read_text())
    story_js = strip_modules((story_dir / "story.js").read_text())
    data = (ROOT / "data/seasons.json").read_text().strip()

    # story.js fetches the data at runtime; inline it instead.
    story_js = re.sub(
        r"const DATA\s*=\s*await fetch\([^)]*\)[^;]*;",
        f"const DATA = {data};",
        story_js,
    )

    # Order matters: audio -> chart -> story, all in one classic script.
    bundle = "\n".join(["(function(){", audio_js, chart_js, story_js, "})();"])

    out = html
    out = out.replace('<link rel="stylesheet" href="../../src/styles.css">',
                      f"<style>\n{css}\n</style>")
    out = out.replace('<script type="module" src="./story.js"></script>',
                      f"<script>\n{bundle}\n</script>")

    if "<style>" not in out or "createAudio" not in out:
        raise SystemExit(f"{slug}: inlining failed — page markers did not match")

    DIST.mkdir(exist_ok=True)
    dest = DIST / f"{slug}.html"
    dest.write_text(out)
    return dest


def main() -> int:
    slugs = sys.argv[1:] or [p.name for p in sorted((ROOT / "stories").iterdir()) if p.is_dir()]
    for slug in slugs:
        dest = build(slug)
        print(f"  {slug} -> {dest.relative_to(ROOT)} ({dest.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
