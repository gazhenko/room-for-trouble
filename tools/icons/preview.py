#!/usr/bin/env python3
"""Render labelled contact sheets of the icon set and lint it.

Python 3 standard library only.

    python3 tools/icons/preview.py              # every sheet + report
    python3 tools/icons/preview.py --only systems,items --no-variants
    python3 tools/icons/preview.py --names sys_warm,sys_cold --out build/shots/x.png

Outputs (build/shots/):
    icons_sheet.png                 all icons, default palette, 4x
    icons_sheet_<variant>.png       all icons per colour variant
    icons_<file>.png                one sheet per source file
    icons_cvd_check.png             semantic/family sets as seen with
                                    simulated colour-vision deficiencies,
                                    default palette vs. the matching variant
Each cell shows the icon at 4x on a light checker, plus 2x and 1x on ink and
1x on cream, so 1x readability and outline contrast can be judged directly.
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import icontext as it  # noqa: E402

OUT_DIR = os.path.join(it.ROOT, "build", "shots")

REQUIRED = """
fam_slime fam_yeti fam_dragon fam_ghost fam_moonwolf fam_sprout
staff_pip staff_pebble staff_moss staff_button npc_nana npc_gus npc_dot
guest_mallow guest_flurry guest_cinder guest_whisp guest_luna guest_fern
item_ticket item_move_ticket item_linen_clean item_linen_dirty item_towel item_snack
gift_slime gift_yeti gift_dragon gift_ghost gift_moonwolf gift_sprout
item_curtain tool_mop tool_can tool_breezer item_trunk item_parcel
sys_warm sys_cold sys_cozy sys_noise sys_note_small sys_quiet sys_water sys_humid
sys_clean sys_mess sys_bed sys_bed_dirty sys_room_cap sys_gate sys_gate_closed
sys_thermo sys_pump sys_frost sys_steam sys_puddle sys_bell sys_move sys_inspect
sys_ping sys_wave sys_heart sys_clock sys_sun_moon sys_lift sys_shutter sys_trip
sys_mirror sys_star sys_star_empty sys_ribbon sys_stamp sys_postcard sys_assist
sys_connection_good sys_connection_poor sys_disconnected sys_controller sys_keyboard
sys_check sys_soft_no sys_arrow sys_handoff sys_need_room sys_wait sys_help
sys_festival sys_moon sys_music sys_lock sys_team sys_coach sys_skip
ping_help ping_bringing ping_ready ping_thanks
diff_cozy diff_family diff_busy
ch1 ch2 ch3 ch4 ch5 ch6
badge_first_hello badge_fresh_fold badge_two_temperatures badge_quiet_chorus
badge_little_bloom badge_other_end badge_everyone_fits badge_helping_hands
ui_cursor ui_check_box ui_check_box_on ui_arrow_left ui_arrow_right ui_arrow_up
ui_arrow_down ui_close ui_settings ui_scrapbook ui_credits ui_play ui_online
ui_couch ui_solo ui_playground ui_hub ui_quick ui_photo
panel_cream panel_ink panel_card button_idle button_focus bubble
app_icon
""".split()

SIZES = {n: 24 for n in "staff_pip staff_pebble staff_moss staff_button npc_nana npc_gus npc_dot "
         "guest_mallow guest_flurry guest_cinder guest_whisp guest_luna guest_fern "
         "ch1 ch2 ch3 ch4 ch5 ch6 panel_cream panel_ink panel_card button_idle button_focus bubble".split()}
SIZES["app_icon"] = 32

LINT_EXEMPT = ("panel_", "button_", "bubble")
# Must match Icons.NINE_SLICE in src/ui/icons.gd.
NINE_SLICE = {"panel_cream": 8, "panel_ink": 8, "panel_card": 8, "button_idle": 8, "button_focus": 8, "bubble": 8}

# ---------------------------------------------------------------- tiny font
_GLYPHS = {
    "a": (".#.", "#.#", "###", "#.#", "#.#"), "b": ("##.", "#.#", "##.", "#.#", "##."),
    "c": (".##", "#..", "#..", "#..", ".##"), "d": ("##.", "#.#", "#.#", "#.#", "##."),
    "e": ("###", "#..", "##.", "#..", "###"), "f": ("###", "#..", "##.", "#..", "#.."),
    "g": (".##", "#..", "#.#", "#.#", ".##"), "h": ("#.#", "#.#", "###", "#.#", "#.#"),
    "i": ("###", ".#.", ".#.", ".#.", "###"), "j": ("..#", "..#", "..#", "#.#", ".#."),
    "k": ("#.#", "#.#", "##.", "#.#", "#.#"), "l": ("#..", "#..", "#..", "#..", "###"),
    "m": ("#.#", "###", "###", "#.#", "#.#"), "n": ("##.", "#.#", "#.#", "#.#", "#.#"),
    "o": (".#.", "#.#", "#.#", "#.#", ".#."), "p": ("##.", "#.#", "##.", "#..", "#.."),
    "q": (".#.", "#.#", "#.#", "##.", ".##"), "r": ("##.", "#.#", "##.", "#.#", "#.#"),
    "s": (".##", "#..", ".#.", "..#", "##."), "t": ("###", ".#.", ".#.", ".#.", ".#."),
    "u": ("#.#", "#.#", "#.#", "#.#", "###"), "v": ("#.#", "#.#", "#.#", "#.#", ".#."),
    "w": ("#.#", "#.#", "###", "###", "#.#"), "x": ("#.#", "#.#", ".#.", "#.#", "#.#"),
    "y": ("#.#", "#.#", ".#.", ".#.", ".#."), "z": ("###", "..#", ".#.", "#..", "###"),
    "0": ("###", "#.#", "#.#", "#.#", "###"), "1": (".#.", "##.", ".#.", ".#.", "###"),
    "2": ("##.", "..#", ".#.", "#..", "###"), "3": ("##.", "..#", ".#.", "..#", "##."),
    "4": ("#.#", "#.#", "###", "..#", "..#"), "5": ("###", "#..", "##.", "..#", "##."),
    "6": (".##", "#..", "###", "#.#", "###"), "7": ("###", "..#", ".#.", ".#.", ".#."),
    "8": ("###", "#.#", "###", "#.#", "###"), "9": ("###", "#.#", "###", "..#", "##."),
    "_": ("...", "...", "...", "...", "###"), "-": ("...", "...", "###", "...", "..."),
    ".": ("...", "...", "...", "...", ".#."), " ": ("...", "...", "...", "...", "..."),
    "(": (".#.", "#..", "#..", "#..", ".#."), ")": (".#.", "..#", "..#", "..#", ".#."),
    "/": ("..#", "..#", ".#.", "#..", "#.."), ":": ("...", ".#.", "...", ".#.", "..."),
}
_FONT = {k: "".join(v) for k, v in _GLYPHS.items()}


def text(cv: it.Canvas, s: str, x: int, y: int, col: it.RGBA, scale: int = 2) -> int:
    for ch in s.lower():
        g = _FONT.get(ch, _FONT[" "])
        for i, bit in enumerate(g):
            if bit == "#":
                cv.rect(x + (i % 3) * scale, y + (i // 3) * scale, scale, scale, col)
        x += 4 * scale
    return x


def text_w(s: str, scale: int = 2) -> int:
    return len(s) * 4 * scale


# ---------------------------------------------------------------- colours
INK = (0x33, 0x43, 0x4B, 255)
CREAM = (0xF7, 0xEA, 0xD6, 255)
PAPER = (0xEE, 0xE6, 0xDA, 255)
CHECK_A = (0xE9, 0xE2, 0xD8, 255)
CHECK_B = (0xDD, 0xD5, 0xCA, 255)
SAGE_BG = (0x9D, 0xB8, 0x8F, 255)
HEADER = (0x80, 0x5C, 0x49, 255)
WARN = (0xC2, 0x61, 0x4F, 255)

CVD = {
    "protanopia": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
    "deuteranopia": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
    "tritanopia": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}


def _lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _unlin(c: float) -> float:
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def luminance(c: it.RGBA) -> float:
    r, g, b = (_lin(v / 255) for v in c[:3])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def simulate(pix: list[list[it.RGBA]], kind: str) -> list[list[it.RGBA]]:
    m = CVD[kind]
    cache: dict[it.RGBA, it.RGBA] = {}

    def f(c: it.RGBA) -> it.RGBA:
        if c[3] == 0:
            return c
        if c not in cache:
            l = [_lin(v / 255) for v in c[:3]]
            o = [round(_unlin(sum(m[i][j] * l[j] for j in range(3))) * 255) for i in range(3)]
            cache[c] = (o[0], o[1], o[2], c[3])
        return cache[c]

    return [[f(c) for c in row] for row in pix]


# ---------------------------------------------------------------- lint
def lint(lib: it.Library) -> list[str]:
    out: list[str] = []
    for name, ic in lib.icons.items():
        pix = lib.pixels(name)
        h, w = ic.h, ic.w
        if not name.startswith(LINT_EXEMPT):
            light_edge = []
            for y in range(h):
                for x in range(w):
                    c = pix[y][x]
                    if c[3] == 0:
                        continue
                    edge = any(not (0 <= x + dx < w and 0 <= y + dy < h) or pix[y + dy][x + dx][3] == 0
                               for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                    if edge and luminance(c) > 0.13:
                        light_edge.append((x, y))
            if light_edge:
                pts = " ".join(f"{x},{y}" for x, y in light_edge[:6])
                out.append(f"{name}: {len(light_edge)} silhouette pixel(s) not dark-outlined ({pts})")
            touching = sum(1 for x in range(w) if pix[0][x][3]) + sum(1 for x in range(w) if pix[h - 1][x][3])
            if name.startswith("sys_") and w == 16 and touching > 10:
                out.append(f"{name}: art fills the full canvas height; keep a 1-px margin")
        colours = {c for row in pix for c in row if c[3]}
        limit = 9 if w <= 16 else 14
        if len(colours) > limit and not name.startswith("app_icon"):
            out.append(f"{name}: {len(colours)} colours (aim for <= {limit} incl. outline/highlight)")
        if name in NINE_SLICE:
            m = NINE_SLICE[name]
            bad_rows = [y for y in range(h) if len({pix[y][x] for x in range(m, w - m)}) > 1]
            bad_cols = [x for x in range(w) if len({pix[y][x] for y in range(m, h - m)}) > 1]
            if bad_rows or bad_cols:
                out.append(f"{name}: 9-slice centre band not uniform (rows {bad_rows[:4]}, cols {bad_cols[:4]})")
        if name in SIZES and (w, h) != (SIZES[name], SIZES[name]):
            out.append(f"{name}: is {w}x{h}, expected {SIZES[name]}x{SIZES[name]}")
        elif name in REQUIRED and name not in SIZES and (w, h) != (16, 16):
            out.append(f"{name}: is {w}x{h}, expected 16x16")
    return out


# ---------------------------------------------------------------- sheets
def _checker(cv: it.Canvas, x: int, y: int, w: int, h: int, cell: int = 8) -> None:
    for yy in range(0, h, cell):
        for xx in range(0, w, cell):
            c = CHECK_A if ((xx // cell) + (yy // cell)) % 2 == 0 else CHECK_B
            cv.rect(x + xx, y + yy, min(cell, w - xx), min(cell, h - yy), c)


def _cell_size(ic: it.Icon, scale: int, label: str) -> tuple[int, int]:
    big_w, big_h = ic.w * scale, ic.h * scale
    side_w = ic.w * 2 + 8
    w = max(big_w + 8 + side_w, text_w(label)) + 16
    h = max(big_h, ic.h * 2 + 4 + ic.h + 4) + 8 + 14 + 8
    return w, h


def _draw_cell(cv: it.Canvas, lib: it.Library, name: str, x: int, y: int, scale: int, variant: str,
               sim: str | None = None, label: str | None = None) -> None:
    ic = lib.icons[name]
    pix = lib.pixels(name, variant)
    if sim:
        pix = simulate(pix, sim)
    bw, bh = ic.w * scale, ic.h * scale
    _checker(cv, x + 8, y + 8, bw, bh)
    cv.blit(pix, x + 8, y + 8, scale)
    sx = x + 8 + bw + 8
    cv.rect(sx - 2, y + 6, ic.w * 2 + 4, ic.h * 2 + 4, INK)
    cv.blit(pix, sx, y + 8, 2)
    sy = y + 8 + ic.h * 2 + 6
    cv.rect(sx - 2, sy - 2, ic.w + 4, ic.h + 4, INK)
    cv.blit(pix, sx, sy, 1)
    cv.rect(sx + ic.w + 2, sy - 2, ic.w + 4, ic.h + 4, CREAM)
    cv.blit(pix, sx + ic.w + 4, sy, 1)
    lab = label if label is not None else name
    text(cv, lab, x + 8, y + 8 + max(bh, ic.h * 3 + 10) + 6, INK)


def sheet(lib: it.Library, groups: list[tuple[str, list[str]]], path: str, variant: str = "default",
          scale: int = 4, width: int = 1280, title: str = "") -> None:
    # Layout pass.
    placements: list[tuple[str, int, int]] = []
    headers: list[tuple[str, int]] = []
    y = 8
    if title:
        y += 34
    for gname, names in groups:
        headers.append((gname, y))
        y += 30
        x, row_h = 0, 0
        for n in names:
            cw, ch = _cell_size(lib.icons[n], scale, n)
            if x + cw > width and x > 0:
                x, y = 0, y + row_h
                row_h = 0
            placements.append((n, x, y))
            x += cw
            row_h = max(row_h, ch)
        y += row_h + 6
    cv = it.Canvas(width, y + 8, PAPER)
    if title:
        text(cv, title, 12, 12, HEADER, 3)
    for gname, hy in headers:
        cv.rect(0, hy, width, 24, HEADER)
        text(cv, gname, 12, hy + 4, CREAM, 3)
    for n, x, py in placements:
        _draw_cell(cv, lib, n, x, py, scale, variant)
    cv.save(path)


def cvd_check(lib: it.Library, path: str, scale: int = 3) -> None:
    titles = ["semantic", "families", "status and pings"]
    sets = [
        ["sys_warm", "sys_cold", "sys_cozy", "sys_quiet", "sys_noise", "sys_water", "sys_humid", "sys_clean"],
        ["fam_slime", "fam_yeti", "fam_dragon", "fam_ghost", "fam_moonwolf", "fam_sprout"],
        ["sys_connection_good", "sys_connection_poor", "sys_disconnected", "sys_star", "sys_star_empty",
         "ping_help", "ping_bringing", "ping_ready", "ping_thanks", "diff_cozy", "diff_family", "diff_busy"],
    ]
    rows: list[tuple[str, str, str | None]] = [("default palette", "default", None)]
    for kind in ("deuteranopia", "protanopia", "tritanopia"):
        rows.append((f"{kind} sees default", "default", kind))
        rows.append((f"{kind} sees {kind} variant", kind, kind))
    rows.append(("high_contrast", "high_contrast", None))
    label_w = 380
    step = 16 * scale + 10
    width = label_w + max(len([n for n in s if n in lib.icons]) for s in sets) * step + 20
    height = 40 + len(sets) * (len(rows) * (step + 4) + 34)
    cv = it.Canvas(width, height, PAPER)
    text(cv, "colour vision check", 12, 10, HEADER, 3)
    y = 40
    for title, s in zip(titles, sets):
        names = [n for n in s if n in lib.icons]
        cv.rect(0, y, width, 26, HEADER)
        text(cv, title, 12, y + 4, CREAM, 3)
        y += 32
        for label, variant, kind in rows:
            text(cv, label, 12, y + step // 2 - 6, INK)
            x = label_w
            for n in names:
                pix = lib.pixels(n, variant)
                if kind:
                    pix = simulate(pix, kind)
                ic = lib.icons[n]
                cv.rect(x - 2, y - 2, 16 * scale + 4, 16 * scale + 4, CREAM)
                cv.blit(pix, x + (16 - ic.w) * scale // 2 if ic.w <= 16 else x, y, scale if ic.w <= 16 else 2)
                x += step
            y += step + 4
        y += 2
    cv.save(path)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="comma-separated source file stems (e.g. systems,items)")
    ap.add_argument("--names", help="comma-separated icon names")
    ap.add_argument("--out", help="output path for a single sheet (with --only/--names)")
    ap.add_argument("--variant", default="default", help="palette variant for --out sheet")
    ap.add_argument("--no-variants", action="store_true", help="skip variant and cvd sheets")
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--dir", default=it.ICON_DIR, help="source directory (default data/art/icons)")
    args = ap.parse_args()

    lib = it.load(args.dir)
    for e in lib.errors:
        print("ERROR", e)
    files = lib.by_file()
    pref = ["families.txt", "guests.txt", "staff.txt", "items.txt", "systems.txt", "actions.txt", "ui.txt", "badges.txt"]
    order = [f for f in pref if f in files] + sorted(f for f in files if f not in pref)

    if args.only or args.names:
        groups: list[tuple[str, list[str]]] = []
        if args.only:
            stems = [s.strip() for s in args.only.split(",")]
            for st in stems:
                f = st if st.endswith(".txt") else st + ".txt"
                if f in files:
                    groups.append((f[:-4], files[f]))
        if args.names:
            wanted = [n.strip() for n in args.names.split(",") if n.strip() in lib.icons]
            groups.append(("selection", wanted))
        out = args.out or os.path.join(OUT_DIR, "icons_%s.png" % "_".join(g for g, _ in groups))
        sheet(lib, groups, out, args.variant, args.scale)
        print("wrote", os.path.relpath(out, it.ROOT))
    else:
        all_groups = [(f[:-4], files[f]) for f in order]
        out = os.path.join(OUT_DIR, "icons_sheet.png")
        sheet(lib, all_groups, out, "default", args.scale, title="room for trouble icons - default")
        print("wrote", os.path.relpath(out, it.ROOT))
        for f in order:
            p = os.path.join(OUT_DIR, f"icons_{f[:-4]}.png")
            sheet(lib, [(f[:-4], files[f])], p, "default", args.scale)
            print("wrote", os.path.relpath(p, it.ROOT))
        if not args.no_variants:
            for v in lib.variants:
                if v == "default":
                    continue
                p = os.path.join(OUT_DIR, f"icons_sheet_{v}.png")
                sheet(lib, all_groups, p, v, args.scale, title=f"room for trouble icons - {v}")
                print("wrote", os.path.relpath(p, it.ROOT))
            p = os.path.join(OUT_DIR, "icons_cvd_check.png")
            cvd_check(lib, p)
            print("wrote", os.path.relpath(p, it.ROOT))

    missing = [n for n in REQUIRED if n not in lib.icons]
    extra = [n for n in lib.icons if n not in REQUIRED]
    warnings = lint(lib)
    scope = None
    if args.only:
        scope = set()
        for st in args.only.split(","):
            scope |= set(files.get(st.strip() + ".txt", []))
    if args.names:
        scope = (scope or set()) | {n.strip() for n in args.names.split(",")}
    for w in warnings:
        if scope is None or w.split(":")[0] in scope:
            print("LINT ", w)
    print(f"{len(lib.icons)} icons in {len(files)} files; variants: {', '.join(lib.variants)}")
    if extra:
        print("extra (not in required list):", " ".join(extra))
    if missing:
        print(f"missing {len(missing)}:", " ".join(missing))
    return 1 if lib.errors else 0


if __name__ == "__main__":
    sys.exit(main())
