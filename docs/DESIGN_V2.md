# Room for Trouble v2 — the Overcooked-scale rebuild

*Decisive design for the rebuild the owner chose (option B of the 2026-10-31 review).
This replaces the parts of `docs/DESIGN_BRIEF.md` listed in §10; everything else in the
brief still applies. Milestone 1 implements it for chapter 1; milestone 2 converts the rest.*

## 1. What v2 is for

Room for Trouble keeps its hotel, its cast, its six systems and its family rule (**a shift never
fails**), but the moment-to-moment game becomes Overcooked-density co-op: a small floor you can
read at a glance on a 7" screen, big toy-like characters, instant pick-up and put-down, a real
dash, orders you can see with timers you can feel, 2–3 step chains that make teammates useful to
each other, and hazards you can see in the lane. The v1 game measured 75–85% of each job as
walking and a 28-px avatar at 1280×800; v2 targets walking under half of a job and a staffer at
least 60 px tall.

## 2. Floor envelope

- **Chapter 1: 13×13 tiles, four rooms** (`data/layouts/base_v2_small.json`, template `P1v2`).
  Rooms are 5×3 inside; the hall is 3 rows: the north edge holds reception, the ticket pedestals
  and a mop dock; the middle row is the free lane; the south edge is the **counter row** (laundry,
  pass counter, stock, kiosk, festival stand). Doors sit on the rows above and below the hall.
- **Chapters 2–6: 19×13 tiles, six rooms** (milestone 2): the same hall grammar with a third
  room on each side; thermal gates on the wall columns, lift pads at the lane ends, the divider
  and shutter in the middle column.
- A floor only carries the fixtures its systems use. Missing fixtures are legal everywhere in
  code (view, sim candidates, bot).
- Walking budget: hall crossing ≤ 3.5 s at 3.6 m/s (chapter 1: 3.1 s); the mean one-way walk of
  the six common jobs ≤ 2.5 s (chapter 1: 2.3 s, was 3.8 s).

## 3. Camera and scale

- Fixed Overcooked-style perspective, pitch 44°, FOV 36°, fitted to the built floor plus 0.6 m
  with the top 10% and bottom 7% of the frame reserved for HUD. It never scrolls or rotates.
- `ACTOR_SCALE` 2.0: a staffer stands ~1.45 m on 1 m tiles and **65–70 px tall at 1280×800**
  (target ≥ 60 px; v1 was 28 px). Guests 70–100 px. Pixel stage unchanged (360-line render,
  integer upscale, toon bands, ink outline on every actor and prop).

## 4. The order card

Every guest is **one order card** on the rail at the top-left, from the moment they are announced
until they leave. A card shows the family portrait, the steps in order with the current step lit,
and one timer bar:

| Step | What the team does | Timer shown | Tip for speed |
|---|---|---|---|
| **Key** (check-in) | take the ticket from the pedestal, put it on a clean room's plaque | lobby patience, 45 s | +10 if placed with two thirds of the patience left (within 15 s) |
| **Gift** | choose the family at the kiosk, carry the gift to the room plinth | — (stay bar) | +5 if installed within 15 s of the guest entering |
| **Request ×n** | towel or snack from stock to the guest (later chapters: warmed, cooled, …) | 20 s window + 6 s late | +5 each if served in the first third of the window |
| **Stay → checkout** | nothing; the guest leaves a dirty bed and a mess | stay, 40 s (chapter 1) | — |

- A late step costs points, never the shift: a request served in the late window earns half; after
  it, nothing. A guest whose patience runs out walks to the **Cozy Corner** and the order is
  *missed* (its remaining points are lost, the card slides away with a sad line). No order ever
  blocks the next one.
- Tips are shown as "+N" rising where they were earned and totalled on the card.
- Requests the guest will make are known from arrival (`plan`), so the card shows every step up
  front; they open at 20% and 50% of the stay (one request: 30%).

## 5. Recipe chains

The frequent actions are instant (take, put, hand off: no movement lock; the dash is 1.6 m in
0.2 s with a 0.6 s cooldown). Depth comes from chains, not from waiting:

