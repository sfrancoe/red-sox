#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_binary=$(mktemp "${TMPDIR:-/tmp}/hub-ball-watch-tests.XXXXXX")
trap 'rm -f "$test_binary"' EXIT HUP INT TERM
swiftc "$repo_root/ios/Hub Ball/Hub Ball/WatchVideo.swift" \
  "$repo_root/ios/Hub Ball/Hub Ball/WatchStore.swift" \
  "$repo_root/ios/Hub Ball/Hub Ball/WatchSources.swift" \
  "$repo_root/ios/Hub Ball/Hub Ball/HubTeam.swift" \
  "$repo_root/ios/Hub Ball/WatchTests/WatchTests.swift" -o "$test_binary"
"$test_binary" "$@"
