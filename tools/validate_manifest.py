#!/usr/bin/env python3
"""Validates the canonical campaign manifest (§21.2). Python 3.11+ stdlib.

  python3 tools/validate_manifest.py data/campaign_manifest.json

Exit code 0 = valid. Reports file/field paths for every problem.
Also prints the derived arrival schedule summary and ribbon upper bounds.
"""
import json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
FAMILIES = {"slime", "yeti", "dragon", "ghost", "moonwolf", "sprout"}
SYSTEMS = {"core", "thermal", "sound", "moisture", "shutter", "lift", "festival"}
EVENT_ARGS = {
    "announce": {"text_key", "icon"}, "coach": {"coach_id", "once_per_profile"},
    "thermal_pulse": {"room", "delta"}, "humidity_pulse": {"room", "delta"},
    "steam_cloud": {"position"}, "frost_patch": {"room"}, "concert_pulse": {"room", "amplitude"},
    "fixture_trip": {"fixture"}, "puddle_patch": {"positions"},
    "shutter_cycle": {"period", "warning", "closed"}, "trunk_spawn": {"object_id", "position", "goal"},
    "parcels_spawn": {"object_ids", "positions", "goal"},
}
FIXTURES = {f"radiator_{c}" for c in "ABCDEF"} | {"towels", "snacks", "lift_pair"}
PREDICATES = {"useful_handoffs", "shared_work", "cozy_departures", "welcome_matches", "laundry_cycles", "requests",
              "vent_solution", "quiet_howls", "balanced_rooms", "water_care", "helpful_guests", "relocations",
              "trunk_goal", "safe_lift_deliveries", "festival_parcels", "tidy_rooms"}
FAMILY_SYSTEM = {"yeti": "thermal", "dragon": "thermal", "ghost": "sound", "moonwolf": "sound", "sprout": "moisture"}
LEVEL_KEYS = {"id", "title", "chapter", "layout", "duration_hotel_s", "waves", "service_count", "systems",
              "initial_rooms", "events", "ribbons", "required_goal_ids"}
# v2 (Overcooked-scale) levels carry their own pacing and timers (DESIGN_V2.md).
V2_KEYS = {"pacing", "patience_s", "request_s", "stay_s", "linen_start"}
PACING_KEYS = {"first_s", "gap_s", "announce_s", "reserve_s"}
SCALE = [650, 1000, 1250, 1500]
CAP = [2, 4, 5, 6]

