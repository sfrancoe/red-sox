# Hub Ball: Netlify cost-reduction handoff

Prepared September 8, 2026 for GPT-5.6 Sol. Read this brief and the current repository instructions; do not repeat the broad investigation.

## Objective and authorization

Prepare the smallest safe change that stops generated-data and iOS-only commits from causing Netlify production deployments, while preserving fresh data for installed apps and necessary backend releases.

This document is an implementation brief, not authorization to deploy. The user requested an analysis and this handoff; no implementation has been performed in this task. When the user assigns implementation, complete local work and verification first. Obtain explicit authorization before merging into `main`, publishing to production, changing account settings, or purchasing credits. Do not create test production deployments merely to measure costs.

## Verified billing evidence

Netlify dashboard snapshot on September 8; current billing period August 28–September 27:

| Category | Usage | Credits |
|---|---:|---:|
| Production deployments | 302 | 4,530.0 |
| Web requests | 32,710 | 6.5 |
| Bandwidth | — | 4.2 |
| Compute | — | 2.4 |
| Netlify AI | None | 0 |
| **Total** | | **4,543.1** |

Deployments account for **99.7%** of credits. All runtime usage combined costs less than one 15-credit deployment. These are team-wide totals. The lagging per-project build table showed 280 builds for `red-sox` and seven for `tourchampionship`; do not equate that table with the billed deployment count.

- Plan: Pro, $20/month, 3,000 included credits.
- Remaining balance at inspection: 1,456.9 credits. Auto-recharge: disabled.
- Paid receipts: $10.89 on September 6 and September 8; whether recharge was enabled previously was not established.
- Production auto-publishing from `main` is enabled. The latest 12 listed deployments were automated data/news refreshes.
- September 8 examples: 7:19 AM baseball data, 7:26 AM Yankees news, 7:33 AM Athletic/MassLive news: three successful production deployments, 45 credits in 14 minutes.
- An initially stale pause warning disappeared after fresh navigation; successful publishing was visible. Recheck current state if relevant.

The primary issue is deployment triggers. Do not prioritize a hosting migration or bandwidth refactor for this task.

## Repository state and root cause

Repository: https://github.com/sfrancoe/red-sox

**Preserve the dirty checkout at `/Users/sfrancoe/Projects/MLB Apps`.** It contains unrelated unfinished work and older snapshots. Work in a fresh worktree from freshly fetched `origin/main`. Do not reset, clean, stash, overwrite, or bulk-copy the dirty checkout. This handoff file is the only project file created by this audit/handoff task.

The project now includes the universal native Hub Ball app, the legacy Boston Baseball
Hub App Store identity, a static website, scheduled Python data fetchers, and Netlify
functions. The standalone Yankees app has been retired; Yankees remains a team inside
Hub Ball. Current `main` includes all 30 teams; the dirty checkout is not authoritative
for current production support.

GitHub Actions fetch scores/headlines, commit changed JSON, and push to `main`. News polls run every 5–10 minutes for the original teams; other jobs refresh baseball data every two hours, expansion-team news every 30 minutes, and leaders daily. Most jobs check for actual changes before committing. **A scheduled run is not necessarily a commit or deployment.** Retain those checks.

An earlier cost fix was implemented locally but only partially integrated:

- `netlify/functions/app-data.mjs` is on `main` and serves allowlisted JSON from GitHub `main/data`, with shared caching.
- Both `/api/data/*` and legacy `/data/*` routes are configured. Representative production requests succeeded and returned durable cache hits.
- `ios/Hub Ball/Hub Ball/AppBackend.swift` centralizes URLs. Release uses `/api/data/`; Debug defaults to `/data/` with a `HUB_DATA_ROOT` override. Live API URLs still use the production hostname.
- **The build-ignore rule exists in the dirty local `netlify.toml`, but was absent from live GitHub `main` during the audit.** Fresh data can already be served without deployments, yet data commits still trigger deployments.

The local candidate compares `$CACHED_COMMIT_REF` and `$COMMIT_REF`, watching `netlify`, `netlify.toml`, and `privacy`. Treat it as a starting idea, not a patch to copy blindly: its dependency coverage and first-build behavior need review.

## Narrow implementation scope

