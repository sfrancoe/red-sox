# Product map and release policy

This repository has exactly two app identities. Use these names consistently in
code, documentation, App Store Connect, TestFlight, release notes, and conversation.

| Canonical name | Status | Bundle ID | Working source |
|---|---|---|---|
| **Hub Ball** | Active product | `com.sfrancoe.HubBall` | `main` → `ios/Hub Ball/` |
| **Boston Baseball Hub** | Legacy; maintenance only until retirement | `com.sfrancoe.Red-Sox-Records` | Git history only |

## Hub Ball

Hub Ball is the current multi-team app. All feature development, TestFlight builds,
App Store metadata, screenshots, device installations, and release work belong here.
Team names describe content selected inside Hub Ball; they do not identify separate
applications.

The `main` branch is the sole release and device-installation source. The declared
release is stored in `config/hub-ball-release.json`. Update that manifest and both Xcode
build configurations together whenever the build changes. Run
`python3 scripts/check_hub_ball_release.py` before packaging, and install through
`scripts/install_hub_ball.sh` instead of invoking `xcodebuild` from an arbitrary
worktree.

## Boston Baseball Hub

Boston Baseball Hub is the canonical name for the legacy Boston-only App Store
identity associated with `com.sfrancoe.Red-Sox-Records`. It receives only critical
fixes needed before retirement; new features belong in Hub Ball.

The current branch does not keep a duplicate Xcode source tree for this legacy app.
If a final maintenance release is required, recover the appropriate historical source
in a temporary worktree and label it explicitly as Boston Baseball Hub.

## Retired standalone Yankees app

The former `NY Baseball Hub` / `Yankees Hub` iOS project is retired. Yankees data,
fetchers, tests, and API routing remain because the Yankees are supported within Hub
Ball.

Complete these account-level steps manually in App Store Connect and Apple Developer:

1. Rename the old Boston app record to **Boston Baseball Hub**, retaining its bundle ID.
2. Confirm `com.sfrancoe.HubBall` is the only record named **Hub Ball**.
3. Retire the standalone Yankees record and obsolete provisioning assets when Apple
   permits it; do not remove Yankees team support from Hub Ball.
4. Expire obsolete beta builds and label remaining groups with canonical product names.

## Retirement sequence for Boston Baseball Hub

1. Stop feature development.
2. Direct users and support material to Hub Ball.
3. Publish only critical compatibility or migration fixes.
4. After the migration window, remove it from sale and expire remaining beta builds.
5. Retain history and records needed for audit or recovery, without a second active
   source tree.
