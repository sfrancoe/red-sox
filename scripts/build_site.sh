#!/usr/bin/env bash
# Assemble the publishable site into _site/ (keeps scripts/ and docs off the web).
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf _site
mkdir -p _site
cp index.html _site/
cp -R src data assets stories news herald x-posts schedule recent-game _site/
echo "built _site/ ($(find _site -type f | wc -l | tr -d ' ') files)"
