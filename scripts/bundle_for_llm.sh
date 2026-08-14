#!/usr/bin/env bash
# Concatenate the whole readable repo into one pasteable file for an LLM.
#
# The project is small enough (~120 KB of text) to hand over in full rather than
# summarized, which is the whole reason this exists: a summary is where the
# subtle constraints get lost. Skips binaries and generated output.
#
#   bash scripts/bundle_for_llm.sh          # → dist/bundle.txt
#   bash scripts/bundle_for_llm.sh --copy   # also copy to the clipboard (macOS)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=dist/bundle.txt
mkdir -p dist
: > "$OUT"

# Read in this order — orientation first, then structure, then code, then data.
# An LLM that hits the rules before the code is far likelier to respect them.
PRIORITY=(
  AGENTS.md
  README.md
  index.html
  src/chart.js
  src/audio.js
  src/styles.css
  src/home.css
  stories/four-roads/index.html
  stories/four-roads/story.js
  stories/war-room/index.html
  stories/war-room/story.js
  scripts/fetch_seasons.py
  scripts/story_facts.py
  scripts/build_site.sh
  scripts/build_single_file.py
  scripts/bundle_for_llm.sh
  netlify.toml
  .github/workflows/refresh-data.yml
  data/meta.json
  data/seasons.json
  .gitignore
  CLAUDE.md
)

emit(){
  local f=$1
  [ -f "$f" ] || { echo "  ! missing $f, skipping" >&2; return; }
  {
    echo
    echo "===================================================================="
    echo "FILE: $f"
    echo "===================================================================="
    cat "$f"
  } >> "$OUT"
}

{
  echo "RED SOX RECORDS — full source bundle"
  echo "Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) from commit $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo
  echo "This is the complete readable source of a small static site: plain ES modules"
  echo "and <canvas>, with game data fetched by a stdlib-only Python script. There is"
  echo "no framework, bundler, backend, or dependency of any kind, and that is"
  echo "deliberate."
  echo
  echo "READ AGENTS.md FIRST — it comes first below and states the hard constraints."
  echo "The ones most often broken: do not add npm or any dependency; never hand-edit"
  echo "data/*.json (generated, overwritten by CI); the site cannot be tested over"
  echo "file:// (ES modules and fetch need a real HTTP origin)."
  echo
  echo "Binary assets (assets/fonts/*.woff2) and generated output (_site/, dist/) are"
  echo "omitted. Files appear one per section, delimited by a FILE: header."
  echo
  echo "--- file tree ---"
  git ls-files 2>/dev/null | grep -v '^assets/fonts/' || true
} >> "$OUT"

for f in "${PRIORITY[@]}"; do emit "$f"; done

# Anything tracked that the priority list does not name — so a file added later
# is never silently left out of the handoff. Binaries and generated dirs excluded.
EXTRA=0
while IFS= read -r f; do
  case " ${PRIORITY[*]} " in *" $f "*) continue ;; esac
  case "$f" in
    assets/fonts/*|_site/*|dist/*|*.woff2|*.png|*.jpg|*.ico) continue ;;
  esac
  emit "$f"; EXTRA=$((EXTRA+1))
done < <(git ls-files 2>/dev/null || true)

BYTES=$(wc -c < "$OUT" | tr -d ' ')
echo "wrote $OUT — $((BYTES/1024)) KB, ~$((BYTES/4/1000))k tokens, $((${#PRIORITY[@]}+EXTRA)) files"
[ "$EXTRA" -gt 0 ] && echo "  ($EXTRA file(s) picked up beyond the curated list — consider adding them to PRIORITY)"

if [ "${1:-}" = "--copy" ]; then
  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy < "$OUT" && echo "copied to clipboard"
  else
    echo "  ! pbcopy not found — copy $OUT by hand" >&2
  fi
fi
