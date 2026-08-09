#!/usr/bin/env python3
"""Print the real milestones in data/seasons.json so story copy can be fact-checked."""
import json, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHECKPOINT = 108
BEATS = {"2023":[13,35,103,108], "2024":[46,96,108,135],
         "2025":[63,98,108,140], "2026":[40,72,100,108,113]}

def streaks(seq, ch):
    best = end = cur = 0
    for i, c in enumerate(seq, 1):
        cur = cur + 1 if c == ch else 0
        if cur > best: best, end = cur, i
    return best, end

data = json.loads((ROOT / "data/seasons.json").read_text())
for year in sorted(data):
    s = data[year]; diff, seq = s["diff"], s["seq"]
    def rec(g):
        w = (g + diff[g-1]) // 2
        return f"{w}-{g-w}"
    peak = max(diff); valley = min(diff)
    wl, wg = streaks(seq, "W"); ll, lg = streaks(seq, "L")
    print(f"\n=== {year} ===")
    print(f"  final          {s['record']}  ({s['end_game']} games"
          f"{', in progress' if s['in_progress'] else ''})")
    print(f"  at game {CHECKPOINT}    {s.get('checkpoint_record')}")
    print(f"  peak           {peak:+d} at game {diff.index(peak)+1}")
    print(f"  valley         {valley:+d} at game {diff.index(valley)+1}")
    print(f"  longest W run  {wl} games, ending game {wg}")
    print(f"  longest L run  {ll} games, ending game {lg}")
    print("  at beat games:")
    for g in BEATS.get(year, []):
        print(f"    g{g:<4} {rec(g):>7}  ({diff[g-1]:+d})" if g <= len(diff)
              else f"    g{g:<4} — season only has {len(diff)} games")
print()
