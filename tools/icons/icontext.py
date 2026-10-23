"""Parser and PNG/ICO writers for the Room for Trouble icon text format.

Python 3 standard library only. The format is documented at the top of
data/art/icons/palette.txt and mirrored by src/ui/icons.gd; keep the two
parsers in step.
"""

from __future__ import annotations

import os
import re
import struct
import zlib
from dataclasses import dataclass, field

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ICON_DIR = os.path.join(ROOT, "data", "art", "icons")
PALETTE_FILE = "palette.txt"

_HEX = re.compile(r"^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$")

RGBA = tuple[int, int, int, int]
CLEAR: RGBA = (0, 0, 0, 0)


def parse_colour(token: str) -> RGBA | None:
    """'#RRGGBB', '#RRGGBBAA' or 'transparent' -> RGBA tuple; None if invalid."""
    if token == "transparent":
        return CLEAR
    if not _HEX.match(token):
        return None
    h = token[1:]
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    a = int(h[6:8], 16) if len(h) == 8 else 255
    return (r, g, b, a)


def hex_of(c: RGBA) -> str:
    return "#%02X%02X%02X" % c[:3]


@dataclass
class Icon:
    name: str
    w: int
    h: int
    file: str
    line: int
    keys: dict[str, RGBA] = field(default_factory=dict)
    rows: list[str] = field(default_factory=list)


@dataclass
class Library:
    palette: dict[str, RGBA] = field(default_factory=dict)
    variants: dict[str, dict[str, RGBA]] = field(default_factory=dict)
    icons: dict[str, Icon] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)

    # ------------------------------------------------------------ rendering
    def colour_table(self, icon: Icon, variant: str = "default") -> dict[str, RGBA]:
        remap = self.variants.get(variant, {})
        table: dict[str, RGBA] = {".": CLEAR}
        for src in (self.palette, icon.keys):
            for k, c in src.items():
                if c[3] == 0:
                    table[k] = CLEAR
                else:
                    m = remap.get(hex_of(c))
                    table[k] = (m[0], m[1], m[2], c[3]) if m else c
        return table

    def pixels(self, name: str, variant: str = "default") -> list[list[RGBA]]:
        icon = self.icons[name]
        table = self.colour_table(icon, variant)
        return [[table.get(ch, (255, 0, 255, 255)) for ch in row] for row in icon.rows]

    def by_file(self) -> dict[str, list[str]]:
        out: dict[str, list[str]] = {}
        for n, ic in self.icons.items():
            out.setdefault(ic.file, []).append(n)
        return out


def _source_files(icon_dir: str) -> list[str]:
    files = sorted(f for f in os.listdir(icon_dir) if f.endswith(".txt"))
    if PALETTE_FILE in files:
        files.remove(PALETTE_FILE)
        files.insert(0, PALETTE_FILE)
    return files


def load(icon_dir: str = ICON_DIR) -> Library:
    lib = Library(variants={"default": {}})
    for fname in _source_files(icon_dir):
        _parse(lib, fname, open(os.path.join(icon_dir, fname), encoding="utf-8").read())
    # Key validation happens after every file is read (palette may come later).
    for ic in lib.icons.values():
        known = set(lib.palette) | set(ic.keys) | {"."}
        bad = sorted({ch for row in ic.rows for ch in row} - known)
        if bad:
            lib.errors.append(f"{ic.file}:{ic.line}: {ic.name}: unknown keys {''.join(bad)!r}")
    return lib


def _parse(lib: Library, fname: str, text: str) -> None:
    mode = ""
    icon: Icon | None = None
    vmap: dict[str, RGBA] = {}
    for ln, raw in enumerate(text.splitlines(), 1):
        line = raw.replace("\t", " ").strip()
        if not line or line == "#" or line.startswith("# "):
            continue
        toks = line.split()
        where = f"{fname}:{ln}"
        if mode == "":
            if toks[0] == "palette":
                mode = "palette"
            elif toks[0] == "variant" and len(toks) >= 2:
                mode = "variant"
                vmap = lib.variants.setdefault(toks[1], {})
            elif toks[0] == "icon" and len(toks) >= 3:
                size = toks[2].lower().split("x")
                try:
                    w = int(size[0])
                    h = int(size[1]) if len(size) > 1 else w
                except ValueError:
                    lib.errors.append(f"{where}: bad size {toks[2]!r}")
                    w = h = 0
                icon = Icon(toks[1], w, h, fname, ln)
                mode = "icon"
            else:
                lib.errors.append(f"{where}: unexpected line {line[:40]!r}")
            continue
        if toks[0] == "end" and len(toks) == 1:
            if mode == "icon" and icon is not None:
                _finish_icon(lib, icon)
            mode, icon = "", None
            continue
        if mode == "palette":
            c = parse_colour(toks[1]) if len(toks) >= 2 else None
            if len(toks[0]) != 1 or c is None:
                lib.errors.append(f"{where}: bad palette entry {line[:40]!r}")
            else:
                lib.palette[toks[0]] = c
        elif mode == "variant":
            a = parse_colour(toks[0])
            b = parse_colour(toks[1]) if len(toks) >= 2 else None
            if a is None or b is None:
                lib.errors.append(f"{where}: bad variant entry {line[:40]!r}")
            else:
                vmap[hex_of(a)] = b
        elif mode == "icon" and icon is not None:
            if (not icon.rows and len(toks) >= 2 and len(toks[0]) == 1
                    and (toks[1].startswith("#") or toks[1] == "transparent")):
                c = parse_colour(toks[1])
                if c is None:
                    lib.errors.append(f"{where}: bad colour {toks[1]!r}")
                else:
                    icon.keys[toks[0]] = c
            else:
                icon.rows.append(line)
    if mode != "":
        lib.errors.append(f"{fname}: missing 'end' for final {mode} block")


