#!/bin/sh
set -eu
exec python3 "$(dirname "$0")/test_hub_ball.py" --suite RecentGameStoreTests "$@"
