import Foundation

// Channel IDs resolved from the teams’ YouTube channels on 2026-09-14.
// Use immutable channel IDs: a renamed handle must not silently change sources.
enum WatchSources {
    static let mlb = "UCoLrcjPV5PbUrUyXq5mjc_A"

    static func channelID(for team: HubTeam) -> String {
        channels[team.apiKey] ?? mlb
    }

    static let channels: [String: String] = [
        "redsox": "UCoLrny_Oky6BE206kOfTmiw", // Boston Red Sox
        "yankees": "UCmAQ_4ELJodnKuNqviK86Dg", // New York Yankees
        "mets": "UCgIMbGazP0uBDy9JVCqBUaA", // New York Mets
        "rays": "UCZaT7TplNF541ySP8SlHVGA", // Tampa Bay Rays
        "orioles": "UC2jqf9lgDjMUtTow1Q4IKzg", // Baltimore Orioles
        "bluejays": "UCVPkZh_H6m_stW8hq-2-yNw", // Toronto Blue Jays
        "whitesox": "UCve-Ci-M4CkBOmNi2LQdCRg", // Chicago White Sox
        "guardians": "UCpI50OSBxxalmRZRq4gtRDw", // Cleveland Guardians
        "tigers": "UCKKG465DFaJ3Yp-jQHA3jhw", // Detroit Tigers
        "royals": "UCvA2SgPVi3Hw6n_WER0VrcQ", // Kansas City Royals
        "twins": "UCkXEh3jSl4oB1mQqjIePfTg", // Minnesota Twins
        "astros": "UC3RPfeyaEIPosC4eIcNr4Gw", // Houston Astros
        "angels": "UCS7H_WWPj5_qfD-zoUzuX2A", // Los Angeles Angels
        "athletics": "UCeiRABiGBQTzpuEYohN_I1Q", // Athletics
        "mariners": "UCWWLs-O8JGYYcNea7AgumAA", // Seattle Mariners
        "rangers": "UCZjXWMvOrhc91chSDPDUspA", // Texas Rangers
        "braves": "UCNWnkblY5_kmf4OQ9l0LgnA", // Atlanta Braves
        "marlins": "UC1Gh_pQ7l41tyBn2HeJ1k-A", // Miami Marlins
        "phillies": "UCWkTX0S0Ii5pT2aRVz7Zctw", // Philadelphia Phillies
        "nationals": "UCUnB3WNX238eraj5IK3fFEw", // Washington Nationals
        "cubs": "UCnU7B7B0U0t2vs-2HMLjgvg", // Chicago Cubs
        "reds": "UCENXPJrzbHXudxhURfk5NCg", // Cincinnati Reds
        "brewers": "UCybiT6P8jSv7gIxC4cHXl2Q", // Milwaukee Brewers
        "pirates": "UCmBaK2wdmP1LZ9gLkkHiM4Q", // Pittsburgh Pirates
        "cardinals": "UCwaMqLYzbyp2IbFgcF_s5Og", // St. Louis Cardinals
        "diamondbacks": "UCxeK534L7DDIwPFv_o9CZjw", // Arizona Diamondbacks
        "rockies": "UCBci3py0IfkjkjPKDE-B6Bw", // Colorado Rockies
        "dodgers": "UC05cNJvMKzDLRPo59X2Xx7g", // Los Angeles Dodgers
        "padres": "UCdhukF6o5_ENjbf_9oNGXNQ", // San Diego Padres
        "giants": "UCpXMHgjrpnynDSV5mXpqImw", // San Francisco Giants
    ]
}
