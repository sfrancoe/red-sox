#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_binary=$(mktemp /tmp/hub-ball-http-cache-tests.XXXXXX)
ready_file=$(mktemp /tmp/hub-ball-http-cache-ready.XXXXXX)
server_pid=""
cleanup() {
  if test -n "$server_pid"; then
    kill "$server_pid" 2>/dev/null || true
  fi
  rm -f "$test_binary" "$ready_file"
}
trap cleanup EXIT HUP INT TERM
python3 "$repo_root/scripts/test_http_cache_server.py" "$ready_file" >/dev/null 2>&1 &
server_pid=$!
for _ in $(seq 1 100); do
  test -s "$ready_file" && break
  sleep 0.01
done
test -s "$ready_file"
fixture_origin="http://localhost:$(cat "$ready_file")"
app_root="$repo_root/ios/Hub Ball/Hub Ball"

swiftc -target "$(uname -m)-apple-macos14.0" \
  -default-isolation MainActor \
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
HUB_HTTP_CACHE_FIXTURE_ORIGIN="$fixture_origin" "$test_binary"