def main(path):
    errors, warnings = [], []
    m = json.loads(pathlib.Path(path).read_text())
    base = json.loads((ROOT / "data/layouts/base.json").read_text())
    bases = {"default": base}
    for name in ("v2_small", "v2_six", "v2_split"):
        bp = ROOT / f"data/layouts/base_{name}.json"
        if bp.exists():
            bases[name] = json.loads(bp.read_text())
    templates = {t["id"]: t for t in json.loads((ROOT / "data/layouts/templates.json").read_text())["templates"]}
    def err(p, msg): errors.append(f"{path}:{p}: {msg}")
    if m.get("schema_version") != 1:
        err("schema_version", "must be 1")
    levels = m.get("levels", [])
    if len(levels) != 24:
        err("levels", f"expected 24 levels, found {len(levels)}")
    chapters = {}
    for i, L in enumerate(levels):
        p = f"levels[{i}]"
        extra = set(L) - LEVEL_KEYS - V2_KEYS
        missing = LEVEL_KEYS - set(L)
        if extra: err(p, f"unknown fields {sorted(extra)}")
        if missing: err(p, f"missing fields {sorted(missing)}"); continue
        if not re.fullmatch(r"L(0[1-9]|1\d|2[0-4])", L["id"]) or L["id"] != f"L{i+1:02d}":
            err(p + ".id", f"bad or out-of-order id {L['id']}")
        if not 1 <= L["chapter"] <= 6: err(p + ".chapter", "1..6")
        chapters.setdefault(L["chapter"], []).append(L["id"])
        if L["layout"] not in templates: err(p + ".layout", f"unknown layout {L['layout']}")
        v2 = templates.get(L["layout"], {}).get("base", "") != ""
        if L["duration_hotel_s"] < (150 if v2 else 270):
            err(p + ".duration_hotel_s", ">= %d required" % (150 if v2 else 270))
        if "pacing" in L:
            pc = L["pacing"]
            if set(pc) != PACING_KEYS: err(p + ".pacing", f"expected {sorted(PACING_KEYS)}")
            elif v2 and not 0 < pc["first_s"] <= 5: err(p + ".pacing.first_s", "first guest within 5 s on v2 floors")
        if len(L["waves"]) != 3: err(p + ".waves", "exactly 3 waves")
        if L["service_count"] not in (1, 2): err(p + ".service_count", "1 or 2")
        for s in L["systems"]:
            if s not in SYSTEMS: err(p + ".systems", f"unknown system {s}")
        if len(L["initial_rooms"]) > 6: err(p + ".initial_rooms", "at most 6 overrides")
        tpl = templates.get(L["layout"], {})
        active = tpl.get("active_rooms", [])
        hall = bases.get(tpl.get("base", "default"), base)["hall"]   # [x0, z0, x1, z1]
        for room in L["initial_rooms"]:
            if room not in active: err(p + f".initial_rooms.{room}", "room not active in layout")
        fams = set()
        for wi, w in enumerate(L["waves"]):
            r = w.get("roster", [])
            if not 1 <= len(r) <= 4: err(p + f".waves[{wi}].roster", "1..4 families")
            for f in r:
                if f not in FAMILIES: err(p + f".waves[{wi}].roster", f"unknown family {f}")
                fams.add(f)
            ms = w.get("minimum_size", 1)
            if not 1 <= ms <= 2 or ms > len(r): err(p + f".waves[{wi}].minimum_size", "1..2 and <= roster length")
        for f in fams:
            need = FAMILY_SYSTEM.get(f)
            if need and need not in L["systems"]:
                err(p + ".systems", f"family {f} needs system {need}")
        ids = set()
        D = L["duration_hotel_s"]
        spawned = set()
        for ei, e in enumerate(L["events"]):
            ep = p + f".events[{ei}]"
            if e["id"] in ids: err(ep + ".id", "duplicate event id")
            ids.add(e["id"])
            if not 0 <= e["at"] <= D: err(ep + ".at", "0..duration")
            t = e["type"]
            if t not in EVENT_ARGS: err(ep + ".type", f"unknown type {t}"); continue
            if set(e.get("args", {})) != EVENT_ARGS[t]: err(ep + ".args", f"expected {sorted(EVENT_ARGS[t])}")
            a = e["args"]
            if t in ("thermal_pulse", "humidity_pulse", "frost_patch", "concert_pulse") and a["room"] not in active:
                err(ep + ".args.room", "room not active")
            if t == "fixture_trip" and a["fixture"] not in FIXTURES: err(ep + ".args.fixture", "not an allowed runtime fixture")
            if t == "fixture_trip" and a["fixture"].startswith("radiator") and "thermal" not in L["systems"]:
                err(ep, "radiator trip without thermal system")
            if t == "shutter_cycle" and (L["layout"][:2] != "P5" or "shutter" not in L["systems"]): err(ep, "shutter only on P5")
            if t == "fixture_trip" and a["fixture"] == "lift_pair" and "lift" not in L["systems"]: err(ep, "lift trip needs lift")
            if t == "trunk_spawn":
                if L["layout"][:2] not in ("P1", "P6"): err(ep, "trunks only on P1/P6")
                spawned.add(a["object_id"])
            if t == "parcels_spawn":
                if len(a["object_ids"]) != len(a["positions"]): err(ep, "object_ids/positions length mismatch")
                spawned |= set(a["object_ids"])
            if t in ("steam_cloud",):
                x, z = a["position"]
                if not (hall[0] <= x <= hall[2] and hall[1] <= z <= hall[3]): err(ep + ".args.position", "must be in the hall")
            if t == "puddle_patch":
                for pos in a["positions"]:
                    if not (hall[0] <= pos[0] <= hall[2] and hall[1] <= pos[1] <= hall[3]): err(ep + ".args.positions", "must be in the hall")
        for gid in L["required_goal_ids"]:
            if gid not in spawned: err(p + ".required_goal_ids", f"{gid} is not spawned by this level")
        if len(L["ribbons"]) != 3: err(p + ".ribbons", "exactly 3 ribbons")
        for ri, rb in enumerate(L["ribbons"]):
            if rb["predicate"] not in PREDICATES: err(p + f".ribbons[{ri}].predicate", f"unknown {rb['predicate']}")
            t4 = rb.get("targets_1_to_4", [])
            if len(t4) != 4 or any((not isinstance(v, int)) or v <= 0 for v in t4):
                err(p + f".ribbons[{ri}].targets_1_to_4", "four positive integers")
        # Expansion, capacity, reserve, solo lesson coverage (DATA02/SOLO01).
        active_n = len(active)
        for h in range(1, 5):
            cap = min(6, CAP[h - 1], active_n)
            sched = []
            for wi, w in enumerate(L["waves"]):
                b = len(w["roster"])
                n = max(min(max((b * SCALE[h - 1] + 500) // 1000, 1), cap), w["minimum_size"])
                if n > cap: err(p + f".waves[{wi}]", f"minimum_size {n} exceeds cap {cap} for {h} humans")
                sched.append([w["roster"][k % b] for k in range(n)])
            anchors = [30, (30 + D - 150) // 2, D - 150]
            first = anchors[0] - 5 * (len(sched[0]) - 1)
            if first < 0: err(p, f"negative first arrival for {h} humans")
            reserve = 50 + 15 + 80 + 3
            if D - anchors[2] < reserve: err(p, f"final-arrival reserve {D - anchors[2]} < {reserve}")
            # Ribbon upper bounds (DATA03).
            guests = sum(len(w) for w in sched)
            fam_count = {}
            for w in sched:
                for f in w:
                    fam_count[f] = fam_count.get(f, 0) + 1
            for ri, rb in enumerate(L["ribbons"]):
                tgt = rb["targets_1_to_4"][h - 1]
                pred = rb["predicate"]
                ub = None
                if pred in ("welcome_matches", "cozy_departures", "helpful_guests"): ub = guests
                elif pred == "requests": ub = guests * L["service_count"]
                elif pred == "water_care": ub = fam_count.get("sprout", 0)
                elif pred == "quiet_howls": ub = fam_count.get("moonwolf", 0)
                elif pred == "trunk_goal": ub = sum(1 for e in L["events"] if e["type"] == "trunk_spawn")
                elif pred == "festival_parcels": ub = sum(len(e["args"]["object_ids"]) for e in L["events"] if e["type"] == "parcels_spawn")
                elif pred == "tidy_rooms": ub = active_n
                elif pred == "balanced_rooms": ub = cap
                elif pred == "relocations": ub = guests
                if ub is not None and tgt > ub:
                    err(p + f".ribbons[{ri}]", f"target {tgt} impossible for {h} humans (upper bound {ub})")
        # Solo lesson coverage: L16/L24 cover all families; protected pairs survive.
        solo = []
        for w in L["waves"]:
            b = len(w["roster"])
            n = max(min(max((b * 650 + 500) // 1000, 1), min(2, active_n)), w["minimum_size"])
            solo += [w["roster"][k % b] for k in range(n)]
        if L["id"] in ("L16", "L24") and set(solo) != FAMILIES:
            err(p, f"solo expansion must cover all six families, got {sorted(set(solo))}")
    for ch in range(1, 7):
        if len(chapters.get(ch, [])) != 4:
            err("levels", f"chapter {ch} must have exactly 4 levels")
    for e in errors:
        print("ERROR", e)
    for w in warnings:
        print("WARN ", w)
    print(f"{len(levels)} levels checked: {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else str(ROOT / "data/campaign_manifest.json")))
