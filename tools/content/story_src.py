"""Storyboard source (§4, §14): opening O00, chapter bridges B01–B05, ending
E00 and each level's pre-shift beat, live gag and postcard. build_content.py
turns this into data/story/*.json (editable StoryPanel resources) and caption
strings in data/localization/en.json."""

# Actor helpers: positions are world tile coordinates on the stage layout.
def A(id, x, z, pose="idle", face=0, **kw):
    d = {"id": id, "pos": [x, z], "pose": pose, "face": face}
    d.update(kw)
    return d

LOBBY_STAFF = A("staff", 5.0, 10.2, "idle")
NANA_DESK = A("nana", 1.3, 9.0, "idle", 70)
GUS_DESK = A("gus", 3.2, 10.4, "idle")
DOT_DESK = A("dot", 3.6, 9.2, "idle", -20)

def P(pid, camera, caption, speaker="", duration=6, actors=None, props=None, focus=None, layout=None, sound=None, sting=None, **kw):
    d = {"id": pid, "camera": camera, "duration": duration, "caption_text": caption, "speaker": speaker,
         "actors": actors or [], "props": props or []}
    if focus: d["focus"] = focus
    if layout: d["layout"] = layout
    if sound: d["sound"] = sound
    if sting: d["sting"] = sting
    d.update(kw)
    return d

OPENING = {
    "id": "O00", "title": "The Opening", "layout": "P1", "music": "title_loop",
    "panels": [
        P("O00.1", "wide_hotel", "A hotel is a place to put your bags down.", "nana", 6,
          [A("nana", -0.9, 9.6, "wave", 90)], sound="chime"),
        P("O00.2", "lobby_group", "And, if we do our jobs…", "nana", 6,
          [A("nana", 3.0, 9.4, "work"), A("gus", 4.3, 9.9, "happy")],
          [{"kind": "sheet_sculpture", "pos": [4.3, 0.0, 9.9], "scale": 0.6}], sound="linen_fold"),
        P("O00.3", "desk_close", "“Moonlight Welcome — neighbours, travellers, everyone.”", "", 5,
          [NANA_DESK], [{"kind": "invitation", "pos": [2.3, 0.95, 9.2]}], sound="bell_ring"),
        P("O00.4", "lobby_group", "We can help!", "staff", 4,
          [A("staff", 5.2, 10.3, "carry"), A("nana", 3.0, 9.4, "happy")]),
        P("O00.4b", "lobby_group", "I was hoping you'd say that.", "nana", 4,
          [A("staff", 5.2, 10.3, "happy"), A("nana", 3.0, 9.4, "wave")]),
        P("O00.5", "desk_close", "Beds. Towels. One standard room temperature. How hard could it be?", "dot", 7,
          [NANA_DESK, A("dot", 3.0, 9.4, "idle", -30)], [{"kind": "checklist", "pos": [3.4, 0.0, 9.9]}], sound="dot_paper"),
        P("O00.6", "guest_close", "We may need more than one kind of welcome.", "nana", 7,
          [A("flurry", 1.7, 9.4, "happy"), A("cinder", 3.5, 9.4, "happy"), A("whisp", 2.6, 9.0, "wave")],
          focus=[2.6, 9.5]),
        P("O00.7", "lobby_group", "Perfect is optional. Helping isn't.", "nana", 7,
          [A("staff", 5.2, 10.3, "happy"), A("nana", 3.0, 9.4, "happy"), A("gus", 4.2, 10.8, "happy")], sound="bell_hiccup"),
        P("O00.8", "postcard_still", "ROOM FOR TROUBLE — There's room for one more.", "", 5,
          [A("staff", 0.0, 0.7, "photo"), A("nana", -2.4, 0.1, "wave", 20), A("gus", 2.4, 0.7, "happy"),
           A("mallow", -1.2, -0.6, "happy", slippers=True), A("flurry", 0.0, -0.8, "happy"), A("cinder", 1.2, -0.6, "happy")],
          sting="sting_results"),
    ],
}

