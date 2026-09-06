# Open player facts and reuse policy

The native iPhone and iPad Players directory is deliberately photo-free and does not
include paid sports feeds. It presents a concise roster, basic biographical facts, and
completed-season career statistics with links back to the source records.

## Sources

`scripts/fetch_players.py` uses four open-data sources:

- **Wikidata** supplies structured birth date, birthplace, education, physical
  measurements, position, identifiers, and team membership. Wikidata publishes its
  structured data under CC0 1.0, so it may be reused commercially without requesting
  an individual license or paying a fee.
- **Wikipedia's Boston roster template and player infoboxes** supply the current
  roster, uniform numbers, broad position groups, roster status, and major-team
  history. Wikipedia is free for commercial reuse under CC BY-SA 4.0. The app provides
  attribution and source links; it copies no article prose or images.
- **Retrosheet** supplies game-level batting, pitching, and fielding logs through the
  completed 2025 season. Retrosheet expressly permits commercial products based on
  its data when its required credit is displayed prominently. The app includes that
  credit in the Players directory and each player source section.
- **The Chadwick Baseball Bureau Persons Register** maps Wikimedia/MLB identifiers to
  stable Retrosheet IDs. Its ODC Attribution 1.0 license permits commercial use with
  attribution.

This is open-licensed data, not license-free content in the literal sense: CC0 places
Wikidata data in the public domain, while Wikipedia's CC BY-SA license requires
attribution and share-alike treatment when protected content is reused. The generated
feed records the licenses, required attribution, statistics cutoff, and exact
roster-template revision.

## Refresh and verification

Run:

```bash
python3 scripts/fetch_players.py
python3 scripts/test_open_players.py
python3 scripts/test_players.py
```

The refresh fails loudly if the roster cannot be parsed, two players collide on an
identity key, or the response shape changes. Missing individual facts remain blank;
the script does not infer or invent them. Retrosheet career logs are cached until its
completed-season release changes, avoiding unnecessary repeat downloads. Tests reject
player photos, MLB image/API hosts, paid-provider references, missing team histories,
and missing source links. They also require both batting and pitching coverage and
verify the career-stat cutoff.

## Scope

The page includes name, number, position, roster status, age, birth date and place,
height/weight when available, education when available, major teams played for, and
standard career batting or pitching totals through 2025. Players absent from the 2025
release—normally 2026 debuts or players awaiting an MLB appearance—receive an explicit
unavailable state. It intentionally excludes headshots, article biography text, WAR,
OPS+, awards, contract values, and private/personal details.

Open-data sourcing does not grant permission to use club logos, uniform designs, or
other league and team trademarks. Those product-branding questions remain separate.
