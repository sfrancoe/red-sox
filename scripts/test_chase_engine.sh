#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_binary=$(mktemp "${TMPDIR:-/tmp}/hub-ball-chase-tests.XXXXXX")
trap 'rm -f "$test_binary"' EXIT HUP INT TERM

swiftc \
  "$repo_root/ios/Hub Ball/Hub Ball/HomeRunChase.swift" \
  "$repo_root/ios/Hub Ball/ChaseEngineTests/ChaseEngineTests.swift" \
  -o "$test_binary"
"$test_binary"
