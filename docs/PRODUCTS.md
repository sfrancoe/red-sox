# Product map and naming policy

This repository has exactly two app identities. Use these names consistently in
code, documentation, App Store Connect, TestFlight, release notes, and conversation.

| Canonical name | Status | Bundle ID | Working source |
|---|---|---|---|
| **Hub Ball** | Active product | `com.sfrancoe.HubBall` | `ios/Hub Ball/` |
| **Boston Baseball Hub** | Legacy product; maintenance only until retirement | `com.sfrancoe.Red-Sox-Records` | Git history only |

## Hub Ball

Hub Ball is the current multi-team app. All feature development, TestFlight builds,
App Store metadata, screenshots, and release work belong to this product. Its Xcode
project is `ios/Hub Ball/Hub Ball.xcodeproj` and its scheme is `Hub Ball`.

Team names such as Red Sox, Yankees, Mets, and Rays describe content selected inside
Hub Ball. They do not identify separate applications.

## Boston Baseball Hub

Boston Baseball Hub is the canonical name for the legacy Boston-only App Store
identity associated with `com.sfrancoe.Red-Sox-Records`. Do not call this app Hub Ball,
Red Sox Records, or Boston Hub in new documentation. It receives only critical fixes
needed before retirement; new features belong in Hub Ball.

The current branch does not keep a duplicate Xcode source tree for this legacy app.
Its prior source remains recoverable from Git history. If a final maintenance release
is required, create it from an appropriate historical commit in a temporary worktree
rather than copying Hub Ball into a second long-lived project.

## Retired standalone Yankees app

The former `NY Baseball Hub` / `Yankees Hub` iOS project is retired and removed from
the working tree. Yankees data, fetchers, tests, and API routing remain because the
Yankees are still a supported team within Hub Ball.

App Store Connect and Apple Developer cleanup cannot be performed from this repository.
Complete these account-level steps manually:

1. Rename the old Boston app record to **Boston Baseball Hub**, while retaining its
   existing bundle identifier.
2. Confirm the active Hub Ball record uses `com.sfrancoe.HubBall` and is the only record
   named **Hub Ball**.
3. Remove or retire the standalone Yankees app record and its obsolete provisioning
   assets when Apple permits it. Do not remove team support from Hub Ball.
4. Label any remaining TestFlight groups/builds with the canonical product name and
   expire obsolete Yankees builds.

## Retirement sequence for Boston Baseball Hub

1. Stop feature development immediately.
2. Direct users and support material to Hub Ball.
3. Publish only critical compatibility or migration fixes.
4. After the agreed migration window, remove it from sale and expire remaining beta
   builds.
5. Retain the Git history and App Store records required for audit or recovery; do not
   keep a second active source tree.