def _finish_icon(lib: Library, icon: Icon) -> None:
    where = f"{icon.file}:{icon.line}"
    ok = icon.w > 0 and len(icon.rows) == icon.h
    if not ok:
        lib.errors.append(f"{where}: {icon.name}: expected {icon.h} rows, found {len(icon.rows)}")
    for i, row in enumerate(icon.rows):
        if len(row) != icon.w:
            lib.errors.append(f"{where}: {icon.name}: row {i + 1} has {len(row)} columns, expected {icon.w}")
            ok = False
    if icon.name in lib.icons:
        lib.errors.append(f"{where}: duplicate icon {icon.name} (first in {lib.icons[icon.name].file})")
        return
    if ok:
        lib.icons[icon.name] = icon


# ---------------------------------------------------------------- image output
class Canvas:
    """Simple RGBA canvas with alpha-over blitting."""

    def __init__(self, w: int, h: int, fill: RGBA = CLEAR):
        self.w, self.h = w, h
        self.px = bytearray(bytes(fill) * (w * h))

    def set(self, x: int, y: int, c: RGBA) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            i = (y * self.w + x) * 4
            a = c[3]
            if a == 255:
                self.px[i:i + 4] = bytes(c)
            elif a > 0:
                d = self.px[i:i + 4]
                inv = 255 - a
                self.px[i:i + 4] = bytes((
                    (c[0] * a + d[0] * inv) // 255,
                    (c[1] * a + d[1] * inv) // 255,
                    (c[2] * a + d[2] * inv) // 255,
                    min(255, a + d[3] * inv // 255),
                ))

    def rect(self, x: int, y: int, w: int, h: int, c: RGBA) -> None:
        for yy in range(max(0, y), min(self.h, y + h)):
            row = bytes(c) * max(0, min(self.w, x + w) - max(0, x))
            i = (yy * self.w + max(0, x)) * 4
            self.px[i:i + len(row)] = row

    def blit(self, pixels: list[list[RGBA]], x: int, y: int, scale: int = 1) -> None:
        for py, row in enumerate(pixels):
            for px_, c in enumerate(row):
                if c[3] == 0:
                    continue
                for sy in range(scale):
                    for sx in range(scale):
                        self.set(x + px_ * scale + sx, y + py * scale + sy, c)

    def png(self) -> bytes:
        return png_bytes(self.w, self.h, bytes(self.px))

    def save(self, path: str) -> None:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(self.png())


def png_bytes(w: int, h: int, rgba: bytes) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    stride = w * 4
    raw = b"".join(b"\x00" + rgba[y * stride:(y + 1) * stride] for y in range(h))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def scaled(pixels: list[list[RGBA]], scale: int) -> list[list[RGBA]]:
    return [[c for c in row for _ in range(scale)] for row in pixels for _ in range(scale)]


def flat(pixels: list[list[RGBA]]) -> bytes:
    return b"".join(bytes(c) for row in pixels for c in row)


def ico_bytes(images: list[list[list[RGBA]]], png_min: int = 256) -> bytes:
    """Multi-size .ico. Sizes >= png_min are PNG-compressed, smaller sizes are
    32-bit BMP DIBs with an AND mask (widest compatibility)."""
    blobs: list[tuple[int, int, bytes]] = []
    for pix in images:
        h, w = len(pix), len(pix[0])
        if w >= png_min:
            blobs.append((w, h, png_bytes(w, h, flat(pix))))
            continue
        xor = bytearray()
        for row in reversed(pix):
            for r, g, b, a in row:
                xor += bytes((b, g, r, a))
        mask_stride = ((w + 31) // 32) * 4
        mask = bytearray()
        for row in reversed(pix):
            bits = bytearray(mask_stride)
            for x, c in enumerate(row):
                if c[3] == 0:
                    bits[x // 8] |= 0x80 >> (x % 8)
            mask += bits
        header = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0, len(xor) + len(mask), 0, 0, 0, 0)
        blobs.append((w, h, header + bytes(xor) + bytes(mask)))
    out = struct.pack("<HHH", 0, 1, len(blobs))
    offset = 6 + 16 * len(blobs)
    for w, h, data in blobs:
        out += struct.pack("<BBBBHHII", w % 256, h % 256, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    return out + b"".join(d for _, _, d in blobs)