1. Confirm whether a fix has landed since this audit. Read current `netlify.toml`, `scripts/build_site.sh`, `docs/app-backend.md`, relevant workflows, and the data gateway.
2. Implement a dependency-aware build decision: skip data-only, iOS-only, and documentation-only changes; build when deployed backend/configuration or retained public assets require it. Include the build script and all actual function dependencies, including generated `netlify/functions/team-registry.mjs`. Handle deletions, renames, mixed commits, and comparisons spanning multiple commits.
3. Handle first builds and unavailable/invalid Git references safely: uncertainty should allow a necessary build. Netlify ignore exit code **0 skips**, **1 builds**. Do not compare only the last commit, which can miss pending backend changes.
4. Preserve existing public pages and assets unless explicitly retired. App-first scope does not authorize silently preventing needed privacy/support or website updates. Review whether `data/` contains any build-time inputs or unsupported static-only consumers before excluding it wholesale.
5. Inspect any existing build-hook/manual-deploy path if accessible. Netlify's ignore command does not cancel hook-triggered builds. Report any remaining bypass; do not disable all production publishing or change billing settings as a shortcut.
6. Add concise maintenance guidance explaining that data refreshes and native design iterations do not need production backend releases. Keep the implementation dependency-free.

Do not change news freshness, consolidate workflows, modify generated data, alter iOS UI, optimize live polling, migrate storage/providers, set up DNS, retire the Yankees app, or repair unrelated failures. A custom domain is useful later and is **not required** for this fix.

## Focused verification and acceptance

Before release:

- Exercise the build decision against temporary Git fixtures or equivalent isolated history: data-only, iOS-only, docs-only, backend-only, registry changes, build-script changes, retained public assets, mixed changes, deletion/rename, multiple commits, and missing/invalid references. Do not manufacture commits in production.
- Run relevant existing gateway/routing tests (`scripts/test_app_data.mjs` and applicable registry tests) and the static build. If browser verification is applicable, serve over HTTP, never `file://`.
- Check required all-team paths locally against existing generated files/registry. Preserve both legacy and current data URL shapes. Do not run all data fetchers or full iOS builds unless changes actually warrant them.
- Respect `AGENTS.md`, add no dependencies, never hand-edit generated JSON, and never commit `_site/` or `dist/`.
- Keep live probes small. Do not invoke paid `/api/x-discovery`; the preflight script already treats it as metered. Use default request headers first; apply the repository's fallback User-Agent only when retrieval actually fails or degrades.

Prepare a focused diff and report local checks before asking for release authorization. After an authorized production release:

- Record the successful deployment ID and commit.
- Observe a naturally occurring data-only refresh: Netlify should skip the build, while updated JSON becomes available within the gateway's cache policy through both legacy and current paths. Compare payload timestamps/content and GitHub source, not HTTP 200 alone.
- Verify an iOS-only change does not deploy when one naturally occurs; use local history checks until then rather than creating artificial production activity.
- Confirm necessary backend changes still deploy, using the authorized release as evidence where applicable.
- Report local verification separately from production verification. Do not declare savings active merely because a local test passed. If a natural refresh has not occurred, identify that remaining check without claiming completion.

## Expected outcome and future workflow

Target zero production deployments caused solely by data refreshes or native app edits. Keep small development commits on review branches; batch actual backend releases. TestFlight-only releases should not require Netlify deployments.

Twenty production deployments plus the observed 13.1 runtime credits would total 313.1 credits versus 4,543.1: approximately 93% lower usage for an equivalent period. This is a scenario, not a guarantee or proof every prior deployment was avoidable. The bill changes in credit-pack increments.

Final implementation report: branch/worktree, changed files, build/skip behavior, focused verification, remaining hook or compatibility concerns, release status, and exact production evidence if release was authorized. Keep it brief; avoid repeating the audit.

## References

- [Verified billing dashboard](https://app.netlify.com/teams/sfrancoe/billing/general)
- [Production deployment history](https://app.netlify.com/projects/red-sox/deploys)
- [Netlify ignore-build semantics and hook exception](https://docs.netlify.com/build/configure-builds/ignore-builds/)
- [Netlify credit rules](https://docs.netlify.com/manage/accounts-and-billing/billing/billing-for-credit-based-plans/how-credits-work/)
- [Full analysis and dashboard update in Reader](https://read.readwise.io/read/01m20d1jsbhyfh3pasd03dmkj7)

Use the full report only if a specific detail is missing. The expensive discovery work is complete; refresh only facts necessary to implement safely.