1. **Check-in**: ticket → clean room plaque. A room is clean only when its bed is *made* and the
   floor is mopped, which makes the linen cycle the gate on every order.
2. **The linen cycle (the "dirty plates" loop)**: checkout leaves a dirty bed → strip (1.2 s) →
   dirty bundle → hamper (8 s wash, queue of 8) → clean bundle on the shelf → make bed (1.5 s).
   Chapter 1 starts with 4/3/2/3 clean bundles (L01–L04) so from L02 on the loop runs out unless
   someone keeps the hamper fed. The emergency press (3 s) is the unlimited fallback.
3. **Gift**: kiosk cycles with Work → carry → plinth. Pre-placing the right gift before the guest
   arrives earns the welcome tip instantly on entry.
4. **Service**: towel rack / snack tin → guest. Later chapters add a middle step: a dragon's
   warmth or the radiator warms a towel for a dragon, the yeti (or an open cold vent) cools a
   snack for a yeti, the tap fills the watering can for a sprout. Each middle step is one
   station interaction in the lane, visible on the card as its own icon.
5. **The pass counter**: anything can be set down on a counter and taken from either side, so a
   runner and a room-maker split a chain without timing a handoff. Chapter 1 has one pass in the
   counter row; six-room floors get two (milestone 2).
6. **Festival trunk (L04, L21–L24)**: two handles, dragged at 1.4 m/s alone or carried at 3 m/s by
   two, along the lane to the goal pad.

## 6. Scoring

Per order, 100 base points: **check-in 30, gift 20, service 30 (split per request), comfort 20**
(comfortable seconds / stay — a bonus, no longer 40% of the result), plus tips up to +25.
Team percent = (base + tips) / (100 × scheduled guests), rounded, clamped to 100, so a fast team
can make up for a missed step. Stars stay at 55 / 75 / 90%. Ribbons are unchanged. The results
screen shows orders served / late / missed, the four components and the tips.

## 7. Hazards: the six systems as things in the lane

Each system stops being an invisible number and becomes something you can see and step around.
Milestone 2 implements these; the sim already has the state for all of them.

| System | v1 | v2 lane hazard |
|---|---|---|
| Thermal (ch. 2) | room heat drifts; vents equalise | a dragon's hiccup puts a **steam cloud** in the lane that slows you to 40% and hides what is in it until someone fans it with the Breezer; a yeti's sneeze leaves a **frost patch** you slide across (slide, no control, squeak). Vents are still the strategic fix. |
| Sound (ch. 3) | noise number per room | a moonwolf howl **startles** staff within two tiles: a 0.5 s stun and the held item drops at your feet (never lost). Curtains and room placement remain the fix. |
| Moisture (ch. 4) | humidity number | slime trails and overflowing trays leave **puddles** that slide you (exists; longer, funnier slide); a dry sprout wilts visibly. |
| Lifts (ch. 5) | item teleport pads | the lift is the **shortcut across the divider**: a conveyor you can ride, with a visible car. |
| Shutter (ch. 5) | timed closure | closes the shortcut on a faster cycle with a loud warning; the lower bypass is always open. |
| Festival (ch. 1, 6) | trunk goal | trunks **block the lane** until carried; parcels are installed at the stand. |

Incident caps per player count stay as in the brief; every hazard has a visible 4 s warning, a
readable effect and a one-step fix.

## 8. Arrival pacing

Levels carry a `pacing` block: `{first_s, gap_s, announce_s, reserve_s}`. The first guest arrives at
**4 s** (announced 3 s earlier, so the first card is on the rail at 1 s); then one every `gap_s`
(chapter 1: 12–18 s), compressed for bigger parties so the last arrival still leaves `reserve_s`
(patience 45 + walk 12 + stay 40 + 3 = 100 s) before the timer, and never faster than the rooms
can turn over: at least (stay + 8 s) / room cap between arrivals (solo, 2 rooms: 24 s), with
guests that no longer fit before the reserve dropped from the end. Shifts are shorter and
denser: L01 160 s, L02 180 s, L03 200 s, L04 210 s (were 270–300 s). Wave rosters still scale by
player count (×0.65 / 1.0 / 1.25 / 1.5); L03 and L04 grow to 8 guests at two players so the
laundry and trunk shifts carry real load.

