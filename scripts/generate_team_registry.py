#!/usr/bin/env python3
"""Generate native and Netlify registry views from config/mlb-teams.json."""

from __future__ import annotations

import argparse
import colorsys
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "config" / "mlb-teams.json"
SWIFT_OUTPUT = ROOT / "ios" / "Hub Ball" / "Hub Ball" / "HubTeam.swift"
JAVASCRIPT_OUTPUT = ROOT / "netlify" / "functions" / "team-registry.mjs"

TEAM_LINE_OVERRIDES = {
    # Precomputed Boston red preserves the primary hue with clearer saturation.
    "boston": "#D83C45",
    "newYork": "#E8E4DA",
    "tampaBay": "#8FBCE6",
    "chicagoWhiteSox": "#C4CED4",
    "detroit": "#FA4616",
    "kansasCity": "#2F65BD",
    "houston": "#EB6E1F",
    "athletics": "#0F7A4C",
    "seattle": "#009B8E",
    "miami": "#00A3E0",
    "toronto": "#2C62B5",
    "texas": "#2E5CB8",
    "milwaukee": "#8FA8C4",
    "pittsburgh": "#B7B2A8",
    "colorado": "#8B6DB8",
    "arizona": "#30CED8",
    "losAngelesDodgers": "#1F4E9C",
    "sanDiego": "#A47552",
}


def rgb(hex_color: str) -> tuple[float, float, float]:
    value = hex_color.removeprefix("#")
    return tuple(int(value[index:index + 2], 16) / 255 for index in (0, 2, 4))


def hex_color(color: tuple[float, float, float]) -> str:
    channels = (round(max(0, min(1, channel)) * 255) for channel in color)
    return "#" + "".join(f"{channel:02X}" for channel in channels)


def relative_luminance(color: tuple[float, float, float]) -> float:
    def linear(channel: float) -> float:
        return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4

    red, green, blue = map(linear, color)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def oklab(color: tuple[float, float, float]) -> tuple[float, float, float]:
    def linear(channel: float) -> float:
        return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4

    red, green, blue = map(linear, color)
    l = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
    m = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
    s = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue
    l_, m_, s_ = (
        math.copysign(abs(channel) ** (1 / 3), channel)
        for channel in (l, m, s)
    )
    return (
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    )


def oklch_color(lightness: float, chroma: float, hue: float) -> tuple[float, float, float]:
    a = chroma * math.cos(hue)
    b = chroma * math.sin(hue)
    l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
    m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
    s_ = lightness - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    linear_rgb = (
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    )

    def gamma(channel: float) -> float:
        return 12.92 * channel if channel <= 0.0031308 else 1.055 * channel ** (1 / 2.4) - 0.055

    return tuple(gamma(channel) for channel in linear_rgb)


def with_luminance(color: tuple[float, float, float], target: float) -> tuple[float, float, float]:
    hue, lightness, saturation = colorsys.rgb_to_hls(*color)
    low, high = 0.0, 1.0
    for _ in range(40):
        lightness = (low + high) / 2
        candidate = colorsys.hls_to_rgb(hue, lightness, saturation)
        if relative_luminance(candidate) < target:
            low = lightness
        else:
            high = lightness
    return colorsys.hls_to_rgb(hue, (low + high) / 2, saturation)


def team_tint(primary: str, swift_case: str) -> str:
    if swift_case == "newYork":
        return "#141F30"
    source = oklab(rgb(primary))
    source_chroma = math.hypot(source[1], source[2])
    if source_chroma < 0.03:
        fallback = TEAM_LINE_OVERRIDES.get(swift_case)
        if fallback is None:
            return "#14293D"
        source = oklab(rgb(fallback))
        source_chroma = math.hypot(source[1], source[2])
        if source_chroma < 0.03:
            return "#14293D"
    hue = math.atan2(source[2], source[1])
    # Shared revision-1 calibration: quieter chrome at unchanged lightness.
    return hex_color(oklch_color(0.22, 0.015, hue))


