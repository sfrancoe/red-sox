#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: bash scripts/install_hub_ball.sh --device <device-identifier> [--allow-dirty]"
}

device_id=""
allow_dirty=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      device_id="$2"
      shift 2
      ;;
    --allow-dirty)
      allow_dirty=true
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

[[ -n "$device_id" ]] || { usage; xcrun devicectl list devices; exit 2; }

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
if [[ "$allow_dirty" == true ]]; then
  python3 scripts/check_hub_ball_release.py --allow-dirty
else
  python3 scripts/check_hub_ball_release.py
fi

derived_data="$(mktemp -d "${TMPDIR:-/tmp}/hub-ball-install.XXXXXX")"
cleanup() {
  case "$derived_data" in
    "${TMPDIR:-/tmp}"/hub-ball-install.*) rm -rf -- "$derived_data" ;;
  esac
}
trap cleanup EXIT

project="ios/Hub Ball/Hub Ball.xcodeproj"
scheme="Hub Ball"
xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration Debug \
  -destination "platform=iOS,id=$device_id" \
  -derivedDataPath "$derived_data" \
  -allowProvisioningUpdates \
  build

app="$derived_data/Build/Products/Debug-iphoneos/Hub Ball.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"

xcrun devicectl device install app --device "$device_id" "$app"
xcrun devicectl device process launch --device "$device_id" "$bundle_id"
echo "Installed and launched Hub Ball $version ($build) from main on $device_id."