BRIDGES = [
    {"id": "B01", "title": "Chapter 1 → 2", "layout": "P1", "music": "title_loop", "panels": [
        P("B01.1", "lobby_group", "I only lost one slipper. That's a personal best.", "mallow", 6,
          [A("mallow", 3.4, 9.3, "happy", slippers=True), NANA_DESK], [{"kind": "invitation", "pos": [2.3, 0.95, 9.2]}]),
        P("B01.2", "guest_close", "Somewhere cool? … Somewhere toasty?", "flurry", 6,
          [A("flurry", 2.0, 9.5, "idle", 20), A("cinder", 3.2, 9.5, "idle", -20)],
          [{"kind": "travel_hat_cool", "pos": [2.0, 1.75, 9.5]}, {"kind": "travel_hat_warm", "pos": [3.2, 1.55, 9.5]}], focus=[2.6, 9.6]),
        P("B01.3", "desk_close", "I may need a wider checklist.", "dot", 5,
          [A("dot", 3.0, 9.4, "concern", -30), NANA_DESK], [{"kind": "checklist", "pos": [3.4, 0.0, 9.9]}], sound="dot_paper"),
        P("B01.4", "fixture_close", "Let's give everyone a little room.", "nana", 6,
          [A("nana", 8.0, 8.9, "wave")], focus=[8.0, 8.0], layout="P2"),
    ]},
    {"id": "B02", "title": "Chapter 2 → 3", "layout": "P2", "music": "title_loop", "panels": [
        P("B02.1", "lobby_group", "I helped! … Me too. Very differently.", "cinder", 6,
          [A("cinder", 4.0, 9.4, "helper"), A("flurry", 6.0, 9.4, "helper")], [{"kind": "sheet_sculpture", "pos": [5.0, 0.0, 10.4]}]),
        P("B02.2", "guest_close", "Just a quiet corner, please.", "whisp", 5,
          [A("whisp", 2.6, 9.5, "idle", 0, mask=True)], focus=[2.6, 9.5]),
        P("B02.3", "lobby_group", "Is this the singing hotel?", "luna", 6,
          [A("luna", 3.4, 9.6, "happy"), A("nana", 2.0, 9.1, "wave", 60)]),
        P("B02.4", "lobby_group", "There's room for a song. And a nap.", "nana", 6,
          [A("luna", 4.4, 9.6, "happy"), A("whisp", 6.2, 9.6, "idle", mask=True), A("nana", 2.4, 9.1, "happy", 60)], layout="P3"),
    ]},
    {"id": "B03", "title": "Chapter 3 → 4", "layout": "P3", "music": "title_loop", "panels": [
        P("B03.1", "lobby_group", "Two checkboxes. Both checked.", "dot", 6,
          [A("whisp", 3.4, 9.0, "sleep", mask=True), A("luna", 6.2, 9.4, "happy"), A("dot", 4.6, 10.4, "happy")]),
        P("B03.2", "guest_close", "I brought a little something for the garden.", "fern", 6,
          [A("fern", 2.4, 9.6, "happy"), A("dot", 3.6, 9.4, "concern")], [{"kind": "clipboard", "pos": [3.0, 1.4, 9.6]}], focus=[3.0, 9.5]),
        P("B03.3", "wide_hotel", "It's got good bones. And excellent windows.", "moss", 6, [], layout="P4"),
        P("B03.4", "lobby_group", "Small kindnesses grow.", "nana", 6,
          [A("fern", 4.0, 9.6, "happy"), A("gus", 5.4, 10.2, "happy"), A("nana", 2.6, 9.2, "happy")],
          [{"kind": "umbrella", "pos": [5.4, 0.6, 10.2]}], layout="P4"),
    ]},
    {"id": "B04", "title": "Chapter 4 → 5", "layout": "P4", "music": "title_loop", "panels": [
        P("B04.1", "lobby_group", "Everyone has volunteered something.", "dot", 6,
          [A("cinder", 3.2, 9.0, "helper"), A("flurry", 4.6, 9.0, "helper"), A("fern", 6.0, 9.0, "helper"), A("luna", 7.4, 9.0, "helper"), A("dot", 5.0, 10.6, "happy")],
          [{"kind": "lantern", "pos": [3.6, 0.0, 10.2]}, {"kind": "flowerpot_trio", "pos": [6.4, 0.0, 10.4]}]),
        P("B04.2", "lobby_group", "I've got the other end.", "button", 6,
          [A("staff", 5.0, 10.6, "carry")], [{"kind": "mini_trunk", "pos": [5.0, 0.0, 10.0], "scale": 2.2}], layout="P1"),
        P("B04.3", "wide_hotel", "Ask for a hand. Offer one back.", "nana", 6, [A("nana", 13, 9.5, "wave")], layout="P5"),
        P("B04.4", "lobby_group", "(A delighted squeak!)", "gus", 6,
          [A("gus", 4.0, 10.4, "happy"), A("staff", 6.0, 10.2, "happy")], [{"kind": "paper_moon", "pos": [5.0, 0.0, 9.0], "scale": 0.8}], layout="P6"),
    ]},
    {"id": "B05", "title": "Chapter 5 → 6", "layout": "P6", "music": "title_loop", "panels": [
        P("B05.1", "festival_wide", "We are almost ready.", "dot", 6, [A("dot", 16.0, 9.5, "happy"), A("staff", 18.0, 10.0, "work")],
          [{"kind": "lantern", "pos": [15.0, 0.0, 9.0]}, {"kind": "lantern", "pos": [19.0, 0.0, 9.0]}]),
        P("B05.2", "guest_close", "Is rain on the guest list?", "cinder", 6, [A("cinder", 2.6, 9.6, "concern")],
          [{"kind": "lantern", "pos": [1.6, 0.0, 9.9]}, {"kind": "umbrella", "pos": [3.2, 0.9, 9.8]}], focus=[2.6, 9.6]),
        P("B05.3", "wide_hotel", "We've spent all week making room.", "nana", 6, [A("nana", 13.0, 9.6, "wave")]),
        P("B05.4", "festival_wide", "Let's use it.", "staff", 6,
          [A("staff", 17.0, 10.2, "happy"), A("nana", 15.0, 9.4, "happy"), A("gus", 19.2, 10.4, "happy")],
          [{"kind": "paper_moon", "pos": [17.0, 0.0, 8.6]}]),
    ]},
]

