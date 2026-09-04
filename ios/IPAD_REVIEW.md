# Hub Ball iPad layout — next TestFlight batch

Scott authorized the TestFlight upload on September 4, 2026. Release archive 1.0 (2) passed. App Store Connect accepted the upload at 13:32 Eastern. Export compliance was completed and build 1.0 (2) is available to the Friends & Family external testing group.

## Layout behavior

- Navigation follows available window width: two rows below 650 points, one larger row from 650 points, sidebar from 1000 points.
- The sidebar opens by default and can be hidden or restored with the top-left sidebar button. This choice persists between sections and app launches; hiding it lets content use the full window width. Simulator hide/show and persistence after reopening verified; simulator and device builds passed.
- Content width excludes the sidebar only while it is visible. Rotation preserves the current screen and its selection.
- Games place batting and pitching side by side from 720 points of content width, below the recap and above scoring plays. Narrow layouts stack the tables. Batting excludes entries whose position is P, SP, or RP; designated hitters and other batting roles remain. Boston/opponent selection and portrait/landscape layouts checked on iPad Pro; simulator and device builds passed.
- Tablet standings use a bounded team-name column and distribute remaining width across statistics, keeping W/L close to the team and headers aligned with values. Division layouts visually checked in portrait and landscape on iPad Pro; simulator and device builds passed.
- Standings no longer shows the red vertical marker beside Boston. Device build passed.
- Games scoreboard uses equal flexible widths for all inning and R/H/E/LOB columns in headers and team rows. Portrait and landscape alignment visually checked on iPad Pro; simulator and device builds passed.
- Schedule uses a calendar and selected-game detail column at the same threshold.
- Pitching reports use up to two columns with a 340-point minimum card width. Standings requires 440 points per column.
- Leaders uses four season boxes in a two-by-two grid from 650 points of content width, with six categories in full-width rows in tall boxes (15-point names/values, left-aligned category headings above players with a thin divider directly under each heading). Wider boxes retain two columns and three evenly spaced rows. Portrait rows use the available height without large gaps between small text blocks. All four boxes remain visible; the latest portrait heading layout and all entries were visually checked on iPad Pro. Smaller boxes can scroll their contents. Individual boxes scroll for overflow in smaller windows or larger text sizes. Compact layouts retain the scrolling season list. Simulator and device builds passed.
- The pitching graph uses 55% of the available page height on tablet-width layouts, with a 380-point minimum, and resizes on rotation. Compact layouts retain 270 points. Portrait and landscape visually checked on iPad mini; simulator and device builds passed.
- Pitching graph labels prioritize up to ten notable pitchers on tablet (eight compact), placing names beside dots only when they fit without intersecting another label or dot. No label connector lines. All pitcher dots and reports remain available. Combined graph visually checked on iPad Pro; simulator and device builds passed.
- Pitching filters are Both, Starters, Relievers, with Both selected initially. Graph and reports share the selected filter and existing report sort. All three filter selections verified in the iPad simulator; combined chart inspected in portrait and landscape.
- Newspapers portrait experiment: at content widths of 720 points or more and available height greater than width, show Globe/Herald above Athletic/MassLive in four equal quadrants with centered white newspaper titles on pinned hunter-green header bars, no source pickers, and independent scrolling. Quadrants use continuous white backgrounds, 17-point bold headlines, 13-point descriptions, and thin story dividers instead of individual cards. Visually checked on iPad mini and installed on Scott’s iPad for comparison. Landscape retains two independently selectable publications, defaulting to Globe and Herald. Each column has its own scrolling headlines. Narrow windows retain one publication. Simulator build and iPad mini portrait/source selection verified.
- Tablet text, calendar cells, post images, and charts get more space. Short graph windows can scroll to the controls.
- Newspapers show a red inline ⚡ NEW marker at the end of each headline for articles published less than six hours ago. Shared headline rendering covers quadrants and cards; a minute timeline updates recency while visible. Future or invalid timestamps are not marked. Eight boundary/time-zone/date-parser checks passed; portrait and landscape badges visually checked in the iPad mini simulator. Simulator and device builds passed.
- Wide layouts use explicit section navigation; page swipes stay inside X Posts. Compact edge swipes use local view coordinates instead of physical-screen bounds.
- X Posts shows Most Liked on the left and Most Recent on the right from 720 points of content width, with pinned headings and independent scrolling. Narrower windows retain the tabs, with Most Liked first and selected by default. Simulator and device builds passed; installed and launched on Scott’s iPad for review.

## Verified September 4, 2026

- Debug iOS Simulator build succeeded; no signing, archive, or upload.
- iPad Pro 13-inch: all eight screens visually inspected in the simulator; landscape game columns, calendar selection/detail update, X feed switching, and graph playback checked.
- iPad mini: portrait and landscape inspected; navigation reflows and retains the selected X feed across rotation. Final portrait scoreboard label and X post header corrections visually checked.
- iPhone 17: compact Games screen visually checked for regression.
- `git diff --check` passed.
- Review screenshots are generated under `dist/ipad-review/` and excluded from Git.

Physical iPad testing, split/windowed multitasking, accessibility text sizes, and older supported iPadOS versions have not been validated in this pass. Include those in the device review before release; full-screen simulator coverage is not a substitute.
