# Native large-text regression checks

Run from the `Hub Ball Large Text` checkout on a Mac with Xcode. These tests use
XCTest to operate the simulator's native app UI; no browser or third-party package
is involved. Do not run two test processes against the same simulator.

```bash
xcrun simctl list devices available
bash scripts/test_large_text_ui.sh SIMULATOR_UUID unique-run-name \
  testCareerBattingRecordsAndTotals testCareerPitchingRecordsAndTotals \
  testPlayerMenusAndStoryCards testTextClippingAudit
python3 scripts/test_large_text_live_size.py SIMULATOR_UUID unique-live-run-name
```

Omit method names to run the regular suite. The live-size case intentionally skips
outside its coordinating Python runner. The narrow-window case skips on phones.
Run names must be unique. The project generator copies the existing app project
configuration to `dist/large-text-ui/`, adds the UI-test target, and leaves the
release project unchanged. Screenshots, accessibility trees, logs, and `.xcresult`
bundles stay under that gitignored directory. The shell runner exports attachments;
`xcrun xcresulttool export attachments` can export a manually invoked run too.

The suite launches with onboarding already completed unless testing onboarding
itself. Its Debug-only reset argument clears that one preference before launch,
allowing the real Follow action to save completion. Player IDs, story data, and
recent games are real app data, not invented layout fixtures. Feed changes can
require updating the chosen player/recap assertion. Simulator preferences are
local test state; do not use a personal device. Tests restore portrait orientation;
the live-size runner restores the original system text category, and the iPad test
uses the native Window Controls / Zoom action to restore a full-width window.

## What assertions establish

- All-sections cases navigate ten sections, scroll three times, and capture portrait
  and landscape. They sample layouts; they do not certify every row or error state.
- Career-total cases require every expected metric and a nonempty accessible value
  to become fully visible beneath the navigation area. Batting has 15 metrics;
  pitching has 13. These inspect accessibility values, not spoken VoiceOver output.
- Recap checks horizontally reach LOB and open a player without changing sections.
- Picker tests exercise filter, sort, standings, pitching, leaderboard, and Settings
  choices. Story tests cover the specific playback/progress/source actions in code.
- Text-clipping audits use Apple's `.textClipped` audit without suppressing failures.
  They run on the displayed Home, Players, Standings, and selected Stories content;
  they are not an app-wide accessibility audit.
- Live-size checks change the actual simulator category while the app remains open.
  Launch-argument size overrides in the other tests do not change system preferences.

Spoken VoiceOver, Display Zoom, older-runtime behavior, and the unexercised cases
listed in the audit report still require separate checks. Keep failed attempts and
superseding passes distinguishable when reporting results.