ENDING = {
    "id": "E00", "title": "The Moonlight Welcome", "layout": "P6", "music": "ending",
    "panels": [
        P("E00.1", "festival_wide", "Look at that. A whole hotel full of welcome.", "nana", 6,
          [A("nana", 16.0, 9.4, "happy"), A("staff", 18.0, 10.2, "happy")], [{"kind": "paper_moon", "pos": [17.0, 0.0, 8.6]}]),
        P("E00.2", "guest_close", "(Flurry offers a chilled cup. Cinder offers a warm biscuit.)", "", 5,
          [A("flurry", -0.5, 0.0, "happy", 20), A("cinder", 0.5, 0.0, "happy", -20)], focus=[13.0, 9.6],
          actors_rel=True),
        P("E00.3", "guest_close", "♪  (a gentle song on one side, a gentle nap on the other)  ♪", "luna", 5,
          [A("luna", -0.6, 0.0, "happy"), A("whisp", 0.8, 0.0, "sleep", mask=True)], focus=[7.0, 9.6], actors_rel=True),
        P("E00.4", "fixture_close", "I knew I packed a spare.", "mallow", 5,
          [A("mallow", 0.9, 0.2, "happy", slippers=True), A("fern", -0.9, 0.2, "happy")],
          [{"kind": "slipper_flowerpot", "pos": [0.0, 0.0, 0.5]}, {"kind": "flower_crown", "pos": [0.0, 0.0, -0.4]}], focus=[21.0, 9.6], actors_rel=True),
        P("E00.5", "desk_close", "I think I understand the important part now.", "dot", 7,
          [A("dot", 3.0, 9.4, "happy", -30), NANA_DESK], [{"kind": "checklist", "pos": [3.4, 0.0, 9.9]}], sound="dot_paper"),
        P("E00.6", "lobby_group", "(The camera timer clicks too early. Everyone blinks.)", "gus", 7,
          [A("staff", 5.2, 10.4, "photo"), A("gus", 4.0, 11.2, "happy"), A("nana", 3.0, 9.4, "photo")],
          [{"kind": "camera", "pos": [4.6, 0.0, 12.4]}], sound="photo_shutter"),
        P("E00.7", "lobby_group", "There. Everybody fits.", "nana", 7,
          [A("staff", 5.2, 10.4, "photo"), A("gus", 4.0, 11.2, "photo"), A("nana", 3.0, 9.4, "photo"),
           A("mallow", 6.6, 9.4, "happy", slippers=True), A("flurry", 7.6, 9.2, "happy"), A("cinder", 8.6, 9.2, "happy")],
          [{"kind": "camera", "pos": [4.6, 0.0, 12.4]}], sound="photo_timer"),
        P("E00.8", "postcard_still", "Hearth & Hiccup — room for one more.", "", 6,
          [A("staff", 0.0, 0.6, "photo"), A("nana", -2.4, 0.0, "wave"), A("gus", 2.4, 0.6, "happy"),
           A("mallow", -1.6, -0.6, "happy", slippers=True), A("flurry", -0.6, -0.8, "happy"), A("cinder", 0.4, -0.8, "happy"),
           A("whisp", 1.4, -0.8, "happy", mask=True), A("luna", 2.4, -0.6, "happy"), A("fern", -2.6, -0.8, "happy"),
           A("dot", 3.2, 0.0, "happy")],
          [{"kind": "paper_moon", "pos": [0.0, 0.0, -2.0]}], focus=[13.0, 9.4], actors_rel=True, sting="sting_results"),
        P("E00.9", "wide_hotel", "(A new traveller's suitcase arrives at the door. The bell hiccups. Gus answers.)", "", 5,
          [A("gus", -0.8, 9.6, "wave", 90)], [{"kind": "tiny_suitcase", "pos": [-1.6, 0.0, 9.6]}], sound="bell_hiccup"),
        P("E00.10", "festival_wide", "Thank you for making room.", "", 8,
          [A("staff", 17.0, 10.2, "happy"), A("nana", 15.4, 9.4, "happy"), A("gus", 18.8, 10.6, "happy"), A("dot", 16.2, 10.8, "happy")],
          [{"kind": "paper_moon", "pos": [17.0, 0.0, 8.6]}, {"kind": "thank_you_garland", "pos": [17.0, 0.0, 8.2]}]),
    ],
}

