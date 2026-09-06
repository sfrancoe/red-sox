# Native app backend

The iOS apps use Netlify as a small API gateway, not as a deployment mechanism
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
Only changes under `netlify/`, `netlify.toml`, or `privacy/` trigger a Netlify
production deployment.

## Backend address

The Red Sox app's provider address lives in `AppBackend.swift`. The Yankees app
keeps its shared roots in `TeamConfig.swift`. When a custom API domain is ready,
change those two definitions and the App Store preflight endpoint list together.

## Adding a data file

Add the generated JSON path to `ALLOWED_PATHS` in `app-data.mjs`, add a test case,
then use `AppBackend.dataURL` or `TeamConfig.dataURL` from the app. Do not expose
an unrestricted repository proxy.
