#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_binary=$(mktemp /tmp/hub-ball-http-cache-tests.XXXXXX)
trap 'rm -f "$test_binary"' EXIT HUP INT TERM
app_root="$repo_root/ios/Hub Ball/Hub Ball"

swiftc -target "$(uname -m)-apple-macos14.0" \
  "$app_root/HubTeam.swift" \
  "$app_root/AppBackend.swift" \
  "$app_root/BaseballTime.swift" \
  "$app_root/Schedule.swift" \
  "$app_root/ScheduleStore.swift" \
  "$app_root/RecentGame.swift" \
  "$app_root/RecentGameSnapshot.swift" \
  "$app_root/MLBGameClient.swift" \
  "$app_root/RecentGameStore.swift" \
  "$repo_root/scripts/test_recent_game_http_cache.swift" \
  -o "$test_binary"
"$test_binary"