# Level beats: (pre camera, focus, layout, speaker, caption, actors, props)
#              (mid trigger, mid fallback hotel s, mid speaker, mid caption)
#              (post speaker, postcard caption, guests on the card, prop)
LEVELS = {
    "L01": (("desk_close", None, "One welcome at a time.", "nana", [NANA_DESK, A("mallow", 3.6, 9.4, "wave")]),
            ("first_welcome", 0, "mallow", "They fit both of my feet!"),
            ("nana", "That is a very good beginning.", ["mallow"], "welcome_pennant")),
    "L02": (("desk_close", None, "A little something for every stay.", "nana", [NANA_DESK]),
            ("first_delivery", 75, "gus", "(Gus presents his towel-cape with a proud squeak.)"),
            ("nana", "Help can come from either direction.", ["mallow"], None)),
    "L03": (("lobby_group", None, "Every goodbye makes room for another hello.", "nana", [A("nana", 3.0, 9.4, "work")]),
            ("first_laundry", 0, "gus", "(Gus leans beside the folded sheet and matches its shape exactly.)"),
            ("nana", "Look what you made ready.", ["mallow"], "sheet_sculpture")),
    "L04": (("lobby_group", None, "A little help at the other end?", "nana", [A("nana", 3.0, 9.4, "wave"), LOBBY_STAFF]),
            ("trunk_delivered", 0, "gus", "(The tiny suitcase unfolds one tiny handle, proudly.)"),
            ("nana", "Big jobs get smaller when we share them.", ["mallow"], "mini_trunk")),
    "L05": (("guest_close", [2.6, 9.6], "Somewhere just a little frosty?", "flurry", [A("flurry", 2.6, 9.6, "happy")]),
            ("time", 90, "flurry", "(A frozen ornament goes “ting…k.” Flurry gives it an apologetic wave.)"),
            ("dot", "Cool. That is one answer.", ["yeti", "slime"], None)),
    "L06": (("desk_close", None, "Different rooms. Same welcome.", "nana", [NANA_DESK, A("cinder", 3.4, 9.1, "idle"), A("flurry", 4.4, 9.1, "idle")]),
            ("first_steam", 115, "", "(A sock-shaped cloud drifts past both luggage tags.)"),
            ("dot", "(Dot adds a second column to her checklist.)", ["dragon", "yeti"], "split_lamp")),
    "L07": (("fixture_close", [8.0, 8.0], "Follow the little arrows.", "nana", [A("nana", 9.4, 8.9, "wave", -35)]),
            ("first_vent", 0, "dot", "(Dot solemnly fans the nearest pipe… then notices the real lever.)"),
            ("dot", "A useful improvement.", ["dragon", "yeti"], "fan")),
    "L08": (("lobby_group", None, "We can make this work.", "nana", [A("nana", 3.0, 9.4, "idle")]),
            ("recovery", 150, "gus", "(Gus shows off his static-fluffed towel eyebrows.)"),
            ("nana", "Cinder dries the scarf while Flurry cools the drinks.", ["dragon", "yeti", "slime"], None)),
    "L09": (("guest_close", [2.6, 9.6], "A quiet corner, if you have one.", "whisp", [A("whisp", 2.6, 9.6, "idle")]),
            ("time", 95, "whisp", "(Whisp's sheet eyebrows rise… then settle as the note fades.)"),
            ("nana", "Whisp naps under a moon mask. A towel bow hangs on the hook.", ["ghost", "slime"], None)),
    "L10": (("lobby_group", None, "Both belong on the guest list.", "nana", [A("nana", 3.0, 9.4, "idle"), A("luna", 4.4, 9.2, "happy"), A("whisp", 5.6, 9.2, "idle")]),
            ("quiet_howl", 0, "luna", "(Luna smiles proudly at the tiny note and mouths “perfect.”)"),
            ("nana", "A big note and a little moon hang on the same welcome sign.", ["moonwolf", "ghost"], "fabric_stage")),
    "L11": (("fixture_close", [8.0, 8.0], "Different little problems. Different little helpers.", "nana", [A("nana", 9.4, 8.9, "wave", -35)]),
            ("time", 140, "dot", "(Dot checks the correct symbol before touching the switch.)"),
            ("dot", "My checklist has pictures now.", ["moonwolf", "ghost", "slime"], None)),
    "L12": (("lobby_group", None, "A small rehearsal? … A considerate one.", "luna", [A("luna", 4.0, 9.4, "happy"), A("nana", 2.6, 9.2, "idle")]),
            ("time", 180, "luna", "(Three towel puppets bow at three different times. Luna loves it.)"),
            ("nana", "A curtain-framed group photo.", ["moonwolf", "ghost", "dragon"], "towel_puppet")),
    "L13": (("guest_close", [2.6, 9.6], "Somewhere with a little moisture?", "fern", [A("fern", 2.6, 9.6, "happy")]),
            ("first_watering", 0, "fern", "(One leaf gives a tiny thumbs-up.)"),
            ("nana", "One bright new blossom.", ["sprout"], "flowerpot_trio")),
    "L14": (("fixture_close", [20.0, 10.0], "A little warm, a little cool, a little water.", "nana", [A("nana", 21.4, 10.6, "wave", -35)]),
            ("first_steam", 105, "fern", "(Fern offers the watering-can-shaped cloud a tiny flower.)"),
            ("nana", "Warm and cool cups beside a thriving potted plant.", ["sprout", "dragon", "yeti"], None)),
    "L15": (("lobby_group", None, "Many hands make light puddles.", "nana", [A("nana", 3.0, 9.4, "carry")]),
            ("first_shared", 150, "mallow", "(Two mop heads leave a heart-shaped dry patch.)"),
            ("nana", "Mop handles form a little arch over a perfectly ordinary dry floor.", ["slime", "sprout"], None)),
    "L16": (("wide_hotel", None, "We have room to make something lovely.", "nana", [A("nana", 13.0, 9.4, "idle")]),
            ("three_cozy", 210, "gus", "(A flower crown lands on Gus's handle.)"),
            ("nana", "The indoor garden is ready.", ["sprout", "slime", "dragon", "yeti", "moonwolf", "ghost"], "flower_crown")),
    "L17": (("wide_hotel", None, "There is usually another way to help.", "nana", [A("nana", 13.0, 10.4, "wave")]),
            ("shutter_closed", 60, "gus", "(Gus simply walks the lower route and politely waves.)"),
            ("nana", "Two arrows curve around the divider and meet at a heart.", ["dragon", "ghost", "sprout"], None)),
    "L18": (("high_close", [24.0, 11.0], "A little lift, when you need one.", "nana", [A("nana", 22.6, 10.6, "wave", 35)]),
            ("first_lift", 0, "gus", "(Gus rides the lift facing the wrong way and comes back with a sightseeing postcard.)"),
            ("nana", "Two lift symbols frame a towel with a travel sticker.", ["dragon", "moonwolf", "sprout"], None)),
    "L19": (("room_door", [14.0, 7.6], "Sometimes a new corner helps.", "nana", [A("nana", 15.2, 8.7, "wave", -30)]),
            ("first_relocation", 0, "", "(The moving guest pauses to admire the same hallway from a new angle.)"),
            ("nana", "One guest points between two windows with equal delight.", ["dragon", "yeti", "ghost"], None)),
    "L20": (("wide_hotel", None, "Another job with two good ends.", "nana", [A("nana", 3.0, 10.6, "wave")]),
            ("second_trunk", 0, "dot", "(The tiny instruction card unfurls into an unexpectedly long ribbon: “This way up.”)"),
            ("nana", "We hung the paper moon.", ["dragon", "moonwolf", "sprout"], "paper_moon")),
    "L21": (("festival_wide", None, "Let's make it easy to find the welcome.", "nana", [A("nana", 17.0, 9.6, "carry")]),
            ("first_parcel", 0, "gus", "(A background lantern briefly wears Gus's bellhop cap.)"),
            ("nana", "Three lit lanterns beneath the paper moon.", ["dragon", "ghost", "sprout"], "lantern")),
    "L22": (("lobby_group", None, "We have more helpers than we thought.", "nana", [A("nana", 3.0, 9.4, "happy"), A("cinder", 4.4, 9.2, "helper"), A("fern", 5.6, 9.2, "helper")]),
            ("two_helpers", 0, "dot", "(Dot offers to hold the clipboard. Gus hands her a towel instead. She beams.)"),
            ("nana", "Guests and staff each hold one small contribution to the festival.", ["dragon", "yeti", "slime", "sprout"], "thank_you_garland")),
    "L23": (("lobby_group", None, "A busy house can still be a kind house.", "nana", [A("nana", 3.0, 9.4, "idle"), A("dot", 4.2, 10.4, "idle")]),
            ("recovery", 180, "dot", "(The bell hiccups. Dot answers with an equally serious hiccup.)"),
            ("dot", "(Dot leaves the clipboard on a hook and joins the group.)", ["dragon", "yeti", "slime", "ghost", "moonwolf", "sprout"], "clipboard")),
    "L24": (("festival_wide", None, "One last welcome. Together.", "nana", [A("nana", 17.0, 9.6, "happy"), A("staff", 18.6, 10.4, "happy")]),
            ("time", 210, "", "(Guests begin a small, happy, in-place celebration.)"),
            ("nana", "Hearth & Hiccup — room for one more.", ["dragon", "yeti", "slime", "sprout", "ghost", "moonwolf"], "moon_stand")),
}

