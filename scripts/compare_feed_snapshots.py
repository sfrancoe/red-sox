#!/usr/bin/env python3
"""Compare two directories of team feeds and report schema and value changes.

Used by the shadow-run check when a team moves from its own fetch scripts to
the shared registry fetchers: run the shared fetchers against live APIs, then
compare their output with the snapshot the old scripts last published.

Exit status is 1 only when a field present in the baseline is missing from the
new feed (a schema regression the app could notice). `--renamed old=new` marks a
field the app already reads under its new name, so the old name may disappear. Value changes are
reported for review, since live data moves between runs.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


IGNORED_KEYS = {"generated_at"}


def shape(value: Any, prefix: str = "") -> set[str]:
    """Every field path, with list items folded into one `[]` segment."""
    if isinstance(value, dict):
        return {
            path
            for key, child in value.items() if key not in IGNORED_KEYS
            for path in shape(child, f"{prefix}.{key}" if prefix else key) | {
                f"{prefix}.{key}" if prefix else key
            }
        }
    if isinstance(value, list):
        return {path for child in value for path in shape(child, f"{prefix}[]")}
    return set()


def flat(value: Any, prefix: str = "") -> dict[str, Any]:
    """Every scalar by its exact position, e.g. `away.batting[3].hits`."""
    if isinstance(value, dict):
        out: dict[str, Any] = {}
        for key, child in value.items():
            if key not in IGNORED_KEYS:
                out.update(flat(child, f"{prefix}.{key}" if prefix else key))
        return out
    if isinstance(value, list):
        out = {}
        for index, child in enumerate(value):
            out.update(flat(child, f"{prefix}[{index}]"))
        return out or {prefix: []}
    return {prefix: value}


def compare(baseline: Any, new: Any, renamed: dict[str, str] | None = None
            ) -> tuple[list[str], list[str], list[tuple[str, Any, Any]]]:
    old_shape, new_shape = shape(baseline), shape(new)
    for path in list(old_shape):
        leaf = path.rsplit(".", 1)[-1]
        if leaf in (renamed or {}):
            successor = path[: len(path) - len(leaf)] + renamed[leaf]
            if successor in new_shape:
                old_shape.discard(path)
    old_values, new_values = flat(baseline), flat(new)
    changed = [
        (path, old_values[path], new_values.get(path))
        for path in old_values
        if old_values[path] != new_values.get(path)
    ]
    return sorted(old_shape - new_shape), sorted(new_shape - old_shape), changed


def short(value: Any, limit: int = 90) -> str:
    text = json.dumps(value, ensure_ascii=False)
    return text if len(text) <= limit else text[: limit - 1] + "…"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("new", type=Path)
    parser.add_argument("files", nargs="+")
    parser.add_argument("--samples", type=int, default=6)
    parser.add_argument("--label", help="heading for the report (defaults to the new directory)")
    parser.add_argument("--renamed", action="append", default=[], metavar="OLD=NEW",
                        help="a field the app also reads under a new name")
    args = parser.parse_args()

    renamed = dict(item.split("=", 1) for item in args.renamed)
    regressions = 0
    print(f"### {args.label or args.new.name}\n")
    for name in args.files:
        old_path, new_path = args.baseline / name, args.new / name
        if not old_path.exists():
            print(f"- **{name}**: no baseline file\n")
            continue
        if not new_path.exists():
            print(f"- **{name}**: ❌ shared fetchers did not write this file\n")
            regressions += 1
            continue
        missing, added, changed = compare(json.loads(old_path.read_text()),
                                          json.loads(new_path.read_text()), renamed)
        regressions += len(missing)
        status = "❌" if missing else "✅"
        print(f"- **{name}** {status} — {len(missing)} missing fields, {len(added)} new fields, "
              f"{len(changed)} changed values")
        for path in missing:
            print(f"  - missing: `{path}`")
        for path in added[: args.samples]:
            print(f"  - new: `{path}`")
        if len(added) > args.samples:
            print(f"  - …and {len(added) - args.samples} more new fields")
        for path, old, new in changed[: args.samples]:
            print(f"  - changed `{path}`: {short(old)} → {short(new)}")
        if len(changed) > args.samples:
            print(f"  - …and {len(changed) - args.samples} more changed values")
        print()
    return 1 if regressions else 0


if __name__ == "__main__":
    sys.exit(main())
