# October 9 private comparison build

Scott authorized building all three pitches and delivering the next TestFlight build only to him. These candidates are bundled for comparison; none is in the shared production catalog.

Open Hub Ball, dismiss the existing White Sox launch card, open Stories, and choose “Three October 9 stories.” Watch a candidate and use Back to return to the comparison list. Done closes Stories. Reopening a chart restarts its playback. All three work offline immediately.

- The Sixth That Saved October: Cleveland and Chicago step-score lines after each completed half-inning; seven seconds with a 0.7-second hold after the top of the sixth. x=5.5 means that half-inning is complete. Axes are 0–9 innings and 0–10 runs.
- Four Games. Never Breathing Room.: four Milwaukee margin step lines, two seconds per game, retaining earlier lines. The common axes are 0–9 and −3 to +3, with −2/0/+2 ticks and a clear zero line. Unplayed final home half-innings in Games 1 and 3 carry the final margin forward for axis alignment.
- Four Saves. Then Forty-One.: six regular-season annual bars (2021–2026: 0/1/0/0/3/41), six seconds, zero baseline and 0–45 scale. The separate closing caption records one Baker save in each of three ALDS wins. The combined-team 2025 row is selected once.

Facts were rechecked against official linescores, schedule team/date context, yearly statistics, and three ALDS box scores. The source proof is private-october9-source.json; sources and methodology accompany each chart. The generator and original native graphics include no third-party images, logos, music or copied article prose. Public source access is not treated as a commercial reuse license.

PrivateStoryPreviews decodes and validates its separate bundled catalog and three immutable-hash payloads. These documents never enter StoryCatalogStore, its remote catalog, loader, or cache. A production refresh, an empty catalog or a network outage therefore cannot remove them. Story-private JSON lives only in the native app resource folder; build_site.sh excludes it. data/stories/catalog-v1.json and both existing stories are unchanged.

This release stays on local canonical main and is not pushed to GitHub or deployed to hosting. Only Scott’s verified one-member internal TestFlight group receives its binary. Before any later public/external build, remove this comparison set or explicitly decide what to retain after Scott chooses a story. Publishing a selected story requires a separate validated content release. Do not promote this comparison binary to Family without explicit authorization.

Implementation: ios/Hub Ball/Hub Ball/PrivateStoryPreviews.swift, StoriesView.swift, TrajectoryStory.swift, TrajectoryStoryView.swift, story-private-*.json. Authoring: scripts/build_private_october9.py. Tests: PrivateStoryPreviewTests.swift, PrivateStoryPreviewUITests.swift and scripts/test_private_october9.py. Release results, screenshots, source snapshots and audience/archive receipts stay under ignored dist/private-october9 and dist/large-text-ui.
