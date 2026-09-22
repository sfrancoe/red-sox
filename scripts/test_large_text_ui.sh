#!/bin/bash
# Run native UI tests against a simulator; generated Xcode project stays under dist/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:?Usage: test_large_text_ui.sh SIMULATOR_UUID RUN_NAME [TEST_METHOD ...]}"
RUN_NAME="${2:?Supply a unique run name}"
shift 2
case "$RUN_NAME" in *[!a-zA-Z0-9_-]*|'') echo 'Run name must contain only letters, digits, underscores, or hyphens.' >&2; exit 2;; esac
cd "$ROOT"
python3 scripts/prepare_large_text_ui_tests.py
OPTIONS=()
for METHOD in "$@"; do
  OPTIONS+=("-only-testing:LargeTextUITests/LargeTextUITests/$METHOD")
done
RESULT="dist/large-text-ui/$RUN_NAME.xcresult"
LOG="dist/large-text-ui/$RUN_NAME.log"
if [[ -e "$RESULT" ]]; then echo "Result already exists: $RESULT" >&2; exit 2; fi
set +e
xcodebuild -project 'dist/large-text-ui/Hub Ball.xcodeproj' -scheme LargeTextAudit \
  -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE" \
  -derivedDataPath dist/large-text-ui/derived -resultBundlePath "$RESULT" \
  -parallel-testing-enabled NO "${OPTIONS[@]}" CODE_SIGNING_ALLOWED=NO test > "$LOG" 2>&1
STATUS=$?
set -e
if [[ -d "$RESULT" ]]; then
  xcrun xcresulttool export attachments --path "$RESULT" --output-path "dist/large-text-ui/$RUN_NAME-evidence" > "dist/large-text-ui/$RUN_NAME-export.log" 2>&1 || true
fi
printf 'Log: %s\nResult: %s\n' "$LOG" "$RESULT"
exit "$STATUS"
