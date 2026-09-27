import Foundation

/// Generated from data/mlb300-hitters.json by scripts/fetch_hitter_story.py.
enum MLB300HitterPlayers {
    struct Player: Identifiable {
        let id: Int
        let name: String
        let team: String
        let average: String
    }
    static let peakYear = 1999
    static let peak: [Player] = [
        .init(id: 123833, name: "Larry Walker", team: "COL", average: ".379"),
        .init(id: 114596, name: "Nomar Garciaparra", team: "BOS", average: ".357"),
        .init(id: 116539, name: "Derek Jeter", team: "NYY", average: ".349"),
        .init(id: 124288, name: "Bernie Williams", team: "NYY", average: ".342"),
        .init(id: 118365, name: "Edgar Martinez", team: "SEA", average: ".337"),
        .init(id: 114935, name: "Luis Gonzalez", team: "ARI", average: ".336"),
        .init(id: 110029, name: "Bobby Abreu", team: "PHI", average: ".335"),
        .init(id: 120903, name: "Manny Ramirez", team: "CLE", average: ".333"),
        .init(id: 123744, name: "Omar Vizquel", team: "CLE", average: ".333"),
        .init(id: 121358, name: "Ivan Rodriguez", team: "TEX", average: ".332"),
        .init(id: 112087, name: "Sean Casey", team: "CIN", average: ".332"),
        .init(id: 114079, name: "Tony Fernández", team: "TOR", average: ".328"),
        .init(id: 112297, name: "Jeff Cirillo", team: "MIL", average: ".326"),
        .init(id: 114932, name: "Juan Gonzalez", team: "TEX", average: ".326"),
        .init(id: 115210, name: "Mark Grudzielanek", team: "LAD", average: ".326"),
        .init(id: 113946, name: "Carl Everett", team: "HOU", average: ".325"),
        .init(id: 114844, name: "Doug Glanville", team: "PHI", average: ".325"),
        .init(id: 120191, name: "Rafael Palmeiro", team: "TEX", average: ".324"),
        .init(id: 110183, name: "Roberto Alomar", team: "CLE", average: ".323"),
        .init(id: 123041, name: "Mike Sweeney", team: "KCR", average: ".322"),
        .init(id: 111792, name: "Homer Bush", team: "TOR", average: ".320"),
        .init(id: 115732, name: "Todd Helton", team: "COL", average: ".320"),
        .init(id: 116706, name: "Chipper Jones", team: "ATL", average: ".319"),
        .init(id: 123690, name: "Randy Velarde", team: "OAK", average: ".317"),
        .init(id: 115223, name: "Vladimir Guerrero", team: "MON", average: ".316"),
        .init(id: 114789, name: "Brian Giles", team: "PIT", average: ".315"),
        .init(id: 115378, name: "Darryl Hamilton", team: "NYM", average: ".315"),
        .init(id: 114739, name: "Jason Giambi", team: "OAK", average: ".315"),
        .init(id: 115749, name: "Rickey Henderson", team: "NYM", average: ".315"),
        .init(id: 120922, name: "Joe Randa", team: "KCR", average: ".314"),
        .init(id: 112155, name: "Roger Cedeno", team: "NYM", average: ".313"),
        .init(id: 124185, name: "Rondell White", team: "MON", average: ".312"),
        .init(id: 118730, name: "Fred McGriff", team: "TBD", average: ".310"),
        .init(id: 115007, name: "Mark Grace", team: "CHC", average: ".309"),
        .init(id: 115094, name: "Shawn Green", team: "TOR", average: ".309"),
        .init(id: 122989, name: "B.J. Surhoff", team: "BAL", average: ".308"),
        .init(id: 113028, name: "Johnny Damon", team: "KCR", average: ".307"),
        .init(id: 123245, name: "Frank Thomas", team: "CWS", average: ".305"),
        .init(id: 110135, name: "Edgardo Alfonzo", team: "NYM", average: ".304"),
        .init(id: 116852, name: "Eric Karros", team: "LAD", average: ".304"),
        .init(id: 121357, name: "Henry Rodriguez", team: "CHC", average: ".304"),
        .init(id: 110432, name: "Jeff Bagwell", team: "HOU", average: ".304"),
        .init(id: 123723, name: "Jose Vidro", team: "MON", average: ".304"),
        .init(id: 122784, name: "Shannon Stewart", team: "TOR", average: ".304"),
        .init(id: 110236, name: "Garret Anderson", team: "ANA", average: ".303"),
        .init(id: 124326, name: "Matt Williams", team: "ARI", average: ".303"),
        .init(id: 120536, name: "Mike Piazza", team: "NYM", average: ".303"),
        .init(id: 112116, name: "Luis Castillo", team: "FLA", average: ".302"),
        .init(id: 122111, name: "Gary Sheffield", team: "LAD", average: ".301"),
        .init(id: 117863, name: "Kenny Lofton", team: "CLE", average: ".301"),
        .init(id: 120044, name: "Magglio Ordonez", team: "CWS", average: ".301"),
        .init(id: 123697, name: "Robin Ventura", team: "NYM", average: ".301"),
        .init(id: 150334, name: "Chris Singleton", team: "CWS", average: ".300"),
        .init(id: 117759, name: "Mike Lieberthal", team: "PHI", average: ".300"),
        .init(id: 115114, name: "Rusty Greer", team: "TEX", average: ".300"),
    ]
    static let latestYear = 2026
    static let latest: [Player] = [
        .init(id: 670541, name: "Yordan Alvarez", team: "HOU", average: ".316"),
        .init(id: 672515, name: "Gabriel Moreno", team: "ARI", average: ".311"),
        .init(id: 650333, name: "Luis Arraez", team: "PHI", average: ".310"),
        .init(id: 802415, name: "Chandler Simpson", team: "TBR", average: ".306"),
        .init(id: 672640, name: "Otto Lopez", team: "MIA", average: ".305"),
        .init(id: 693304, name: "Nick Gonzales", team: "PIT", average: ".302"),
        .init(id: 681198, name: "TJ Rumfield", team: "COL", average: ".300"),
    ]
}
