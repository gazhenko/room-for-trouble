#!/usr/bin/env python3
"""Builds runtime content from editable sources (Python 3.11+ stdlib only).

  python3 tools/build_content.py

Writes:
  data/localization/en.json   English localization source (all keys)
  data/story/*.json           StoryPanel scenes (opening, bridges, ending, levels)
  data/levels/Lxx.json        derived per-level schedules for 1–4 players
  data/credits.json           credits and third-party notices
Level purposes come straight from docs/DESIGN_BRIEF.md so prose stays canonical.
"""
import json, math, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools" / "content"))
import strings_en as S  # noqa: E402
import story_src as ST  # noqa: E402

manifest = json.loads((ROOT / "data/campaign_manifest.json").read_text())
brief = (ROOT / "docs/DESIGN_BRIEF.md").read_text()

loc = {}
for part in (S.UI, S.SETTINGS, S.CAST, S.GUESTS, S.ITEMS, S.BARKS, S.MODS, S.COSMETICS, S.CHAPTERS, S.TUTORIALS, S.CREDITS_EXTRA):
    loc.update(part)

# ---------------------------------------------------------------- levels
cards = re.split(r"\n### (L\d\d) — ", brief)
purposes = {}
payoffs = {}
for i in range(1, len(cards), 2):
    lid = cards[i]
    body = cards[i + 1]
    m = re.search(r"\*\*Purpose:\*\* (.+)", body)
    purposes[lid] = m.group(1).strip() if m else ""
    m = re.search(r"\*\*Silly payoff:\*\* (.+)", body)
    payoffs[lid] = m.group(1).strip() if m else ""

for L in manifest["levels"]:
    lid = L["id"]
    loc[f"level.{lid}.title"] = L["title"]
    loc[f"level.{lid}.purpose"] = purposes.get(lid, "")
    loc[f"level.{lid}.payoff"] = payoffs.get(lid, "")
    for rb in L["ribbons"]:
        loc[f"ribbon.{lid}.{rb['predicate']}"] = rb["label"]
loc["level.L19.view"] = "A guest would love a new view. Try Move Room at their door."
loc["level.L24.music"] = "The festival music joins in."
loc["level.L24.lanterns"] = "The lanterns glow steadily."

def panel_out(p, scene_id, idx):
    d = {k: v for k, v in p.items() if k != "caption_text"}
    key = f"story.{p['id']}" if p.get("id") else f"story.{scene_id}.{idx}"
    if p.get("caption_text"):
        loc[key] = p["caption_text"]
        d["caption"] = key
    if d.get("camera") == "postcard_still":
        d["set"] = "photo"
        d.pop("actors_rel", None)
        d.pop("focus", None)
    elif d.get("actors_rel") and "focus" in d:
        fx, fz = d["focus"]
        for a in d["actors"]:
            a["pos"] = [round(a["pos"][0] + fx, 3), round(a["pos"][1] + fz, 3)]
            if "pos" in a and False:
                pass
        for pr in d["props"]:
            pr["pos"] = [round(pr["pos"][0] + fx, 3), pr["pos"][1], round(pr["pos"][2] + fz, 3)]
        d.pop("actors_rel")
    return d

def scene_out(sc):
    out = {"id": sc["id"], "layout": sc.get("layout", "P1"), "music": sc.get("music", "title_loop"),
           "title_key": f"story.{sc['id']}.title", "panels": []}
    loc[f"story.{sc['id']}.title"] = sc.get("title", sc["id"])
    for i, p in enumerate(sc["panels"]):
        out["panels"].append(panel_out(p, sc["id"], i))
    return out

def write(rel, obj):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=1, ensure_ascii=False) + "\n")

write("data/story/opening.json", {"schema_version": 1, "scenes": [scene_out(ST.OPENING)]})
write("data/story/bridges.json", {"schema_version": 1, "scenes": [scene_out(b) for b in ST.BRIDGES]})
write("data/story/ending.json", {"schema_version": 1, "scenes": [scene_out(ST.ENDING)]})

