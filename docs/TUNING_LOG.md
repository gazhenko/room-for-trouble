# Tuning log

The format follows §23.2. Each entry gives:
- the level or system
- the previous and new value
- the observed issue
- the affected player counts
- the invariants rechecked
- the evidence

The canonical source is changed first, and derived data is regenerated with
`python3 tools/build_content.py`.

**Baseline:** every number in `data/campaign_manifest.json` (Appendix A) and in the brief's
system tables (patience, request windows, stock caps, thermal and acoustic coefficients,
helper streaks, incident caps, player-count scale 0.65/1.0/1.25/1.5, room caps, the
150 s arrival reserve) is implemented **as written**. No campaign value has been retuned.
None of the issues found in reference runs traced back to a manifest number. All were
feedback, targeting, bot or presentation problems, so the brief's rule ("improve feedback
before increasing the timer") was applied.

Human playtests have not happened yet (`docs/PLAYTEST_REPORT.md`), so these values are
still the brief's initial proposals. They are not experimentally established.

---

### T-001 — Interaction targeting: staff handoff minimum distance

- **System:** `SimInteract._best` (targeting)
- **Previous:** a teammate anywhere inside reach was a valid handoff target, with the facing
  cone applied only beyond 0.45 m.
- **New:** teammates closer than **0.25 m** are never targets. The facing cone always
  applies to teammates.
- **Issue:** at 2–4 players, two overlapping staff could hand an item back and forth on
  consecutive Carry presses. It looked like the item "bounced".
- **Player counts:** 2, 3, 4.
- **Invariants rechecked:** ITEM01 (one owner), MAP02 (reachable anchors), handoff ribbons.
- **Evidence:** `tests/test_items.gd`, the reference runs at x2 and x4
  (`docs/REFERENCE_RUNS.md`), and the full suite passing.

### T-002 — P5 lift pad position

- **Layout:** P5 "Split Lobby" (`data/layouts/templates.json`)
- **Previous:** the brief's lift pad coordinate overlapped a ticket pedestal.
- **New:** lift pad at **(1, 10)**. The second pad stays at (24, 11).
- **Issue:** a fixture clash made one pedestal unusable while the lift was loading.
- **Player counts:** all (L17–L19).
- **Invariants rechecked:** MAP01 (flood fill, every shutter and mirror state), MAP02 and
  MOD01 (mirror transform).
- **Evidence:** `tests/test_content.gd` map tests and the L18/L19 reference runs.

### T-003 — Playground guests never time out

- **System:** `SimGuests` patience and checkout
- **Previous:** Playground guests used campaign patience and stay length.
- **New:** Playground guests (`play` flag) never lose patience or check out by themselves.
  The player waves goodbye.
- **Issue:** demonstrating a family on the Playground board ended with the guest walking
  off mid-demonstration.
- **Player counts:** all (Playground only; the campaign is unaffected).
- **Invariants rechecked:** GUEST02 (campaign timeouts are unchanged) and SCORE02.
- **Evidence:** `tests/test_items.gd::test_guest02_timeout_goes_to_cozy_corner` and the
  Playground smoke step in `src/dev/smoke_test.gd`.

### T-004 — Story and readability (presentation only)

- **Changes:**
  - Pre-shift beats are staged on the dressed hotel set, with per-level props.
  - Fixture and door camera presets were pulled back.
  - Shift-list blurbs replace designer "purpose" text.
  - A finished scene no longer clears the next scene's first caption.
- **Issue:** beats played on an empty shell with no context. Some fixture close-ups were
  filled by Nana. The first caption of a chained scene could vanish.
- **Player counts:** all.
- **Invariants rechecked:** STORY01 (`tests/test_content.gd`), with the cameras and props
  checked by `tools/validate_content.gd`.
- **Evidence:** screenshots from `tools/dev/ui_tour.tscn -- --only=pre_`.

---

## Observations to revisit with human playtests

From `docs/REFERENCE_RUNS.md` (bot only):

- **3–4 player scores are lower than solo and duo** in the festival chapter: L21 x3 59%,
  L24 x2 58%, L20 Busy x2 56%. As player count rises, the bots crowd the same jobs: idle
  time grows from about 19% solo to about 36% at 4 players. Travel dominates busy time at
  every count (59–74% of the total on average). Humans may coordinate better or worse. **Do not** change the
  manifest until real 3–4 player sessions show whether this is a bot artefact.
- **Single Cozy Corner arrivals at 3–4 players in early shifts** (for example L01 x3 and
  x4). The scaled roster adds a guest whose arrival overlaps with assignment travel. Check
  whether real players notice the pedestal queue.
- **Stock never ran out** in any bot run. Towel and snack restock rates may be generous.
  Watch whether families ever use the emergency press.
