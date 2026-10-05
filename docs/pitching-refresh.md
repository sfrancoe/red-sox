# Above the Forecast refresh

The regular-season FanGraphs actuals vs Steamer feed is separate from playoff
statistics (MLB API). Its workflow runs Mondays at 12:55 UTC during October.
`config/pitching-refresh.json` pins both actuals and the operator-verified projection
season to 2026. Automatic refreshes stop after October 31, including at New Year.
The weekly October schedule remains inert in later years until explicit setup.
No playoff, news, score, or other MLB schedules changed.

One process downloads projections once successfully per run and shares that list
across all 30 teams. Every FanGraphs attempt is spaced at least ten seconds apart,
including transient-error retries. HTTP 429 receives one deferred retry after the
first team pass; the entire client honors the full Retry-After seconds or HTTP date.
Absent/invalid Retry-After means a five-minute cooldown. Shared projection 429 can
also retry once after cooldown. If the cooldown plus a 45-second request cannot fit
within the 30-minute fetch budget, it fails without making an early request.
Healthy snapshots publish even when other teams fail. Failed snapshots keep their
last-good bytes, and unresolved errors fail the workflow so notifications remain.
Fetching/cooldowns use a separate pitching lock; only the short publication job
holds `site-data-writes`. Its artifact contains changed healthy files only.

## Manual refresh and season transition

Use **Refresh MLB pitching data → Run workflow** for a refresh under the policy.
After freeze, enable the `force` input only to deliberately refresh the configured
season. Locally, `python3 scripts/refresh_pitching.py --force` is equivalent;
`--team giants` can narrow a local investigation. Legacy pitching scripts also use
the policy. Force does not change the season or projection URL.

Before enabling 2027, explicitly review the FanGraphs projection source and confirm
it represents the intended 2027 Steamer baseline. The current endpoint is unversioned:
a matching `projection_season` is an operator assertion, not provider verification.
Never force a historical refresh after that endpoint has rolled forward; retain
2026 snapshots or supply a verified historical projection source. In a reviewed PR,
set `season`, `projection_season`, `projections_url`, and `refresh_until` together.
Choose and review the new season's schedule separately; this October-only schedule
does not enable daily in-season refreshes. Validate mocked regressions with
`python3 -m unittest discover -s scripts -p 'test_pitching_refresh.py'` and inspect
the resulting feeds before publication. Existing 2026 snapshots stay untouched by
this code change and by winter no-op runs.

GitHub hosted-runner outages are infrastructure failures; this change cannot fix
them. FanGraphs may still rate-limit beyond the bounded retry budget, which remains
an explicit workflow failure rather than a fabricated or empty snapshot.
