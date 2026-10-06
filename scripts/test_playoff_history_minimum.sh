#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_binary=$(mktemp "${TMPDIR:-/tmp}/hub-ball-playoff-minimum-tests.XXXXXX")
trap 'rm -f "$test_binary"' EXIT HUP INT TERM
app_root="$repo_root/ios/Hub Ball/Hub Ball"

swiftc -target "$(uname -m)-apple-macos14.0" \
  "$app_root/HubTeam.swift" \
  "$app_root/AppBackend.swift" \
  "$app_root/APIClient.swift" \
  "$app_root/SafeURL.swift" \
  "$app_root/PostseasonHistory.swift" \
  "$repo_root/scripts/test_playoff_history_minimum.swift" \
  -o "$test_binary"
"$test_binary"
