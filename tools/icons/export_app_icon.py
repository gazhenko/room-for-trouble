#!/usr/bin/env python3
"""Export the application icon from the text sources.

    python3 tools/icons/export_app_icon.py

Reads `app_icon` (32x32) and `app_icon_16` (16x16) from data/art/icons/ and
writes, with nearest-neighbour integer scaling only:
    assets/export/icons/app_icon.png   256x256  (app_icon x8)
    assets/export/icons/app_icon.ico   16 (app_icon_16 x1), 32 (app_icon x1),
                                       48 (app_icon_16 x3), 256 (app_icon x8, PNG)
Python 3 standard library only.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import icontext as it  # noqa: E402

OUT = os.path.join(it.ROOT, "assets", "export", "icons")


def main() -> int:
    lib = it.load()
    for e in lib.errors:
        print("ERROR", e)
    if "app_icon" not in lib.icons:
        print("app_icon block missing")
        return 1
    big = lib.pixels("app_icon")
    small = lib.pixels("app_icon_16") if "app_icon_16" in lib.icons else None
    if len(big) != 32 or len(big[0]) != 32:
        print("app_icon must be 32x32")
        return 1
    os.makedirs(OUT, exist_ok=True)
    p256 = it.scaled(big, 8)
    with open(os.path.join(OUT, "app_icon.png"), "wb") as f:
        f.write(it.png_bytes(256, 256, it.flat(p256)))
    s16 = small if small else [row[::2] for row in big[::2]]
    images = [s16, big, it.scaled(s16, 3), p256]
    with open(os.path.join(OUT, "app_icon.ico"), "wb") as f:
        f.write(it.ico_bytes(images))
    print("wrote assets/export/icons/app_icon.png (256x256) and app_icon.ico (16/32/48/256)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
