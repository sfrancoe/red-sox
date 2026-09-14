# Hub Ball Watch

Native iPhone and iPad feature. No website, backend, data pipeline, dependency,
API key, or paid service changes are required.

## Experience

- Watch follows Game Recaps in the default navigation. Existing custom page
  orders receive Watch after Game Recaps; an explicitly placed Watch stays put.
- Home has a Watch entry point.
- The selected team's channel, Around MLB, and Saved are separate collections.
- Each collection has search, a large lead video, and a responsive video grid.
- Playback opens a native full-screen destination containing YouTube's player.
  On wide iPad windows, the player and Up Next scroll independently. Compact
  iPad windows use the phone layout. Selecting Up Next returns phone users to
  the player.
- Captions, fullscreen, ads, and playback restrictions remain YouTube's controls.
  Playback requires a gesture. An Open on YouTube link stays available when a
  publisher disables embedding or a video is removed/restricted.
- Bookmarks persist on the current device. They do not download videos or sync.
- Sharing uses the native share sheet with the title, YouTube URL and
  “Found on Hub Ball”. It never automatically sends or publishes a message.

## Sources and refresh

`WatchSources.swift` records channel IDs resolved from each team's YouTube
channel on September 14, 2026. All 30 channel feeds returned 15 entries during
implementation; MLB supplies the league feed. The app reads public Atom feeds
on opening Watch and on pull to refresh. Feeds contain the most recent uploads,
including Shorts; they are not the complete channel archive and are not ranked
by popularity. The lead video is the newest upload in the current collection.

`WatchFeedParser` validates IDs, channel ownership, titles and dates, ignores
remote HTML and media URLs, and deduplicates entries. Playback/thumbnail URLs
are constructed from the validated IDs. Requests first use URLSession defaults;
one fallback uses the User-Agent specified by AGENTS.md. Last successful
listings can survive an outage for seven days, with an explicit notice and
last-check date. Video playback still requires connectivity.

YouTube player identity uses the application bundle ID in the Referer header
and origin parameter, following:
https://developers.google.com/youtube/terms/required-minimum-functionality

## Growth scope

Watch creates a repeat-use reason to open Hub Ball and puts its name in shared
videos. This is a retention and word-of-mouth foundation, not a guarantee of
organic acquisition. Shared URLs currently lead to YouTube. Once a verified
public App Store URL exists, include it in the share message so new viewers can
install Hub Ball. No invented store link, public YouTube channel creation,
uploading, analytics, or website work is included.

## Validation

- `bash scripts/test_watch.sh`: deterministic parser, all-team source coverage,
  saved-video persistence, successful refresh, offline cache and team isolation.
- Optional local live-feed fixture: `bash scripts/test_watch.sh /tmp/feed.xml`
  where the fixture is MLB's current Atom feed.
- Debug simulator build: Xcode project `ios/Hub Ball/Hub Ball.xcodeproj`,
  scheme `Hub Ball`. Launch argument `-show-watch` opens Watch directly after
  onboarding; no release version or build number changes are needed for testing.
- Before release, finish interactive iPhone and iPad checks: play/pause,
  fullscreen/captions, open-on-YouTube fallback, Up Next, split view, bookmarks,
  search/empty results, refresh, team switching, VoiceOver and share cancellation.
  These checks were blocked by the locked Mac during implementation.
