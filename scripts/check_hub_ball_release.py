#!/usr/bin/env python3
"""Validate the canonical Hub Ball release source and detect newer worktrees."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "config" / "hub-ball-release.json"
PROJECT_FILE = ROOT / "ios" / "Hub Ball" / "Hub Ball.xcodeproj" / "project.pbxproj"
RELEASE_PATHS = (
    "config/hub-ball-release.json",
    "ios/Hub Ball",
    "scripts/check_hub_ball_release.py",
    "scripts/install_hub_ball.sh",
)


def git(*args: str, cwd: Path = ROOT) -> str:
    result = subprocess.run(
        ["git", *args], cwd=cwd, check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def setting(text: str, name: str) -> str:
    pattern = rf'^\s*{re.escape(name)}\s*=\s*"?([^;\"]+)"?;'
    values = sorted(set(re.findall(pattern, text, re.MULTILINE)))
    if len(values) != 1:
        raise ValueError(f"Expected one {name} value; found {values or 'none'}.")
    return values[0].strip()


def project_identity(project_file: Path) -> tuple[str, str, int]:
    text = project_file.read_text(encoding="utf-8")
    return (
        setting(text, "PRODUCT_BUNDLE_IDENTIFIER"),
        setting(text, "MARKETING_VERSION"),
        int(setting(text, "CURRENT_PROJECT_VERSION")),
    )


def worktrees() -> list[Path]:
    output = git("worktree", "list", "--porcelain")
    return [
        Path(line.removeprefix("worktree "))
        for line in output.splitlines()
        if line.startswith("worktree ")
    ]


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    branch = git("branch", "--show-current")
    if branch != manifest["canonical_branch"]:
        print(
            f"FAIL: Hub Ball releases must come from {manifest['canonical_branch']}; "
            f"current branch is {branch or 'detached'}.",
            file=sys.stderr,
        )
        return 1

    bundle_id, version, build = project_identity(PROJECT_FILE)
    expected = (manifest["bundle_id"], manifest["version"], int(manifest["build"]))
    if (bundle_id, version, build) != expected:
        print(
            f"FAIL: release manifest expects {expected[0]} {expected[1]} ({expected[2]}), "
            f"but Xcode contains {bundle_id} {version} ({build}).",
            file=sys.stderr,
        )
        return 1

    dirty = git("status", "--porcelain", "--", *RELEASE_PATHS)
    if dirty:
        print("FAIL: release-sensitive files are not committed:\n" + dirty, file=sys.stderr)
        return 1

    newer: list[str] = []
    found: list[tuple[int, Path]] = []
    relative_project = PROJECT_FILE.relative_to(ROOT)
    for tree in worktrees():
        candidate = tree / relative_project
        if not candidate.is_file():
            continue
        try:
            candidate_bundle, _, candidate_build = project_identity(candidate)
        except (OSError, ValueError):
            continue
        if candidate_bundle != bundle_id:
            continue
        found.append((candidate_build, tree))
        if candidate_build > build:
            newer.append(f"build {candidate_build}: {tree}")

    if newer:
        print(
            "FAIL: a newer Hub Ball build exists outside the canonical source:\n"
            + "\n".join(newer),
            file=sys.stderr,
        )
        return 1

    scanned = ", ".join(str(number) for number, _ in sorted(found, reverse=True))
    print(
        f"PASS: Hub Ball {version} ({build}) on {branch} is canonical; "
        f"scanned worktree builds: {scanned}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
