# NY Baseball Hub iOS app

NY Baseball Hub is a separate iPhone and iPad app built from the Hub Ball foundation. It has its own Xcode project, bundle identifier (`com.sfrancoe.Yankees-Hub`), app icon, branding, and bundled offline data. Installing it does not replace or alter the Boston Baseball Hub app.

The app uses MLB team ID 147 and reads its generated data from `/data/yankees/`. Its seven sections are Games, Schedule, Newspapers, X Posts, Standings, Pitching, and Leaders. There is no Game 108 section.

The newspaper page uses The New York Times Yankees collection, New York Post Yankees page, New York Daily News Yankees page, and The Athletic Yankees feed. The refresh scripts keep each feed in its own Yankees namespace and the iOS bundle contains the latest successful snapshot for offline fallback.

Open `Yankees Hub.xcodeproj` in Xcode to run the app. The target supports iPhone and iPad on iOS 17 or later. TestFlight distribution requires a separate App Store Connect app record for the Yankees bundle identifier.

The X Posts tab expects `/api/x-discovery?team=yankees`. Enabling its live discovery query uses the metered X API and should remain undeployed until that cost is approved.
