# Hub Ball: Netlify cost-reduction review follow-up

Prepared September 8, 2026 for Sol. This is a focused follow-up to PR #2, not a request to repeat the cost investigation.

## Objective and scope

Fix the reproduced rename bug in the build-ignore script, then complete the outstanding production verification for data-only and iOS-only changes. Preserve the existing data freshness, website, backend, and native app behavior. Do not broaden this into a hosting migration or polling refactor.

Repository: https://github.com/sfrancoe/red-sox

Reviewed production commit: `37b330f319a560a91a50468344f95c47d433c683` (PR #2).

Preserve the dirty checkout at `/Users/sfrancoe/Projects/MLB Apps`. Fetch current remote state and use a clean worktree. The previous implementation worktree was `/private/tmp/hub-ball-netlify-c4IPX4`; verify its state before reusing it. Read applicable repository instructions. No dependencies or paid API calls.

This document describes the work; it does not grant new release authorization. Follow the user's explicit instructions in the implementation session, including any existing authorization to merge and deploy. Do not create artificial production deployments solely for verification.

## 1. Reproduced bug: a rename can hide a deployed-file deletion

Location: `scripts/netlify_ignore.sh`, around line 28:

```bash
git diff --name-only --diff-filter=ACDMRTUXB "$cached_ref" "$commit_ref" --
```

With rename detection enabled, `--name-only` reports the destination of a detected rename. If a deployed file moves into a directory classified as non-deploying, the script misses the removal from its original deployed path and incorrectly skips the build.

Independently reproduced in an isolated Git fixture:

1. Commit `src/removed.js` containing `export const publicAsset = true;`.
2. Move it unchanged to `docs/removed.js` and commit.
3. Run the production ignore script with `CACHED_COMMIT_REF` pointing to the first commit and `COMMIT_REF` to the second. Set `git config diff.renames true` in the fixture to make the condition explicit.

Git reports:

```text
R100    src/removed.js    docs/removed.js
```

Actual result:

```text
Netlify build skipped: only generated data, native app, docs, or automation files changed
Exit: 0
```

Expected result: exit **1**, allowing a deployment to remove the old public asset. The same problem can affect a function moved into an ignored directory. It leaves obsolete deployed content or code live until another change triggers a build.

### Required fix and tests

Make the classification account for both sides of a rename. A small solution is to disable rename detection for this comparison so the move appears as a deletion plus an addition. Alternatively, explicitly parse both old and new paths. Preserve the full cached-to-target comparison and the existing conservative behavior on invalid or unavailable references.

Add isolated regression tests covering:

- Public asset moved into `docs/`: build.
- Netlify function moved into an ignored directory: build.
- Ignored file moved into a deployed directory: build.
- Move entirely within ignored directories: skip.
- Public-to-public rename and public-file deletion: build.

Run the existing ignore-script tests, gateway tests, registry validation, and static build. Do not change generated data or manufacture production commits for tests.

The review already passed these checks on the prior implementation:

```bash
bash scripts/test_netlify_ignore.sh
node scripts/test_app_data.mjs
python3 scripts/test_team_registry.py
bash scripts/build_site.sh
```

The existing tests passed because they did not cover a deployed-to-ignored rename. Add the failing regression before applying the fix, then demonstrate that it passes afterward.

## 2. Pending: verify actual production skips and data freshness

The review independently confirmed that commit `37b330f` was published on September 8 at 8:13 AM Eastern, with seven functions deployed and a nine-second build/deploy duration:

https://app.netlify.com/projects/red-sox/deploys/6a9ffbf145d6c6000838d78c

At review time, no subsequent data-only commit had landed. Therefore, the production deployment was verified, but an actual data-refresh skip and freshness after that skip were not yet verified. Check current history first; natural refreshes may have occurred since this brief was written.

### Data-only acceptance check

1. Identify a naturally occurring data-only commit after the ignore rule was deployed. Confirm the actual comparison contains no pending deployed-file changes.
2. Find its corresponding Netlify event/log and verify that the ignore command skipped/canceled the build before a production deployment. Record the commit and event evidence. Absence of a published deployment alone is insufficient if the event could have failed for another reason.
3. Choose JSON that actually changed in that commit. Compare the current GitHub source with the corresponding production responses through both `/data/…` and `/api/data/…`. Check content or meaningful timestamps, not merely HTTP 200.
4. Allow for the gateway's configured cache freshness/revalidation behavior. Record the time checked and whether the source remained stable during the comparison.
5. Confirm that fresh data becomes available without a new successful production deployment.

Keep live probes small. Never invoke the metered `/api/x-discovery` endpoint. Do not change refresh schedules, force a data commit, or trigger a paid deployment just to produce evidence.

### iOS-only acceptance check

If a natural iOS-only commit has occurred, verify that Netlify skipped it as well. Otherwise, retain the passing local test and report this production check as pending. Do not manufacture an iOS commit for verification.

The prior authorized release already demonstrates that necessary build/configuration changes can deploy. An authorized release of the rename fix can provide the next such example; no separate test deployment is necessary.

## Completion report

Report briefly:

- Fix commit/PR, changed files, and worktree.
- Regression result before and after the fix, plus relevant checks.
- Release status and deployment evidence, if released under the user's authorization.
- Natural data-only commit, Netlify skip evidence, and content comparison for both route shapes.
- iOS-only production verification, or an explicit pending status if no suitable commit exists.

Do not claim measured savings or full production verification from local tests alone. If a natural event has not occurred, state exactly what remains to be observed rather than keeping a session waiting indefinitely or creating new scheduled automation without a user request.
