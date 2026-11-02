# Known issues and unverified areas

The game is complete and was built and tested on one Apple Silicon Mac. This page lists what
is unfinished, unverified, or behaves imperfectly, so nothing is presented as more finished
than it is.

## Not verified on real hardware or services

| Area | Status | What remains |
|---|---|---|
| **Windows** | Exported (`RoomForTrouble.exe` plus `RoomForTrouble.pck`, x86-64). Under Wine (x86-64 Debian container, Mesa) the shipping smoke test **passes with both renderers**: Forward+ on Vulkan via lavapipe, and Compatibility on OpenGL (`tools/smoke_windows_wine.sh`). Some Forward+ runs crashed inside Wine's software-Vulkan stack at device creation, before any game code ran. They stopped once each run got its own output directory: Docker Desktop's file sharing was losing re-created bind mounts. The script still retries that case once. It has **never run on real Windows**. | Run `RoomForTrouble.exe -- --smoke-test` on a real Windows 10/11 PC and play couch co-op with controllers. The `.exe` has no embedded icon (`modify_resources=false`, because rcedit is not in the toolchain). |
| **Linux desktop** | Smoke test passes in a clean x86-64 Debian container under Xvfb, with Mesa llvmpipe and the Compatibility renderer (`tools/smoke_linux.sh`) | Test on a real Linux desktop GPU with the Forward+ renderer. |
| **Steam Deck** | Not tested | 800p layout, Deck controls and glyphs, suspend/resume and focus changes on the device (§24.4). |
| **macOS** | Fully played and smoke-tested from the exported `.app` on an M1 Pro, including online. The bundle is **ad-hoc signed** with hardened runtime: `codesign --verify --deep --strict` passes. | It is not notarized, so on a downloaded copy Gatekeeper asks the player to choose Open Anyway (System Settings → Privacy & Security). Notarization needs a paid Developer ID certificate; this machine has only an Apple Development identity. |
| **Physical controllers** | **No physical controller was available.** The exported Linux build was tested with **four kernel-level virtual gamepads** (uinput/evdev with udev; Xbox 360 and DualShock 4 identities, recognised by Godot's controller database) (`tools/smoke_linux_gamepads.sh`). That covers Carry-to-join, mixed glyph families, each stick moving only its own staff, Start/B, unplug (seat marked missing, team paused) and a different controller reclaiming the seat. Menu traversal and rebinding are covered by UI01. | Test the §24.4 matrix with real hardware: one keyboard plus three pads, four pads, rumble, Bluetooth reconnects, and Steam Input on a Deck. |
| **Public online endpoint** | **Internet play verified (2026-10-23):** the full two-client e2e suite passed against a public `wss://…trycloudflare.com` endpoint. That covers create, join by code, play, the forged-seat guard, reconnect with token and a shared result, over a real TLS certificate and internet path (`tests/net/run_tunnel.sh`, a temporary Cloudflare quick tunnel, shut down afterwards). Also verified: the Docker + Caddy TLS stack, restart recovery, abuse handling, and a 100 ± 20 ms, 2%-loss link (`tests/net/run_netem.sh`). | No permanent public host is deployed; that's the owner's choice of host and domain (`OPERATIONS.md`). There has been no long-running soak or multi-room load test. |
| **Family playtests** | **None conducted** | See `docs/PLAYTEST_REPORT.md` for the procedure. Balance and "is it fun" are unvalidated with people. Reference runs come from a scripted bot. |

## v2 (Overcooked-scale rebuild, 2.0.0-alpha)

- **All 24 shifts, the three tutorials, the hub, the Playground and every story scene run on
  the v2 floors** (13×13 four-room chapter 1, 19×13 six-room chapters 2–6, 19×14 split lobby for
  chapter 5). Balance comes from the scripted reference bot (`docs/REFERENCE_RUNS.md`), not from
  family playtests; expect tuning after the owner plays on the Deck (tips weight, request
  windows, chapter density).
- **Story scenes are mapped, not re-authored.** Actors and cameras are authored on the classic
  28×20 floor and staged onto the v2 floors at load (`StoryStaging`, D48): the framing scales with
  the bigger toys, groups keep their shape, and any hotel station between the camera and a face
  is hidden for that panel. Every beat passes the frame check (`ui_tour` CHECK lines), but the
  set behind a close-up is the compact hall, not the classic one: a desk-side chat shows the
  reception desk behind Nana rather than in front of her, and the lane's counter row can frame
  the bottom of a shot. The content validator warns when an actor would stand in a wall or a
  station footprint.
- **Classic templates P1–P6 remain in the data** only as the authoring frame for scenes and for
  the mirror test; nothing plays on them.
- **v1 replays and per-level bests are not comparable** with v2 (different floors, pacing and
  score); `SIM_VERSION` is 2.0.1 (2.0.0 added the floors, 2.0.1 the sprout water step and
  vent/helper tempering) and replays from other simulation versions are refused with a message.
- **The lift car is a view-side animation.** The simulation still teleports the item or rider
  after the transit time; the cage sinking and rising is derived from the lift state, so a
  player who steps onto the arriving pad early sees the car come up under their feet.
- **Walking share.** Even with instant take/put, roughly 70% of a job is still walking on the
  v2 floors (hands-on steps are 0.2–1.7 s); the warm/chill middle step is the lever that adds
  hands-on time without adding waiting.

## Known imperfections

- **Draw calls.** The busiest floor (L24, four players) peaks at 154 draw calls on Standard
  graphics and 131 on Low (the brief budgets 150 on the low preset), down from 622. That's
  after merging station bodies and baking each character into one skinned mesh. The HUD
  adds about 200 2D draws on top. Low-end and integrated GPUs and the Steam Deck are
  unmeasured.
- **Frame pacing has only been measured on one machine.** On the M1 Pro, final-build
  frame times never exceeded 10.8 ms (Forward+) or 15.8 ms (Compatibility) across seven
  runs; see `docs/PERFORMANCE.md`.
- **The bot scores lower with 2–4 players than solo** in later chapters, because of simple
  bot coordination such as two bots chasing the same job. This reflects the driver, not
  necessarily human play; see `docs/REFERENCE_RUNS.md`.
- **Online clients do not predict their own movement.** They interpolate about 100 ms
  behind, so at high latency your own avatar feels slightly delayed. Local couch play is
  unaffected.
- **No spectators.** A player who joins an online room mid-shift waits for the next shift.
- **English only.** All text goes through the localization table (`data/localization/en.json`),
  but no other language ships.
- **Read-aloud uses the operating system's text-to-speech voices.** Where no English voice
  is installed, it is silently unavailable.
- **The Compatibility renderer** (older GPUs, the Linux container) has no screen-space
  outline pass. The toon shading and pixel upscale still apply.
- **The Windows and Linux builds are x86-64 only.** There are no ARM64 Windows or Linux
  packages.

## Reporting a problem

- The last local campaign or Quick Shift is saved as a deterministic replay in
  `user://replays/last_shift.json`. `tools/dev/replay.gd` replays it and reports the first
  divergent checkpoint.
- Save files are in `user://profiles/`, with `.bak1`–`.bak3` backups.