# Pre-shift set dressing: story props, or "item:<kind>" for gameplay items,
# placed in world tile coordinates [x, height, z] near the beat's actors.
def I(kind, x, z, rot=0, y=0.0, scale=None):
    d = {"kind": kind if kind in PROP_KINDS else "item:" + kind, "pos": [x, y, z], "rot": rot}
    if scale: d["scale"] = scale
    return d

PROP_KINDS = {"invitation", "checklist", "fan", "paper_moon", "lantern", "flower_crown", "tiny_suitcase",
              "camera", "travel_hat_warm", "travel_hat_cool", "clipboard", "towel_puppet", "umbrella",
              "slipper_flowerpot", "welcome_pennant", "sheet_sculpture", "split_lamp", "fabric_stage",
              "flowerpot_trio", "mini_trunk", "moon_stand", "thank_you_garland"}

PRE_PROPS = {
    "L01": [I("welcome_slime", 2.9, 9.9, 20), I("invitation", 2.3, 9.8, -15)],
    "L02": [I("towel", 2.4, 9.9, 10), I("towel", 2.8, 10.1, -25), I("snack", 3.2, 9.8)],
    "L03": [I("linen_dirty", 3.8, 9.9, 30), I("linen_clean", 2.2, 9.9, -10)],
    "L04": [I("festival_trunk", 5.6, 10.9, 90), I("tiny_suitcase", 4.2, 10.4, -20)],
    "L05": [I("travel_hat_cool", 3.3, 9.9, 15), I("welcome_yeti", 1.9, 9.9)],
    "L06": [I("travel_hat_warm", 3.4, 9.7, -10), I("travel_hat_cool", 4.4, 9.7, 10)],
    "L07": [I("fan", 10.1, 9.3, -30), I("checklist", 8.4, 9.2, 20)],
    "L08": [I("umbrella", 3.9, 9.8, 25), I("breezer", 2.2, 10.0)],
    "L09": [I("welcome_ghost", 3.3, 9.9, 10)],
    "L10": [I("curtain_roll", 5.0, 9.9, 80), I("welcome_moonwolf", 3.8, 9.9)],
    "L11": [I("curtain_roll", 10.2, 9.3, 70), I("checklist", 8.4, 9.2, -10)],
    "L12": [I("fabric_stage", 5.4, 9.0), I("towel_puppet", 4.6, 9.9, -15)],
    "L13": [I("watering_can", 3.3, 9.9, -30), I("slipper_flowerpot", 1.9, 9.8)],
    "L14": [I("watering_can", 22.2, 11.0, 30), I("breezer", 20.4, 10.9)],
    "L15": [I("mop", 3.8, 9.8, 60), I("mop", 4.3, 10.2, 20)],
    "L16": [I("flowerpot_trio", 14.0, 9.2), I("flower_crown", 12.2, 9.6)],
    "L17": [I("welcome_pennant", 14.0, 10.6), I("checklist", 12.2, 10.8, 15)],
    "L18": [I("towel", 24.0, 11.0, 20), I("snack", 23.3, 11.3)],
    "L19": [I("move_ticket", 14.5, 8.9, -10)],
    "L20": [I("festival_trunk", 5.0, 10.4, 90), I("festival_trunk", 6.8, 11.2, 80), I("clipboard", 3.9, 10.9)],
    "L21": [I("lantern", 16.0, 9.2), I("lantern", 18.0, 9.2), I("festival_parcel", 17.8, 10.2, 15)],
    "L22": [I("thank_you_garland", 4.6, 8.7)],
    "L23": [I("clipboard", 4.8, 10.6, -20), I("towel", 2.4, 10.0)],
    "L24": [I("paper_moon", 17.0, 8.4), I("lantern", 15.6, 9.1), I("lantern", 19.4, 9.1), I("moon_stand", 20.0, 10.2)],
}
