# Free career-stat sources for a commercial iPhone/iPad app

Research date: September 5, 2026

## Recommendation

Use **Retrosheet** for career statistics and the **Chadwick Baseball Bureau Persons Register** for player identity matching.

This is the clearest no-fee path I found for a commercial product:

- Retrosheet explicitly permits selling data and producing commercial products from it, provided its required credit is displayed prominently.
- It provides downloadable game-level batting, pitching, and fielding records through the completed 2025 season.
- Individual-player downloads are small, so the app's build process can fetch only the players on the Red Sox roster rather than ingesting the complete historical archive.
- The Chadwick Register provides cross-references among Retrosheet, MLBAM, Baseball Reference, FanGraphs, and Wikidata identifiers. It is licensed under ODC Attribution 1.0, which explicitly allows commercial use with attribution.

This route is **annual, not live**. During the 2026 season, the honest UI label would be “Career through 2025.” Players who debuted in 2026 would show “No MLB career stats in the current data release” until Retrosheet publishes 2026.

## What the app can show

For hitters, Retrosheet supplies the inputs for games, plate appearances, at-bats, runs, hits, doubles, triples, home runs, RBI, walks, strikeouts, stolen bases, caught stealing, hit-by-pitch, sacrifice flies, AVG, OBP, SLG, and OPS.

For pitchers, it supplies the inputs for games, starts, wins, losses, saves, innings pitched, hits, runs, earned runs, home runs, walks, strikeouts, hit batters, wild pitches, balks, complete games, ERA, and WHIP.

It also has fielding totals by player and position. Regular season, postseason, exhibitions, and other game types are identified, so career totals can be limited to the familiar regular-season line.

Retrosheet does not publish Baseball Reference's WAR or OPS+ values. We should not copy those values from Baseball Reference. OPS can be calculated directly. A custom adjusted metric or WAR-like model is possible later, but it would require a documented methodology and would not necessarily match Baseball Reference.

## Source comparison

| Source | Free | Commercial app | Freshness | Coverage | Verdict |
|---|---:|---:|---|---|---|
| Retrosheet | Yes | Explicitly permitted with required credit | Through 2025; annual | Detailed batting, pitching, fielding, game context | **Primary recommendation** |
| Chadwick Register | Yes | ODC Attribution permits commercial use | Public extract updated roughly weekly | Identity crosswalk, not statistics | **Use with Retrosheet** |
| SABR Lahman Database | Yes | CC BY-SA 3.0 permits commercial use with attribution and share-alike duties | Through 2025; annual | Convenient season-level career statistics | Strong fallback, but share-alike is less convenient |
| MLB Stats API | No fee to call | Published MLB notice limits use to individual, non-commercial, non-bulk use without permission | Live | Excellent official coverage | Do not use for the commercial Players feature without written permission |
| Baseball Reference | Free to browse | Terms prohibit building a competing/substitute data store from scraped content | Live | Excellent, including WAR and OPS+ | Do not scrape |
| FanGraphs | Free to browse | Terms prohibit commercial exploitation of the service without authorization | Live | Excellent advanced statistics | Do not scrape |
| API-Baseball | Free tier | Terms state site material is for personal, non-commercial use | Live/API | General baseball API | Not suitable |
| TheSportsDB | Free development API | App-store publication requires a paid subscription | Varies | Crowd-sourced; MLB depth is uncertain | Not actually free for this product |

## Practical validation against this app

The current roster feed contains 47 players. The Chadwick public crosswalk directly matched 38 using the existing MLBAM or Wikidata identifiers. Several of the remaining names can be resolved safely by exact name plus playing-year checks. The others are 2026-only or pre-debut players and therefore cannot appear in a dataset whose latest season is 2025.

An individual Retrosheet career-log download for Wilyer Abreu was under 8 KB, confirming that a roster-scoped refresh is practical. The build should save a verified, frozen JSON snapshot in the iOS bundle; the phone should not depend on Retrosheet being online.

## Proposed implementation

1. Extend the existing player refresh script to load the current roster and resolve each player to a stable Retrosheet ID through Chadwick.
2. Download each matched player's Retrosheet log and retain regular-season records with the appropriate published statistic value.
3. Aggregate and independently calculate rate statistics, with explicit tests for innings, AVG, OBP, SLG, OPS, ERA, and WHIP.
4. Cross-check a sample of veteran hitters, pitchers, traded players, two-way players, and 2025 rookies against a second source before shipping.
5. Bundle the result in the app with `stats_through: 2025`, source metadata, and a clear unavailable state for 2026 debuts.
6. Add the required Retrosheet credit and Chadwick/ODC attribution to an in-app Sources screen and the App Store support/privacy pages.
7. Refresh annually. If live in-season career totals later become essential, replace or supplement this feed with a paid commercial license.

## Primary references

- [Retrosheet CSV downloads, coverage, and commercial-use notice](https://www.retrosheet.org/downloads/csvdownloads.html)
- [Retrosheet CSV field definitions](https://www.retrosheet.org/downloads/csvcontents.html)
- [Retrosheet individual player logs](https://www.retrosheet.org/downloads/csvplayers.html)
- [Chadwick Persons Register identifiers and license](https://github.com/chadwickbureau/register)
- [ODC Attribution 1.0 license](https://opendatacommons.org/licenses/by/1-0/)
- [SABR Lahman Database current release](https://sabr.org/lahman-database/)
- [Lahman 2025 distributed license notice](https://github.com/myceliumdata/lahman-seed/blob/main/lahman_1871-2025_csv/readme2025.txt)
- [Sports Reference data-use policy](https://www.sports-reference.com/data_use.html)
- [FanGraphs terms](https://www.fangraphs.com/about/terms-of-service)
- [API-Baseball terms](https://www.api-baseball.com/terms)
- [TheSportsDB terms](https://www.thesportsdb.com/docs_terms_of_use.php)

## Legal note

This is a technical and source-policy assessment, not legal advice. Before a commercial launch, counsel should review the exact attribution placement and the app's use of team and league trademarks. The recommended data licenses do not grant rights to MLB, Red Sox, or player imagery and logos.