## 9. Visual escalation by chapter

| Chapter | Floor | Light and palette | Dressing |
|---|---|---|---|
| 1 Welcome Lobby | 13×13, 4 rooms | late morning, cream and coral | bare: a welcome rug, a few plants |
| 2 Radiator Row | 19×13 | noon, warm floor glow near radiators, cool blue near open cold vents | brass pipes, radiators, steam |
| 3 Quiet Wing | 19×13 | dusk, plum and cream, warm lamps | note trims, curtains, paper moon |
| 4 Conservatory | 19×13 | green light through glass, humid haze | plants everywhere, drains, trays |
| 5 Split Lobby | 19×13 | evening, sky and walnut | divider, shutter, lift cars, travel stickers |
| 6 Grand Hall | 19×13 | night festival | lit lanterns, garlands, confetti, a crowd outside |

The sun colour and elevation, ambient tint and decor density are per template; each chapter adds
one hazard and one visible thing in the lane (pipes, curtains, drains, lift cars, trunks).

## 10. Cut or changed from `docs/DESIGN_BRIEF.md`

- **§12 envelope and room table**: 28×20 with 7×6 rooms → 13×13 (chapter 1) and 19×13 (chapters
  2–6) with 5×3 rooms; the hall is 3 rows with the counter row on the south edge; fixture
  coordinates come from each base file; a floor omits fixtures of systems it never uses; the
  renovation vignettes (rooms C/F fenced off in chapter 1) are cut — chapter 1 is a four-room
  hotel and the east wing opens in chapter 2.
- **§17.2 camera**: "fit the 28×20 floor" → fit the built floor; pitch 55° → 44°; HUD bands
  reserved; actors at 2.0 scale.
- **§6.2 Quick Step**: 0.8 m / 1 s cooldown → 1.6 m / 0.6 s.
- **§6.4 action timings**: take/place/handoff never block movement; dispense stock 1.0 → 0.33 s,
  gift 1.2 → 0.5 s, fulfil 0.4 → 0.2 s, assign 0.6 → 0.4 s.
- **§10.2 arrival scheduling**: three wave anchors with the first guest at 30 s → continuous flow
  with the first guest at 4 s; the 150 s reserve is replaced by each level's `reserve_s`.
- **§10.3/§8 timings (chapter 1)**: patience 50 → 45 s, request window 25 → 20 s, stays 70–75 →
  40 s, per level.
- **§10.4 score**: 20/20/20/40 → 30/20/30/20 plus tips; tips count toward the percent (a
  fast team can cover about one missed order in four).
- **Appendix A rosters**: L03 and L04 grow from 6 to 8 two-player guests.
- **§11.1 HUD**: incoming cards → the order rail; seat tags move from the head to the feet.
- **§12.2**: the festival stand leaves the hall lane (classic floor: (26,11)); new fixture kind
  `counters`.
- **§5.3 useful-job hints** stay, but the lit step on the order card is the primary guide.
- **Story sets and the hub** stay on the classic P1 set until milestone 2 re-stages them.

## 11. Milestone plan

- **M1 (done in this branch)**: chapter 1 and T01 on the 13×13 floor; order rail, per-order score
  with tips, continuous arrivals, linen scarcity, pass counter, instant take/put, real dash, juice,
  seat tags at the feet; evidence under `build/shots/fable/m1/`.
- **M2**: the 19×13 six-room base; chapters 2–6 and T02/T03 converted (manifest pacing, stays,
  linen per level); the six lane hazards; recipe middle steps (warm/cool/water); two counters;
  per-chapter light and dressing; story sets and the hub re-staged on the v2 floors; results
  postcard on the new set; reference-run matrix and docs regenerated; online/replay compatibility
  (content hash bumps; replays from v1 are not expected to load).