def team_line(primary: str, swift_case: str, tint: str) -> str:
    selected = rgb(TEAM_LINE_OVERRIDES.get(swift_case, primary))
    # Leave a small margin so conversion to 8-bit hex cannot round a nominal
    # 3:1 result below the contrast floor.
    minimum_luminance = max(0.18, 3.05 * (relative_luminance(rgb(tint)) + 0.05) - 0.05)
    if relative_luminance(selected) < minimum_luminance:
        selected = with_luminance(selected, minimum_luminance)
    elif swift_case not in TEAM_LINE_OVERRIDES:
        selected = with_luminance(selected, 0.25)
    return hex_color(selected)


def quoted(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def swift_bool(value: bool) -> str:
    return "true" if value else "false"


def swift_source(source: dict[str, str]) -> str:
    return f".init(key: {quoted(source['key'])}, name: {quoted(source['name'])})"


def swift_definition(team: dict[str, Any]) -> str:
    colors = team["colors"]
    tint = team_tint(colors["primary"], team["swift_case"])
    features = team["features"]
    sources = ", ".join(swift_source(source) for source in team["news_sources"])
    feature_values = ", ".join(
        f"{key}: {swift_bool(features[key])}"
        for key in (
            "native_picker", "home", "recent_game", "schedule", "standings",
            "pitching", "leaders", "news", "x_posts", "players", "stories",
        )
    )
    color_values = ", ".join(
        f"{key}: {quoted(colors.get(key, fallback))}"
        for key, fallback in (
            ("primary", colors["primary"]),
            ("secondary", colors["secondary"]),
            ("background", colors["background"]),
            ("ink", colors["ink"]),
            ("border", colors["border"]),
            ("positive", colors["positive"]),
            ("banner", colors["primary"]),
            ("accent_dark", colors["secondary"]),
            ("navigation", colors["secondary"]),
        )
    )
    color_values += (
        f", team_tint: {quoted(tint)}"
        f", team_line: {quoted(team_line(colors['primary'], team['swift_case'], tint))}"
    )
    return f"""        .{team['swift_case']}: .init(
            mlbID: {team['mlb_id']}, fullName: {quoted(team['full_name'])},
            cityName: {quoted(team['city_name'])}, shortName: {quoted(team['short_name'])},
            abbreviation: {quoted(team['abbreviation'])}, cityAbbreviation: {quoted(team['city_abbreviation'])},
            apiKey: {quoted(team['api_key'])}, dataDirectory: {quoted(team['data_directory'])},
            xHandle: {quoted(team['x_handle'])},
            usesLegacyRootData: {swift_bool(team['legacy_root_data'])}, league: {quoted(team['league'])},
            division: {quoted(team['division'])}, fangraphsID: {team['fangraphs_id']},
            baseballReferenceID: {quoted(team['baseball_reference_id'])},
            colors: .init({color_values}),
            newsSources: [{sources}],
            features: .init({feature_values})
        )"""


def render_swift(teams: list[dict[str, Any]]) -> str:
    cases = "\n".join(
        f"    case {team['swift_case']} = {quoted(team['id'])}" for team in teams
    )
    definitions = ",\n".join(swift_definition(team) for team in teams)
    return f"""// Generated by scripts/generate_team_registry.py. Do not edit by hand.
import Foundation

struct NewsSource: Hashable, Identifiable, Sendable {{
    let key: String
    let name: String

    var id: String {{ key }}
    var shortName: String {{ name }}
    var fileName: String {{ key }}
}}

struct HubTeamColors: Sendable {{
    let primary: String
    let secondary: String
    let background: String
    let ink: String
    let border: String
    let positive: String
    let banner: String
    let accentDark: String
    let navigation: String
    let teamTint: String
    let teamLine: String

    init(
        primary: String, secondary: String, background: String, ink: String,
        border: String, positive: String, banner: String, accent_dark: String,
        navigation: String, team_tint: String, team_line: String
    ) {{
        self.primary = primary
        self.secondary = secondary
        self.background = background
        self.ink = ink
        self.border = border
        self.positive = positive
        self.banner = banner
        self.accentDark = accent_dark
        self.navigation = navigation
        self.teamTint = team_tint
        self.teamLine = team_line
    }}
}}

struct HubTeamFeatures: Sendable {{
    let nativePicker: Bool
    let home: Bool
    let recentGame: Bool
    let schedule: Bool
    let standings: Bool
    let pitching: Bool
    let leaders: Bool
    let news: Bool
    let xPosts: Bool
    let players: Bool
    let stories: Bool

    init(
        native_picker: Bool, home: Bool, recent_game: Bool, schedule: Bool,
        standings: Bool, pitching: Bool, leaders: Bool, news: Bool,
        x_posts: Bool, players: Bool, stories: Bool
    ) {{
        self.nativePicker = native_picker
        self.home = home
        self.recentGame = recent_game
        self.schedule = schedule
        self.standings = standings
        self.pitching = pitching
        self.leaders = leaders
        self.news = news
        self.xPosts = x_posts
        self.players = players
        self.stories = stories
    }}
}}

struct HubTeamDefinition: Sendable {{
    let mlbID: Int
    let fullName: String
    let cityName: String
    let shortName: String
    let abbreviation: String
    let cityAbbreviation: String
    let apiKey: String
    let dataDirectory: String
    let xHandle: String
    let usesLegacyRootData: Bool
    let league: String
    let division: String
    let fangraphsID: Int
    let baseballReferenceID: String
    let colors: HubTeamColors
    let newsSources: [NewsSource]
    let features: HubTeamFeatures
}}

enum HubTeam: String, CaseIterable, Identifiable, Sendable {{
{cases}

    nonisolated private static let registry: [HubTeam: HubTeamDefinition] = [
{definitions}
    ]

    nonisolated var id: String {{ rawValue }}
    nonisolated var definition: HubTeamDefinition {{ Self.registry[self]! }}
    nonisolated var mlbID: Int {{ definition.mlbID }}
    nonisolated var fullName: String {{ definition.fullName }}
    nonisolated var cityName: String {{ definition.cityName }}
    nonisolated var cityAbbreviation: String {{ definition.cityAbbreviation }}
    nonisolated var shortName: String {{ definition.shortName }}
    nonisolated var abbreviation: String {{ definition.abbreviation }}
    nonisolated var pickerTitle: String {{ definition.fullName }}
    nonisolated var apiKey: String {{ definition.apiKey }}
    nonisolated var dataDirectory: String {{ definition.dataDirectory }}
    nonisolated var xHandle: String {{ definition.xHandle }}
    nonisolated var dataPathComponent: String? {{
        definition.usesLegacyRootData ? nil : definition.dataDirectory
    }}
    nonisolated var colors: HubTeamColors {{ definition.colors }}
    nonisolated var newsSources: [NewsSource] {{ definition.newsSources }}
    nonisolated var features: HubTeamFeatures {{ definition.features }}
    nonisolated var supportsHome: Bool {{ features.home }}
    nonisolated var supportsPlayers: Bool {{ features.players }}
    nonisolated var hasPublishedStories: Bool {{ features.stories }}

    nonisolated static var availableTeams: [HubTeam] {{
        allCases
            .filter {{ $0.features.nativePicker }}
            .sorted {{ $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }}
    }}
}}

enum HubPreferences {{
    static let selectedTeamKey = "hubSelectedTeam"
    static let completedTeamOnboardingKey = "hubCompletedTeamOnboarding"
    static let pageOrderKey = "hubPageOrder"
}}
"""


def render_javascript(document: dict[str, Any]) -> str:
    body = json.dumps(document["teams"], indent=2, ensure_ascii=False)
    return f"""// Generated by scripts/generate_team_registry.py. Do not edit by hand.
export const MLB_TEAMS = Object.freeze({body});
export const TEAM_BY_API_KEY = new Map(MLB_TEAMS.map(team => [team.api_key, team]));
export const TEAM_BY_ID = new Map(MLB_TEAMS.map(team => [team.id, team]));
export const TEAM_BY_MLB_ID = new Map(MLB_TEAMS.map(team => [team.mlb_id, team]));
"""


def write_or_check(path: Path, content: str, check: bool) -> bool:
    if check:
        return path.exists() and path.read_text() == content
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    document = json.loads(SOURCE.read_text())
    outputs = {
        SWIFT_OUTPUT: render_swift(document["teams"]),
        JAVASCRIPT_OUTPUT: render_javascript(document),
    }
    stale = [path for path, content in outputs.items() if not write_or_check(path, content, args.check)]
    if stale:
        names = ", ".join(str(path.relative_to(ROOT)) for path in stale)
        raise SystemExit(f"Generated team registry files are stale: {names}")
    if not args.check:
        print("Generated " + ", ".join(str(path.relative_to(ROOT)) for path in outputs))


if __name__ == "__main__":
    main()
