#!/usr/bin/env python3
"""Stage and apply pitching artifacts only against their original source versions."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

from refresh_pitching import ROOT, output_path, write_snapshot
from team_registry import all_teams

GUARDS = ('config/pitching-refresh.json', 'config/mlb-teams.json')


def digest(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def source_bytes(root: Path, path: str) -> bytes | None:
    result = subprocess.run(['git', 'show', f'HEAD:{path}'], cwd=root, capture_output=True)
    return result.stdout if result.returncode == 0 else None


def current_digest(path: Path) -> str | None:
    return digest(path.read_bytes()) if path.exists() else None


def stage(root: Path, artifact: Path) -> None:
    artifact.mkdir(parents=True, exist_ok=True)
    policy = json.loads((root / GUARDS[0]).read_text())
    guards = {path: digest((root / path).read_bytes()) for path in GUARDS}
    files = []
    for team in all_teams():
        path = output_path(team, root)
        relative = path.relative_to(root).as_posix()
        original = source_bytes(root, relative)
        payload = path.read_bytes()
        if original == payload:
            continue
        if json.loads(payload).get('season') != policy['season']:
            raise RuntimeError(f'Unexpected artifact season: {relative}')
        target = artifact / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
        files.append({'path': relative, 'source_sha256': digest(original) if original is not None else None,
                      'result_sha256': digest(payload)})
    (artifact / 'manifest.json').write_text(json.dumps(
        {'season': policy['season'], 'guards': guards, 'files': files}, indent=2) + '\n')


def apply(root: Path, artifact: Path) -> list[str]:
    """Reject changed policy; skip stale files while applying independent healthy files."""
    manifest = json.loads((artifact / 'manifest.json').read_text())
    accepted = artifact / 'accepted-paths'
    accepted.write_text('')
    errors = []
    if set(manifest['guards']) != set(GUARDS) or any(
        current_digest(root / path) != manifest['guards'][path] for path in GUARDS
    ):
        return ['Pitching policy or team registry changed during fetch; rejected all artifacts']
    policy = json.loads((root / GUARDS[0]).read_text())
    if manifest['season'] != policy['season'] or policy['projection_season'] != policy['season']:
        return ['Artifact season does not match the publication policy']
    allowed = {output_path(team, root).relative_to(root).as_posix() for team in all_teams()}
    pending = []
    for entry in manifest['files']:
        relative = entry['path']
        if relative not in allowed:
            errors.append(f'Unexpected pitching artifact path: {relative}')
            continue
        path = root / relative
        if current_digest(path) != entry['source_sha256']:
            errors.append(f'{relative} changed during fetch; kept newer main snapshot')
            continue
        payload = (artifact / relative).read_bytes()
        feed = json.loads(payload)
        if digest(payload) != entry['result_sha256'] or feed.get('season') != policy['season']:
            errors.append(f'Invalid digest or season for {relative}; kept main snapshot')
            continue
        pending.append((relative, feed))
    for relative, feed in pending:
        write_snapshot(root / relative, feed)
        with accepted.open('a') as handle:
            handle.write(relative + '\n')
    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('stage', 'apply'))
    parser.add_argument('artifact', type=Path)
    args = parser.parse_args()
    if args.mode == 'stage':
        stage(ROOT, args.artifact)
    else:
        errors = apply(ROOT, args.artifact)
        if errors:
            raise SystemExit('\n'.join(errors))


if __name__ == '__main__':
    main()
