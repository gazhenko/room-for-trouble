# Completion matrix

This matrix lists every requirement in `docs/DESIGN_BRIEF.md` together with the evidence that
it is met. Evidence means a test, a script, a document, or something you can check yourself in
the build. Where a requirement depends on hardware, people or services that were not
available, the row says so plainly rather than marking it done.

**Status legend**

| Mark | Meaning |
|---|---|
| ✅ | Implemented and verified by the cited evidence |
| 🟡 | Implemented; verified only partly (the limit is stated in the row) |
| ⛔ | Blocked on something outside this environment (hardware, people, a host, or credentials) |
| ↔ | A deliberate departure from the brief, recorded in `DECISIONS.md` |

Every evidence path is relative to the repository root. To produce the cited run outputs
again, run `tools/build.sh`. It writes `build/test_report.txt`, `build/ui_report.txt`,
`build/net_*.txt`, `build/SHA256SUMS` and `build/ARTIFACTS.json`.

## §25 Definition of done

| # | Requirement | Status | Evidence / limit |
|---|---|---|---|
| 1 | Complete local game runs from exported Windows and Linux packages | 🟡 | **Linux:** the exported game passes the shipping smoke test in a clean x86-64 container (`tools/smoke_linux.sh`), plus the gamepad test with four kernel-level controllers (`tools/smoke_linux_gamepads.sh`). **Windows:** the exported `.exe` passes the smoke test under Wine with both Forward+ (Vulkan) and Compatibility (`tools/smoke_windows_wine.sh`), but ⛔ has not run on real Windows hardware. **macOS:** the ad-hoc-signed `.app` passes it on the M1 Pro, including online. All of these are run by `tools/verify_artifacts.sh`. |
| 2 | 1–4 seats with the required keyboard and controller arrangements | 🟡 | Per-device routing (`src/app/input_router.gd`), with two keyboard slots and any number of pads. **Four OS-level (uinput/evdev) gamepads**, mixed Xbox and DualShock, joined, moved independently, paused, unplugged and reclaimed on the exported Linux build (`tools/smoke_linux_gamepads.sh`). That test found and fixed a reclaim bug. UI01 covers menus and keyboard-only play. ⛔ No physical controller hardware was tested. |
| 3 | All 6 guest families have distinct comfort, quirk, helper and visual behaviour | ✅ | `src/sim/sim_guests.gd` (comfort test, quirk timers, `helper_preview`/`invoke_helper`). Models in `src/view/models/model_actors.gd`. `tests/test_env.gd` covers thermal, sound, moisture and director behaviour. The Playground can show each family on demand. Scrapbook → Guide lists each family's need, quirk and helper. |
| 4 | All 24 shifts, 6 layouts, 3 tutorials, chapter bridges, opening and ending | ✅ | `data/campaign_manifest.json`, `data/layouts/templates.json`, `data/tutorials/tutorials.json`, `data/story/*.json` (55 scenes). Checked by `tests/test_content.gd` (DATA01, story references) and `tests/test_tutorials.gd`. Every level finishes at 1–4 players (`docs/REFERENCE_RUNS.md`). |
| 5 | Every shift supports solo play, a soft wrap-up, and progress that does not depend on stars | ✅ | SOLO01 (`tests/test_rules.gd`, `tools/validate_manifest.py`). The soft wrap and Cozy Corner are covered by `tests/test_sim_core.gd::test_idle_shift_soft_wrap`. Progress at 0% is covered by `test_save02_idempotent_results` and `SaveService.apply_result`. |
| 6 | Tickets, requests, laundry, gifts, relocation, curtains, vents, moisture, lifts, shutter, trunks and parcels follow their contracts | ✅ | ITEM, WORK, ROOM, GUEST, ENV and DIR tests (§24.1 table). Lifts, shutter, trunks and parcels are exercised by the L17–L24 reference runs. The trunk solo drag is covered by `test_solo01_one_player_moves_a_trunk`. |
| 7 | Handoffs, shared work and co-carry give visible, useful cooperation without duplicate resources | ✅ | ITEM01 and WORK01 (`tests/test_items.gd`); the targeting change is in T-001 (`docs/TUNING_LOG.md`); co-carry is covered by the trunk tests; the useful-handoff and shared-work ribbons are scored in `SimScore`. |
| 8 | Private online rooms through a real WSS endpoint, with mixed local/remote seats and reconnect | ✅ | **Internet:** e2e passed through a public Cloudflare WSS endpoint with real TLS (`tests/net/run_tunnel.sh`, temporary, closed afterwards). Also covered: WSS through the Caddy TLS stack, mixed 2+1+1 seats (`run_quad.sh`), reconnect (NET02), restart (NET04) and a lossy 100 ms link (`run_netem.sh`). A permanent public host is the owner's deployment choice (`OPERATIONS.md`). |
| 9 | Offline play, active-shift suspension, save recovery and idempotent progress are verified | ✅ | Local play never touches the network. Suspension round-trips through the profile JSON (`test_save_suspended_shift_round_trips_through_profile_json`, which caught and fixed a key-type bug). SAVE01 fixtures cover truncated, tampered, v0 and write-failure saves. SAVE02 covers idempotent results. |
| 10 | Cozy/Family/Busy and individual accessibility settings work throughout menus and gameplay | 🟡 | `src/app/settings.gd` and the Settings screen (all §11.3 options; see the table below). UI01 walks every settings tab. Pace changes are covered by the reference runs (Family and Busy). ⛔ There has been no human check with assistive needs. |
| 11 | Hub, 24 postcards, 8 cosmetic sets, 8 modifiers, Quick Shift and Playground are complete | ✅ | `src/app/hub_screen.gd`, Scrapbook, Wardrobe, `data/cosmetics.json` (default plus 8 sets), `data/modifiers.json` (8), Quick Shift and Playground. Screens are traversed by UI01 and shown in `build/shots/tour*`. The Playground step is in the smoke test. |
| 12 | Final art, audio, story and UI are coherent, readable and free of debug stand-ins | 🟡 | All assets are final per `docs/ASSET_REGISTER.md`. A screenshot review was done at 720p (`tools/dev/ui_tour.tscn`). Debug tools appear only with `--dev`. ⛔ The "readable at handheld scale" check was not done on a Steam Deck. |
| 13 | Performance and hardware claims have actual measurement records | 🟡 | `docs/PERFORMANCE.md` has measurements on the M1 Pro, including the floor draw-call budget: 154 on Standard and 131 on Low against 150. Other hardware targets are marked unmeasured. |
| 14 | Automated tests, route/content checks, exports and family-playtest observations are documented | 🟡 | `BUILD.md`, `docs/REFERENCE_RUNS.md` and this matrix. ⛔ No family playtests have been run (`docs/PLAYTEST_REPORT.md`). |
| 15 | Build, operation, licence and asset-provenance documents and checksums are included | ✅ | `README.md`, `BUILD.md`, `OPERATIONS.md`, `DECISIONS.md`, `KNOWN_ISSUES.md`, `CHANGELOG.md`, `CREDITS.md`, `THIRD_PARTY_NOTICES.md`, `docs/ASSET_REGISTER.md`. `tools/build.sh` writes `SHA256SUMS` and `ARTIFACTS.json`. |
| 16 | Unavailable credentials, platform access and untested hardware are identified precisely | ✅ | `KNOWN_ISSUES.md` § "Not verified on real hardware or services". |