level_scenes = []
gags = {}
for L in manifest["levels"]:
    lid = L["id"]
    pre, mid, post = ST.LEVELS[lid]
    cam, focus, cap, speaker, actors = pre
    layout = L["layout"]
    pp = ST.P(f"{lid}.pre", cam, cap, speaker, 6, actors, focus=focus, layout=layout)
    level_scenes.append({"id": f"{lid}.pre", "layout": layout, "music": "planning",
                         "title_key": f"story.{lid}.pre.title", "panels": [panel_out(pp, lid, 0)]})
    loc[f"story.{lid}.pre.title"] = f"{L['title']} — before the clock"
    trig, fallback, mspeaker, mcap = mid
    loc[f"level.{lid}.mid"] = mcap
    gags[lid] = {"trigger": trig, "fallback_s": fallback, "speaker": mspeaker, "caption": f"level.{lid}.mid"}
    pspeaker, pcap, fams, prop = post
    loc[f"level.{lid}.postcard"] = pcap
    staff_actor = ST.A("staff", 0.0, 0.7, "photo")
    gactors = []
    names = {"slime": "mallow", "yeti": "flurry", "dragon": "cinder", "ghost": "whisp", "moonwolf": "luna", "sprout": "fern"}
    variant_fam = {v: k for k, v in names.items()}
    fams = [variant_fam.get(f, f) for f in fams]
    for j, f in enumerate(fams[:6]):
        x = -1.0 * (len(fams[:6]) - 1) * 0.5 + j * 1.0
        gactors.append(ST.A(names[f] if j < 1 else f"guest:{f}", round(x, 2), -0.6, "happy" if j % 2 == 0 else "wave",
                            slippers=(f == "slime"), mask=(f == "ghost")))
    props = [{"kind": prop, "pos": [2.8, 0.0, -1.2]}] if prop else []
    fx = {"P1": [6.0, 9.6], "P2": [13.0, 9.6], "P3": [13.0, 9.6], "P4": [13.0, 9.6], "P5": [18.0, 9.8], "P6": [13.0, 9.6]}[layout]
    pq = ST.P(f"{lid}.post", "postcard_still", pcap, pspeaker, 6,
              [staff_actor, ST.A("nana", -2.6, 0.2, "wave"), ST.A("gus", 2.6, 0.7, "happy")] + gactors,
              props, focus=fx, layout=layout, actors_rel=True, sting="sting_postcard")
    level_scenes.append({"id": f"{lid}.post", "layout": layout, "music": "title_loop",
                         "title_key": f"story.{lid}.post.title", "panels": [panel_out(pq, lid, 1)]})
    loc[f"story.{lid}.post.title"] = f"{L['title']} — postcard"
write("data/story/levels.json", {"schema_version": 1, "scenes": level_scenes, "gags": gags})

# ---------------------------------------------------------------- derived level files
SCALE = [650, 1000, 1250, 1500]
CAP = [2, 4, 5, 6]
for L in manifest["levels"]:
    tpl_active = 4 if L["layout"] == "P1" else 6
    per = {}
    for h in range(1, 5):
        cap = min(6, CAP[h - 1], tpl_active)
        waves = []
        for w in L["waves"]:
            b = len(w["roster"])
            n = (b * SCALE[h - 1] + 500) // 1000
            n = max(min(max(n, 1), cap), w["minimum_size"])
            waves.append([w["roster"][i % b] for i in range(n)])
        d = L["duration_hotel_s"]
        anchors = [30, (30 + d - 150) // 2, d - 150]
        sched = []
        for wi, wave in enumerate(waves):
            k = len(wave)
            for j, fam in enumerate(wave):
                t = anchors[wi] - 5 * (k - 1 - j)
                sched.append({"family": fam, "wave": wi, "arrive_s": t, "announce_s": max(0, t - 8)})
        per[str(h)] = {"waves": waves, "schedule": sched, "guest_count": len(sched)}
    write(f"data/levels/{L['id']}.json", {"schema_version": 1, "generated_from": "data/campaign_manifest.json",
          "id": L["id"], "title": L["title"], "chapter": L["chapter"], "layout": L["layout"],
          "story": {"pre": f"{L['id']}.pre", "post": f"{L['id']}.post", "gag": gags[L["id"]]},
          "by_humans": per})

# ---------------------------------------------------------------- credits
credits = {"schema_version": 1, "sections": [
    {"title": "Room for Trouble", "lines": [
        "An original cooperative game about running a cozy monster hotel together.",
        "Design brief: “Room for Trouble” complete game design and engineering handoff, v1.0 (2026-10-22).",
        "Implementation, procedural art, procedural audio and tools: built with Claude Code (Anthropic) for the project owner."]},
    {"title": "Cast", "lines": ["Nana Nook · Gus · Dot Quill", "Pip · Pebble · Moss · Button",
        "Mallow · Flurry · Cinder · Whisp · Luna · Fern"]},
    {"title": "Art & audio", "lines": [
        "All 3D models are procedural low-poly meshes authored in code (src/view/models).",
        "All icons are original pixel art authored as text (data/art/icons).",
        "All music and sound effects are original procedural synthesis (tools/audio/synth.py)."]},
    {"title": "Third-party", "lines": [
        "Godot Engine 4.7.2 — MIT License, © Juan Linietsky, Ariel Manzur and contributors.",
        "Pixelify Sans — SIL Open Font License 1.1, © The Pixelify Sans Project Authors.",
        "Nunito — SIL Open Font License 1.1, © The Nunito Project Authors.",
        "Full licence texts: THIRD_PARTY_NOTICES.md and assets/export/fonts/."]},
    {"title": "Thank you", "lines": ["To every family, friend and neighbour who makes a little room."]},
]}
write("data/credits.json", credits)

# ---------------------------------------------------------------- localization
write("data/localization/en.json", dict(sorted(loc.items())))
print(f"strings: {len(loc)}  story scenes: {1 + len(ST.BRIDGES) + 1 + len(level_scenes)}  levels: {len(manifest['levels'])}")
