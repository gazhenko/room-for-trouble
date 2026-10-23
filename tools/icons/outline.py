#!/usr/bin/env python3
"""Authoring aid: add the standard 1-px ink outline around drawn fills.

Draw an icon's fills only (keeping a 1-px transparent margin), then pipe the
rows through this filter, or rewrite one block of a source file in place:

    python3 tools/icons/outline.py < rows.txt
    python3 tools/icons/outline.py --mirror < left_half.txt     # mirror then outline
    python3 tools/icons/outline.py --block data/art/icons/items.txt item_towel

Every transparent '.' pixel that touches an opaque pixel on one of its four
sides becomes the outline key (default 'k'); diagonal-only contact is left
open, which keeps silhouettes round. --mirror copies the left half onto the
right (odd widths keep the centre column). --block applies to the rows of the
named icon, so only run it on a block that has no outline yet.
Python 3 standard library only.
"""

from __future__ import annotations

import argparse
import sys


def outline(rows: list[str], key: str = "k", diagonal: bool = False) -> list[str]:
    h, w = len(rows), max(len(r) for r in rows)
    grid = [list(r.ljust(w, ".")) for r in rows]
    out = [row[:] for row in grid]
    nb = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    if diagonal:
        nb += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    for y in range(h):
        for x in range(w):
            if grid[y][x] != ".":
                continue
            if any(0 <= x + dx < w and 0 <= y + dy < h and grid[y + dy][x + dx] != "." for dx, dy in nb):
                out[y][x] = key
    return ["".join(r) for r in out]


def mirror(rows: list[str], width: int) -> list[str]:
    half = (width + 1) // 2
    res = []
    for r in rows:
        left = r[:half].ljust(half, ".")
        right = left[: width // 2][::-1]
        res.append(left + right)
    return res


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--key", default="k")
    ap.add_argument("--diagonal", action="store_true", help="also outline diagonal contacts")
    ap.add_argument("--mirror", action="store_true", help="mirror left half before outlining")
    ap.add_argument("--width", type=int, default=0, help="canvas width for --mirror (default: 2x input)")
    ap.add_argument("--no-outline", action="store_true")
    ap.add_argument("--block", nargs=2, metavar=("FILE", "ICON"))
    a = ap.parse_args()

    def process(rows: list[str]) -> list[str]:
        if a.mirror:
            rows = mirror(rows, a.width or 2 * max(len(r) for r in rows))
        return rows if a.no_outline else outline(rows, a.key, a.diagonal)

    if a.block:
        path, name = a.block
        lines = open(path, encoding="utf-8").read().split("\n")
        start = next((i for i, l in enumerate(lines) if l.split()[:2] == ["icon", name]), None)
        if start is None:
            print(f"icon {name} not found in {path}", file=sys.stderr)
            return 1
        end = next(i for i in range(start, len(lines)) if lines[i].strip() == "end")
        idx = [i for i in range(start + 1, end)
               if lines[i].strip() and not lines[i].startswith("# ")
               and not (len(lines[i].split()) >= 2 and len(lines[i].split()[0]) == 1)]
        new = process([lines[i].strip() for i in idx])
        for i, r in zip(idx, new):
            lines[i] = r
        open(path, "w", encoding="utf-8").write("\n".join(lines))
        print("\n".join(new))
        return 0
    rows = [l.strip() for l in sys.stdin.read().splitlines() if l.strip()]
    print("\n".join(process(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
