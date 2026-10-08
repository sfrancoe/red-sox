#!/usr/bin/env python3
"""Validate an entire staged story release without network access."""
import argparse
from pathlib import Path
from story_content import validate_tree

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-root', type=Path, default=Path(__file__).resolve().parents[1] / 'data')
    args = parser.parse_args()
    catalog = validate_tree(args.data_root)
    print(f"Validated {len(catalog['stories'])} stories; catalog {catalog['revision']}")
