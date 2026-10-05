# Expansion news source alerts

Scope: `fetch_team_news.py` and the scheduled/manual **Refresh MLB expansion team
news** workflow, currently 26 expansion teams. This is the Bing RSS incident path.
The Red Sox, Yankees, Mets, Rays and postseason news workflows retain their existing
alert behavior. No notification account settings change. PR9 source isolation and
PR10 pitching policy/pacing/publication remain intact.

Only exhausted transient RSS retrieval failures (network errors/timeouts, HTTP 429
or 5xx, malformed XML) qualify for delayed alerts. Every such failure logs the team,
source, error and streak and appears in the job summary. First failure is a visible
warning and does not fail the job. The second consecutive eligible failure and each
subsequent failure are alerts that fail the job after healthy sources publish.
A verified source success, including unchanged articles, resets that source alone.
Valid RSS with no matching articles remains PR9's warning/last-good behavior: it is
ineligible and neither increments nor resets the streak. Unselected sources are
also ineligible. Streaks follow team API key plus source key, independently.

Code/configuration failures, nontransient HTTP errors, certificate trust failures,
unexpected response shape, missing/corrupt/inconsistent state, invalid/changed source
identity, duplicate selected sources, disk/summary/output failures, no configured
sources, and failure of every selected source remain immediate failures. Source
code errors are reported independently while healthy sources finish. Integrity or
I/O failures abort publication of the entire batch. Individual transient failures
never overwrite their last-good feeds; atomic replacement protects feed/status files
from interrupted writes. A total transient outage still records streaks but fails
immediately, even on the first update.

## State and publication

`.github/news-status/expansion.json` is a versioned repository state file. The seed
ships empty; previously unseen sources start at zero. Missing state never silently
reinitializes. Each observed source stores its URL, consecutive failure count and
last error. URL changes require an explicit status migration. Healthy unchanged
sources do not churn state. State-only commits are automation changes and use the
existing Netlify ignore policy.

An eligible refresh is one complete fetch batch whose source status and healthy
feed updates successfully publish together. The workflow retains `site-data-writes`
serialization, checks out `main`, and fast-forwards to the latest published state
before calculating streaks. It stages status and healthy data in one commit and
pushes directly; it does not rebase calculated streaks onto newer state. A competing
main update, failed commit/push, aborted fetch, or interrupted job remains an
immediate workflow failure; an unpublished batch does not advance persisted streaks.
A subsequent refresh reads the last published state. Complete batches emit
`publish_ready=true`, allowing publication even when persistent-source/code failures
make the fetch step fail; incomplete/integrity-failed batches emit no marker and are
not committed. This deliberately chooses safety over retrying a stale publication.

No workflow was manually dispatched and no production refresh/deployment is needed
to test this. Offline tests mock retrieval and use temporary data plus bare Git
repositories. They cover first/second failures, recovery, alternating sources, empty
searches, unchanged snapshots, total outages, code/config errors, missing/corrupt
state, duplicate/changed identities, atomic-write failure, partial healthy
publication and rejection of a competing publication. Existing pitching and
postseason regressions are unchanged.

```sh
python3 scripts/test_fetch_team_news.py
python3 scripts/test_news_alert_publication.py
python3 -m unittest discover -s scripts -p 'test_pitching_refresh.py'
python3 -m unittest discover -s scripts -p 'test_refresh_reliability.py'
python3 -m unittest discover -s scripts -p 'test_fetch_postseason_news.py'
python3 scripts/test_team_registry.py
python3 scripts/test_open_players.py
bash scripts/test_netlify_ignore.sh
```
