#!/usr/bin/env python3
"""Validate the project atlas graph: a consistent tree, honest sizes and real connections."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_atlas  # noqa: E402


def main() -> None:
    graph = build_atlas.build_graph()
    nodes = {node["id"]: node for node in graph["nodes"]}
    assert len(nodes) == len(graph["nodes"]), "duplicate node ids"

    for node in nodes.values():
        for child in node["children"]:
            assert nodes[child]["parent"] == node["id"], f"{child} is not parented by {node['id']}"
        if node.get("parent"):
            assert node["id"] in nodes[node["parent"]]["children"], f"{node['id']} missing from its parent"

    systems = [nodes[key] for key in graph["systems"]]
    tracked = [f for f in build_atlas.git("ls-files", "-z").split("\0")
               if f and f not in build_atlas.EXCLUDED and (build_atlas.ROOT / f).is_file()]
    assert sum(s["files"] for s in systems) == len(tracked), "every tracked file is placed exactly once"
    for node in nodes.values():
        if node["children"] and node["sys"] != "external":
            assert node["lines"] == sum(nodes[c]["lines"] for c in node["children"]), f"{node['id']} lines"
            assert node["bytes"] == sum(nodes[c]["bytes"] for c in node["children"]), f"{node['id']} bytes"
    assert nodes["data"]["lines"] == 0, "generated data is sized by bytes, never as code lines"

    edges = {(e["s"], e["t"], e["type"]) for e in graph["edges"]}
    for s, t, _ in edges:
        assert s in nodes and t in nodes, f"dangling edge {s} -> {t}"
    ios = "f:" + build_atlas.IOS
    for expected in [
        ("f:scripts/generate_team_registry.py", ios + "HubTeam.swift", "generates"),
        ("f:scripts/generate_team_registry.py", "f:netlify/functions/team-registry.mjs", "generates"),
        (ios + "ScheduleStore.swift", ios + "APIClient.swift", "uses"),
        (ios + "StandingsStore.swift", "f:netlify/functions/mlb-data.mjs", "calls"),
        ("f:scripts/fetch_seasons.py", "f:data/seasons.json", "writes"),
        ("f:.github/workflows/refresh-data.yml", "f:scripts/fetch_seasons.py", "runs"),
        ("f:stories/four-roads/story.js", "f:src/chart.js", "uses"),
        ("f:netlify/functions/app-data.mjs", "data", "serves"),
    ]:
        assert expected in edges, f"missing connection {expected}"
    for node in nodes.values():
        if node.get("path", "").startswith(".github/workflows/"):
            assert any(s == node["id"] and kind == "runs" for s, _, kind in edges), f"{node['id']} runs nothing"

    page = build_atlas.render(graph)
    template = build_atlas.TEMPLATE.read_text(encoding="utf-8")
    assert page.count("</script>") == template.count("</script>"), "graph JSON must not close its script tag"
    print(f"atlas ok: {len(nodes)} parts, {len(edges)} connections")


if __name__ == "__main__":
    main()
