# Native app backend

The Hub Ball iOS app uses Netlify as a small API gateway, not as a deployment mechanism
for changing data.

## Data flow

1. GitHub Actions refreshes and commits generated files under `data/`.
2. Netlify skips the commit because no backend file changed.
3. The app requests `/api/data/<file>.json`.
4. `netlify/functions/app-data.mjs` fetches the allowlisted file from the public
   repository and caches it on Netlify's durable CDN for five minutes.

The gateway also handles the legacy `/data/*` paths so installed TestFlight
builds continue receiving fresh data during the transition.

This keeps frequent data commits from consuming production-deployment credits.
The build-ignore check compares Netlify's last published commit with the target
commit, so it also covers batches of commits. Data-only, native-app-only,
documentation-only, and automation-only changes skip production deployment.
Changes to the public site, `netlify/`, `netlify.toml`, the site build/ignore
scripts, or the team registry build a new release. Unknown paths build by
default, as do first builds and builds whose Git references cannot be verified.

Keep data refreshes and native design work separate from backend releases when
practical. A mixed commit that includes any deployed file correctly triggers a
release. Netlify build hooks bypass ignore commands, so hook-triggered releases
must remain an intentional manual operation.

## Backend address

Hub Ball's provider address lives in `AppBackend.swift`. When a custom API domain is
ready, change that definition and the App Store preflight endpoint list together.

## Adding a data file

Add the generated JSON path to `ALLOWED_PATHS` in `app-data.mjs`, add a test case,
then use `AppBackend.dataURL` from the app. Do not expose an unrestricted repository
proxy.
