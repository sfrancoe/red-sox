import Foundation

/// Generated from data/mlb300-hitters.json by scripts/fetch_hitter_story.py.
enum MLB300HitterPlayers {
    struct Player: Identifiable {
        let id: Int
        let name: String
        let average: String
    }
    static let peakYear = 1999
    static let peak: [Player] = [
        .init(id: 123833, name: "Larry Walker", average: ".379"),
        .init(id: 114596, name: "Nomar Garciaparra", average: ".357"),
        .init(id: 116539, name: "Derek Jeter", average: ".349"),
        .init(id: 124288, name: "Bernie Williams", average: ".342"),
        .init(id: 118365, name: "Edgar Martinez", average: ".337"),
        .init(id: 114935, name: "Luis Gonzalez", average: ".336"),
        .init(id: 110029, name: "Bobby Abreu", average: ".335"),
        .init(id: 120903, name: "Manny Ramirez", average: ".333"),
        .init(id: 123744, name: "Omar Vizquel", average: ".333"),
        .init(id: 121358, name: "Ivan Rodriguez", average: ".332"),
        .init(id: 112087, name: "Sean Casey", average: ".332"),
        .init(id: 114079, name: "Tony Fernández", average: ".328"),
        .init(id: 112297, name: "Jeff Cirillo", average: ".326"),
        .init(id: 114932, name: "Juan Gonzalez", average: ".326"),
        .init(id: 115210, name: "Mark Grudzielanek", average: ".326"),
        .init(id: 113946, name: "Carl Everett", average: ".325"),
        .init(id: 114844, name: "Doug Glanville", average: ".325"),
        .init(id: 120191, name: "Rafael Palmeiro", average: ".324"),
        .init(id: 110183, name: "Roberto Alomar", average: ".323"),
        .init(id: 123041, name: "Mike Sweeney", average: ".322"),
        .init(id: 111792, name: "Homer Bush", average: ".320"),
        .init(id: 115732, name: "Todd Helton", average: ".320"),
        .init(id: 116706, name: "Chipper Jones", average: ".319"),
        .init(id: 123690, name: "Randy Velarde", average: ".317"),
        .init(id: 115223, name: "Vladimir Guerrero", average: ".316"),
        .init(id: 114789, name: "Brian Giles", average: ".315"),
        .init(id: 115378, name: "Darryl Hamilton", average: ".315"),
        .init(id: 114739, name: "Jason Giambi", average: ".315"),
        .init(id: 115749, name: "Rickey Henderson", average: ".315"),
        .init(id: 120922, name: "Joe Randa", average: ".314"),
        .init(id: 112155, name: "Roger Cedeno", average: ".313"),
        .init(id: 124185, name: "Rondell White", average: ".312"),
        .init(id: 118730, name: "Fred McGriff", average: ".310"),
        .init(id: 115007, name: "Mark Grace", average: ".309"),
        .init(id: 115094, name: "Shawn Green", average: ".309"),
        .init(id: 122989, name: "B.J. Surhoff", average: ".308"),
        .init(id: 113028, name: "Johnny Damon", average: ".307"),
        .init(id: 123245, name: "Frank Thomas", average: ".305"),
        .init(id: 110135, name: "Edgardo Alfonzo", average: ".304"),
        .init(id: 116852, name: "Eric Karros", average: ".304"),
        .init(id: 121357, name: "Henry Rodriguez", average: ".304"),
        .init(id: 110432, name: "Jeff Bagwell", average: ".304"),
        .init(id: 123723, name: "Jose Vidro", average: ".304"),
        .init(id: 122784, name: "Shannon Stewart", average: ".304"),
        .init(id: 110236, name: "Garret Anderson", average: ".303"),
        .init(id: 124326, name: "Matt Williams", average: ".303"),
        .init(id: 120536, name: "Mike Piazza", average: ".303"),
        .init(id: 112116, name: "Luis Castillo", average: ".302"),
        .init(id: 122111, name: "Gary Sheffield", average: ".301"),
        .init(id: 117863, name: "Kenny Lofton", average: ".301"),
        .init(id: 120044, name: "Magglio Ordonez", average: ".301"),
        .init(id: 123697, name: "Robin Ventura", average: ".301"),
        .init(id: 150334, name: "Chris Singleton", average: ".300"),
        .init(id: 117759, name: "Mike Lieberthal", average: ".300"),
        .init(id: 115114, name: "Rusty Greer", average: ".300"),
    ]
    static let latestYear = 2026
    static let latest: [Player] = [
        .init(id: 670541, name: "Yordan Alvarez", average: ".316"),
        .init(id: 672515, name: "Gabriel Moreno", average: ".311"),
        .init(id: 650333, name: "Luis Arraez", average: ".310"),
        .init(id: 802415, name: "Chandler Simpson", average: ".306"),
        .init(id: 672640, name: "Otto Lopez", average: ".305"),
        .init(id: 693304, name: "Nick Gonzales", average: ".302"),
        .init(id: 681198, name: "TJ Rumfield", average: ".300"),
    ]
}
