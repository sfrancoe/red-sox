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
product_name="$(basename "$app" .app)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"

running_pid="$(
  xcrun devicectl device info processes \
    --device "$device_id" \
    --hide-headers 2>/dev/null \
    | awk -v executable="/$product_name.app/$product_name" '
        index($0, executable) && pid == "" { pid = $1 }
        END { if (pid != "") print pid }
      '
)"
if [[ -n "$running_pid" ]]; then
  xcrun devicectl device process terminate --device "$device_id" --pid "$running_pid"
fi

xcrun devicectl device install app --device "$device_id" "$app"
installed_build="$(
  xcrun devicectl device info apps \
    --device "$device_id" \
    --bundle-id "$bundle_id" \
    --hide-headers 2>/dev/null \
    | awk 'NF { installed_build = $NF } END { print installed_build }'
)"
if [[ "$installed_build" != "$build" ]]; then
  echo "ERROR: Device reports Hub Ball build $installed_build after installing build $build." >&2
  exit 1
fi
xcrun devicectl device process launch --device "$device_id" "$bundle_id"
echo "Installed and launched Hub Ball $version ($build) from main on $device_id."
