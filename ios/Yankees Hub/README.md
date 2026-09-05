# NY Baseball Hub iOS app

NY Baseball Hub is a separate iPhone and iPad app built from the Hub Ball foundation. It has its own Xcode project, bundle identifier (`com.sfrancoe.Yankees-Hub`), app icon, branding, and bundled offline data. Installing it does not replace or alter the Boston Baseball Hub app.

The app uses MLB team ID 147 and reads its generated data from `/data/yankees/`. Its eight sections are Games, Schedule, Newspapers, X Posts, Standings, Pitching, Leaders, and Markets. There is no Game 108 section.

The Markets tab combines public Kalshi and Polymarket prices for Yankees game and season markets. It uses the team-isolated `/api/yankees-markets` endpoint, keeps a separate on-device snapshot cache, and follows the same read-only table, filters, details, history, freshness, and outage behavior as the Boston app.

The newspaper page uses The New York Times Yankees collection, New York Post Yankees page, New York Daily News Yankees page, and The Athletic Yankees feed. The refresh scripts keep each feed in its own Yankees namespace and the iOS bundle contains the latest successful snapshot for offline fallback.

The X page combines the Yankees list at `https://x.com/i/lists/2095986539037647187` with a recent X search. List posts are filtered against Yankees terms and the current roster before they reach Most Recent; Most Liked merges those filtered posts with highly engaged Yankees search results from the past 24 hours.

Open `Yankees Hub.xcodeproj` in Xcode to run the app. The target supports iPhone and iPad on iOS 17 or later. TestFlight distribution requires a separate App Store Connect app record for the Yankees bundle identifier.

The X Posts tab expects `/api/x-posts?team=yankees` for its curated list and `/api/x-discovery?team=yankees` for supplemental popular posts. Live discovery uses the existing metered X API configuration.