## §0.3 Required repository deliverables

| Deliverable | Status | Where |
|---|---|---|
| Runnable Godot project with all authored sources and editable data | ✅ | `project.godot`, `src/`, `data/`, `tools/content/`, `tools/audio/`, `data/art/icons/` |
| Exported Windows and Linux builds, a dedicated server build, checksums | 🟡 | Produced by `tools/build.sh` into `build/` (gitignored). The Windows build is untested (see §25 #1). |
| README, BUILD, OPERATIONS, DECISIONS, KNOWN_ISSUES, CHANGELOG, CREDITS, THIRD_PARTY_NOTICES | ✅ | repository root |
| Automated simulation, content and network checks | ✅ | `tests/`, `tools/validate_*` |
| Short manual family-playtest report | ⛔ | `docs/PLAYTEST_REPORT.md` gives the procedure and states that no sessions have been run |
| Asset register | ✅ | `docs/ASSET_REGISTER.md`, `assets/export/audio/REGISTER.md` |
| Save migration fixtures | ✅ | `tests/fixtures/saves/` (v1 valid, truncated, tampered, v0), tested by `tests/test_save.gd` |
| Campaign manifest, localization source, editable storyboard resources | ✅ | `data/campaign_manifest.json`, `tools/content/strings_en.py`, `tools/content/story_src.py` → `data/story/*.json` |
| Truthful completion matrix | ✅ | this file |

## §0.1 Binding decisions

| Decision | Status | Notes |
|---|---|---|
| Cooperative, friendly, funny | ✅ | No fail states, no blame ledger, the Cozy Corner, comic quirks |
| 1–4 players: solo, couch, private online with mixed seats | ✅ / 🟡 | See §25 #2 and #8 |
| Godot 4.7.2 stable, standard edition, typed GDScript, pinned templates | ✅ | `tools/build.sh` checks the version; template checksums verified (`BUILD.md`) |
| Stylised low-poly 3D, **fixed elevated orthographic camera**, whole floor visible | ↔ | D1/D2: an Overcooked-style fixed perspective camera with a pixel-art render, at the owner's request. The whole floor is always visible. |
| Windows and Linux x86-64, Steam Deck profile, macOS preset | 🟡 / ⛔ | The presets and exports exist. A Deck glyph family and an 800p layout are present but ⛔ untested on a Deck. macOS is a candidate build (unsigned). |
| Full gamepad and keyboard operation; 1 keyboard + 3 pads or 4 pads; optional shared keyboard | 🟡 | Implemented. A shared-keyboard caveat is shown in Settings → Controls. ⛔ Not tested with physical pads. |
| Authoritative headless Godot service over WSS with private codes | ✅ | `src/net/`, `server/deploy/` |
| Mandatory content (3 tutorials, 24 shifts, 6 templates, 6 families, 4 staff, story, playground, Quick Shift, 8 modifiers, 24 postcards, 8 cosmetic sets) | ✅ | See §25 #4 and #11 |
| Cozy / Family / Busy, with assists separate from team pressure | ✅ | Settings → Gameplay (pace) and per-seat assists |
| Narrative: the Moonlight Welcome festival, ending in celebration | ✅ | O00, B01–B05, E00 |

## §24.1 Automated system and content checks

| ID | Required result | Status | Evidence |
|---|---|---|---|
| DATA01 | 24 unique sequential levels, 6×4, 3 waves, known references | ✅ | `tests/test_content.gd::test_data01_manifest`, `tools/validate_manifest.py` |
| DATA02 | Valid expansion for 1–4 humans and every modifier, with the final reserve | ✅ | `test_data02_expansion_all_counts`, `validate_manifest.py` |
| DATA03 | Ribbon targets within their upper bounds | ✅ | `tests/test_rules.gd::test_data03_ribbon_targets_within_upper_bounds`, `validate_manifest.py` |
| MAP01 | Routes reachable in every floor, shutter and mirror state | ✅ | `test_map01_routes_reachable` |
| MAP02 | No target through a wall; usable anchor points | ✅ | `test_map02_fixtures_have_access` |
| ITEM01 | One owner under simultaneous commands | ✅ | `tests/test_items.gd::test_item01_simultaneous_pickup_one_owner` |
| ITEM02 | A full queue preserves the held object | ✅ | `test_item02_hamper_full_keeps_bundle` |
| ITEM03 | Unique items return to their dock or pedestal | ✅ | `test_item03_ticket_returns_to_pedestal` |
| WORK01 | Shared rate ≤1.6×, a single completion | ✅ | `test_work01_shared_rate_and_single_commit` |
| ROOM01 | Admission and move races keep one guest per room | ✅ | `test_room01_move_room_preserves_history` |
| ROOM02 | Relocating after a request or helper gives no reset, duplication or extra credit | ✅ | `tests/test_rules.gd::test_room02_relocate_after_request_and_helper` |
| GUEST01 | Same-tick delivery counts, with half credit when late | ✅ | `test_guest01_same_tick_delivery_counts`, `tests/test_score.gd` |
| GUEST02 | Running out of patience leads to the Cozy Corner, never a failure | ✅ | `test_guest02_timeout_goes_to_cozy_corner` |
| ENV01 | Thermal conservation and bounds | ✅ | `tests/test_env.gd::test_env01_*` |
| ENV02 | Curtains and the one-hop acoustic graph | ✅ | `test_env02_curtain_attenuation_worked_example` |
| ENV03 | Tray, overflow, caps | ✅ | `test_env03_moisture_tray_and_overflow` |
| DIR01 | Incident and cooldown caps hold | ✅ | `test_dir01_incident_caps`; peak overlap ≤2 across 126 runs |
| SCORE01 | 100% for perfect play; exact star boundaries | ✅ | `tests/test_score.gd::test_score01_*` |
| SCORE02 | Stable denominator, nothing negative, progress unlocks | ✅ | `test_score02_late_half_and_abandoned_zero`, `test_score_denominator_stable` |
| SOLO01 | Solo lessons and teaching pairs survive; no required two-human input | ✅ | `tests/test_rules.gd::test_solo01_*`, the solo reference runs |
| SAVE01 | Power cut, corrupt primary, migration | ✅ | `tests/test_save.gd::test_save01_*` (fixtures) |
| SAVE02 | Idempotent progress | ✅ | `test_save02_idempotent_results` |
| REPLAY01 | Same commands give the same hashes; the first divergence is identifiable | ✅ | `tests/test_rules.gd::test_replay01_*`, `src/sim/sim_replay.gd`, `tools/dev/replay.gd` |
| UI01 | Controller-only traversal and rebinding with no focus traps | ✅ | `tests/ui/ui_focus_test.tscn` (73 checks: every screen and settings tab, seat lobby, pause, rebind, keyboard-only menus, every card on screen at 175%). Also fixed a rebind bug where capture mutated the default bindings. |
| NET01 | Forged seat, wrong shift, bad sequence rejected | ✅ | `tests/test_save.gd::test_net01_protocol_rejects_bad_input`, `tests/net/run_e2e.sh`, `run_quad.sh` (attacks) |
| NET02 | Disconnect while holding, working or co-carrying releases safely; one owner after reconnect | ✅ | `tests/test_rules.gd::test_net02_*`, `run_e2e.sh` (reconnect with token) |
| NET03 | 4 seats, 2+1+1, no cross-room data, capacity rejection | ✅ | `tests/net/run_quad.sh` |
| NET04 | Restart and checkpoint restore; content mismatch refused | ✅ | `tests/net/run_restart.sh` (Compose restart); checkpoints with a different content hash are discarded (`Net._restore_checkpoints`); `hello` refuses a mismatched content hash |
| NET05 | Delayed traffic, loss, oversized payloads are resource-safe | ✅ | `tests/net/run_netem.sh`: the full e2e suite (create, join, play, forged seat, reconnect, shared result) against the exported Linux server behind a **100 ± 20 ms, 2%-loss** link (`tc netem`). `run_quad.sh` covers the flood, garbage and oversized cases, memory bounds and a health probe afterwards. `test_net05_stale_or_flooded_input_cannot_run_away` covers input from a silent client. |
| MOD01 | Mirror transforms are consistent | ✅ | `tests/test_content.gd::test_mod01_mirror_transforms`, MAP01 in mirror states |
| STORY01 | Skip and replay every scene; 0-star ending; no soft lock | ✅ | `test_story_refs_and_loc`, `test_tutorials_complete_with_assist`. Progress at 0 stars still unlocks (SCORE02). |

## §24.2 Gameplay reference-run matrix

| Requirement | Status | Evidence |
|---|---|---|
| Every level: solo Family with Gus, 2P and 4P Family, one Busy run | ✅ | `docs/REFERENCE_RUNS.md`: all 24 levels at 1/2/3/4 Family plus 2P Busy (126 runs, 0 unfinished) |
| Three-player coverage | 🟡 | Bot runs at 3 players ✅. Real three-player sessions ⛔. |
| Metrics per run: arrivals, admissions, abandons, latency, work/travel, comfort per room, incident overlap, resource waits, score, ribbons, early finish, recovery | ✅ | Columns in `docs/REFERENCE_RUNS.md`; raw data in `build/reference_runs.json` |
| Gold route without Quick Step or helpers; solo has no co-carry requirement | ✅ | The bot never uses Quick Step, helpers or co-carry |
| One deliberately imperfect run per chapter | ✅ | Dropped ticket (L03), absent teammate (L07, L15), late start (L11, L19), two absent (L23). All finish with recoveries. |

## §24.3 Family usability sessions

| Requirement | Status | Evidence |
|---|---|---|
| Three or more sessions with the listed observations | ⛔ | Not conducted. The procedure and observation sheet are in `docs/PLAYTEST_REPORT.md`. |

## §24.4 Accessibility and hardware checks

| Check | Status | Evidence / limit |
|---|---|---|
| Keyboard-only | ✅ | Two keyboard slots with full bindings. UI01 drives the menus from keyboard slot 1 alone: S moves, E accepts, Left Shift backs out. Gameplay frames go through the same per-seat router as the pads. |
| 1 keyboard + 3 controllers; 4 controllers | 🟡 | Four kernel-level virtual pads on the exported Linux build (`tools/smoke_linux_gamepads.sh`). Keyboard plus pads share the same router (UI01 keyboard check). ⛔ Not with physical pads. |
| Mixed Xbox/PlayStation glyphs | ✅ | The virtual Xbox 360 and DualShock 4 pads were recognised by Godot's controller database. Seats showed `A` and `✕` respectively (`tools/smoke_linux_gamepads.sh`). |
| Controller unplug/replug and device reassignment | ✅ | Kernel-level pad unplugged mid-shift: its seat was marked missing, the staff safely released and the team paused. A *different* controller then pressed Carry and reclaimed the seat; that check found and fixed a reused-device-id bug. A same-model replug is auto-reassigned by GUID (`InputRouter._on_joy_changed`). |
| Custom remap | ✅ | UI01 rebind test. Fixed a shared-defaults bug. |
| UI scale 125/150/175% | ✅ | Settings → Vision (shared and per-seat), applied to the HUD and menus. At 175%, menus that would overflow a 720p screen shrink to fit, centred. The seat lobby and the HUD arrival strip adapt, and seat tags never cover prompts. UI01 checks that every menu card lies fully on screen at 175%. Screenshots at 175%, 125% and 1280×800 were reviewed. |
| Mono audio; all audio muted | ✅ | Settings → Hearing (mono and per-bus sliders); no audio-only objectives (warnings are icons and captions) |
| Reduced motion; high contrast | ✅ | Settings → Vision/Comfort; icons have a high-contrast variant |
| Steady Feet; toggle Work; Auto Catch | ✅ | Per-seat assists in the sim (`Settings.seat_assists`). Auto Catch is used in every test. |
| Cozy preset | ✅ | Pace setting; Cozy patience in `SimGuests` |
| Caption-only story | ✅ | Captions with speaker names; voices are non-verbal babble |
| 720p and 800p | 🟡 | UI tour and autoplay at 1280×720 and 1280×800 on macOS. ⛔ Not checked on a Deck screen. |
| Steam Deck suspend/resume and focus changes | ⛔ | No device |
| Window/fullscreen, alt-tab, laptop sleep | 🟡 | Fullscreen toggle in Settings. The sim uses fixed ticks and never wall time, so clock changes cannot advance a stay. Sleep and alt-tab were not explicitly tested. |
| Save-write failure keeps the previous good save, with a clear message | ✅ | `test_save01_disk_write_failure_keeps_previous_save`; `ui.save.write_failed` |

## §24.5 Shipping smoke test

| Step | Status | Evidence |
|---|---|---|
| Launch → local play → seats | ✅ | `src/dev/smoke_test.gd` (title, main menu, seat) |
| Play T01 or skip → finish L01 → confirm save → restart → continue | ✅ | The smoke test plays L01 and checks completion, then reloads the profile from disk |
| Open Playground → demonstrate each family | 🟡 | The smoke test opens the Playground. Demonstrating each family is manual (Playground board). |
| Join a private online endpoint, hand off, reconnect, finish, both clients get progress | ✅ | `run_e2e.sh` (two real clients) and `--smoke-endpoint` room creation |
| Open credits/licences → exit cleanly | ✅ | The smoke test opens Credits; Credits → Licences shows the full texts; the process exits 0 |
| Repeat on an offline machine | ✅ | The Linux container smoke run has no network service for the game; local play needs none |
| Dedicated server without GPU, display or audio | ✅ | `tools/smoke_linux.sh` (headless server + probe in a container) |
| The package references no absolute development paths | ✅ | Self-contained exports (the PCK sits beside the executable, inside the `.app`, or embedded in the server). Only `res://` and `user://` paths are used. The Linux run in a clean container passes. |

## Design sections: feature inventory

| Brief § | Feature | Status | Where |
|---|---|---|---|
| 2 | Main navigation (Title → Play Together/Solo/Playground/Settings/Scrapbook/Credits; Couch/Online; Create/Join) | ✅ | `src/ui/screens/main_menu_screen.gd`, `online_screen.gd` |
| 2 | Untimed planning, 3-note countdown, planning restrictions | ✅ | `HotelSim` phases; `test_planning_to_active` |
| 3 | Staff (cosmetic only), hosts, guests | ✅ | `model_actors.gd`, `SimC.STAFF_IDS` |
| 4 | Story panels: captioned, replayable, skippable; opening, bridges, ending, beats, postcards | ✅ | `src/app/story_player.gd`, `data/story/`, Scrapbook → Stories |
| 5 | Guest journey and room journey | ✅ | `sim_guests.gd`, `sim_interact.gd` |
| 6 | Controls, motion constants, targeting priority, shared progress, handoffs, heavy objects, recovery guarantees | ✅ | `sim_move.gd`, `sim_interact.gd`, `sim_goals.gd`; ITEM and WORK tests |
| 7 | Rooms, items, stations, stock, Gus | ✅ | `sim_interact.gd`, `sim_gus.gd`, `model_stations.gd` |
| 8 | Guest state, family data, happiness and communication, family animations | ✅ | `data/guests.json`, `sim_guests.gd`, `actor_rig.gd` |
| 9 | Thermal, sound, moisture, steam, power trip, interaction recipes, incident director | ✅ | `sim_env.gd`, `sim_director.gd`; ENV and DIR tests |
| 10 | Scaling, arrivals, difficulty, score, ribbons, soft failure | ✅ | `arrival_plan.gd`, `sim_score.gd`; DATA and SCORE tests |
| 11.1 | Screen composition (guest strip, clock, ribbons, seat cards, requests) | ✅ | `src/ui/hud.gd` |
| 11.2 | Pings (tap phrase and hold radial) | ✅ | `InputRouter` ping hold; `SimInteract.press_ping` |
| 11.3 | Accessibility options (motor, vision, hearing, cognitive, comfort, literacy) | ✅ | Settings tabs; `Settings.DEFAULTS`/`SEAT_DEFAULTS` |
| 11.4 | Lobby, per-device join, readiness, countdown, "Start with ready players" after 20 s without silently starting unready seats | ✅ | `seat_lobby.gd`, `online_screen.gd`, `Net._lobby`; `tests/net/run_ready.sh` |
| 11.4 | First-time cutscene skip agreed by all clients | ↔ | D9: online story beats play locally on each client; server readiness gates the shift |
| 11.5 | Local pause menu (Resume, Settings, Find Tools, Back to Lobby, Restart, Leave); online auto-pause, leader breaks, Gus/Wait/End options, reconnect reservation, lost-server Return to Hub | ✅ | `src/ui/pause_menu.gd`, `Net._lobby` (pause/resume/leader_option), `Session._on_net_lost` |
| 12 | Six templates, shutter, lift pads, route constraints | ✅ | `data/layouts/`; MAP and MOD tests |
| 13 | T01–T03 state machines, hint escalation, "Try it for me" | ✅ | `sim_tutorial.gd`, `tests/test_tutorials.gd` |
| 14 | 24 authored shifts | ✅ | manifest and story; reference runs |
| 15 | Event contract, comedy budget, bark library | ✅ | `sim_director.gd`, `strings_en.py` BARKS, `shift_screen.gd::_gag_tick` |
| 16 | Hub, unlock rules, 8 cosmetic sets, Quick Shift with 8 modifiers, Playground | ✅ | `hub_screen.gd`, `save_service.gd`, `wardrobe_screen.gd`, `quick_shift_screen.gd`, `playground_screen.gd` |
| 17 | Art direction, **camera**, animation API, asset budgets | ✅ / ↔ | The camera departs per D1/D2. Animation verbs are in `ActorRig.set_anim`. Triangle budgets are met for 75 of 76 models. The floor draw-call budget is met on the Low preset (131 ≤ 150; D28/D29). |
| 18 | Music inventory, sound inventory, mixing | ✅ | `assets/export/audio/`, `src/view/audio_director.gd` |
| 19.2–19.4 | Simulation separate from presentation, command order, integer time | ✅ | `src/sim/` (no scene-tree access) |
| 19.5 | Replays: record, headless re-run, first divergent tick, metrics export | ✅ | `SimReplay`, `tools/dev/replay.gd`, `tools/dev/reference_runs.gd` (metrics) |
| 19.5 | Developer overlay (nav grid, anchors, held owners, heat/noise/humidity, incident queue, arrivals, clocks, RTT, snapshot age, pending work, goal flags), step one tick or one hotel second, spawn events, available only with a dev flag | ✅ | `src/dev/dev_overlay.gd` (`-- --dev`, F1–F9) |
| 19.5 | Validate Level, Play Level as 1/2/3/4, Preview Wave, Preview Story Panel, Reset to Seed | ✅ | `src/dev/dev_tools_screen.gd` (main menu with `--dev`); Reset to Seed is F9 in the overlay |
| 19.6 | Performance targets | 🟡 | `docs/PERFORMANCE.md` (M1 Pro only; other targets unmeasured) |
| 20 | Topology, rooms and codes, message contract, sync, disconnects and checkpoints, safeguards, deployment files | ✅ | `src/net/`, `server/deploy/`, `OPERATIONS.md`; NET tests |
| 20.4 | Client prediction | ↔ | D8: interpolation only |
| 21 | Content registry, manifest rules, save schema, active-shift resume, localization and typography | ✅ | `content_registry.gd`, `save_service.gd`, `loc.gd`, fonts |
| 22 | Build commands, server invocation, deployment notes, package structure | ✅ | `BUILD.md`, `OPERATIONS.md`, `tools/build.sh` |
