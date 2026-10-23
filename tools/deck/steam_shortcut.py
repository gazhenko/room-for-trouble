#!/usr/bin/env python3
"""Finds the Room for Trouble non-Steam shortcut and gives it library artwork.

Runs on the Deck (shipped in the game folder by tools/deck/serve.sh):
  steam_shortcut.py has            exit 0 if a shortcut already points at the game
  steam_shortcut.py art <dir>      copy <dir>/{capsule,wide,hero,logo}.png into Steam's grid
Steam reads shortcuts.vdf (binary VDF) itself; this only reads it, and the
artwork shows after Steam next starts (switching to Game Mode restarts it).
"""
import os
import shutil
import struct
import sys

MARK = "Games/RoomForTrouble/"
ART = {"capsule.png": "{}p.png", "wide.png": "{}.png", "hero.png": "{}_hero.png", "logo.png": "{}_logo.png"}


def parse(buf, i=0):
    d = {}
    while True:
        t = buf[i]
        i += 1
        if t == 0x08:
            return d, i
        j = buf.index(b"\0", i)
        key = buf[i:j].decode("utf-8", "replace").lower()
        i = j + 1
        if t == 0x00:
            d[key], i = parse(buf, i)
        elif t == 0x01:
            j = buf.index(b"\0", i)
            d[key] = buf[i:j].decode("utf-8", "replace")
            i = j + 1
        elif t == 0x02:
            d[key] = struct.unpack_from("<I", buf, i)[0]
            i += 4
        elif t == 0x07:
            d[key] = struct.unpack_from("<Q", buf, i)[0]
            i += 8
        else:
            raise ValueError("unknown VDF type %d at %d" % (t, i - 1))


def shortcuts():
    """Yields (grid dir, appid) for every Steam user with a shortcut to the game."""
    seen = set()
    for root in ("~/.local/share/Steam/userdata", "~/.steam/steam/userdata"):
        root = os.path.realpath(os.path.expanduser(root))
        if root in seen or not os.path.isdir(root):
            continue
        seen.add(root)
        for uid in os.listdir(root):
            vdf = os.path.join(root, uid, "config", "shortcuts.vdf")
            if not os.path.isfile(vdf):
                continue
            try:
                with open(vdf, "rb") as f:
                    data, _ = parse(f.read())
            except (ValueError, IndexError, struct.error):
                continue
            for sc in data.get("shortcuts", {}).values():
                if MARK in sc.get("exe", "") and "appid" in sc:
                    yield os.path.join(root, uid, "config", "grid"), sc["appid"]


def main(argv):
    found = list(shortcuts())
    if argv[1:2] == ["has"]:
        return 0 if found else 1
    if argv[1:2] == ["art"] and len(argv) > 2:
        for grid, appid in found:
            os.makedirs(grid, exist_ok=True)
            for src, pattern in ART.items():
                path = os.path.join(argv[2], src)
                if os.path.isfile(path):
                    shutil.copyfile(path, os.path.join(grid, pattern.format(appid)))
        return 0 if found else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
