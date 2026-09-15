#!/usr/bin/env python3
"""Focused invariants for the pure leaderboard ranking helpers."""
from fetch_league_leaders import innings_outs, rank


def row(name: str, value: float, identifier: int) -> dict:
    return {"name": name, "value": value, "player_id": identifier}


def main() -> None:
    tied = rank([row("B", 8, 2), row("A", 9, 1), row("C", 8, 3), row("D", 7, 4)], False)
    assert [item["rank"] for item in tied] == [1, 2, 2, 4]
    assert [item["name"] for item in tied] == ["A", "B", "C", "D"]
    low = rank([row("A", 1.1, 1), row("B", 0.9, 2)], True)
    assert [item["name"] for item in low] == ["B", "A"]
    assert innings_outs("40.0") == 120
    assert innings_outs("40.2") == 122
    assert innings_outs("40.3") is None
    print("league leaderboard tests passed")


if __name__ == "__main__":
    main()
