# Known issues and unverified areas

The game is complete and was built and tested on one Apple Silicon Mac. This page lists what
is unfinished, unverified, or behaves imperfectly, so nothing is presented as more finished
than it is.

## Not verified on real hardware or services

| Area | Status | What remains |
|---|---|---|
| **Windows** | Exported (`build/windows/RoomForTrouble.exe`, x86-64, embedded PCK); never launched | Run `RoomForTrouble.exe -- --smoke-test` on a real Windows 10/11 PC, then play couch co-op with controllers. The `.exe` has no embedded icon (`modify_resources=false`: rcedit/Wine are not in the toolchain). |
| **Linux desktop** | Smoke test passes in a clean x86-64 Debian container under Xvfb, with Mesa llvmpipe and the Compatibility renderer (`tools/smoke_linux.sh`) | Test on a real Linux desktop GPU with the Forward+ renderer. |
| **Steam Deck** | Not tested | 800p layout, Deck controls and glyphs, suspend/resume and focus changes on the device (§24.4). |
| **macOS** | Fully played and smoke-tested from the exported `.app` on an M1 Pro | Unsigned and not notarized, so Gatekeeper warns on first launch (right-click → Open). Signing and notarization need the owner's Apple Developer credentials. |
| **Physical controllers** | No controller was connected during development. Controller behaviour was exercised with synthetic joypad events (UI01 traversal, seat lobby, rebind, pause), and the device-routing code is unit-tested. | Test the §24.4 matrix with real hardware: one keyboard plus three pads, four pads, mixed Xbox/PlayStation glyphs, unplug/replug, reassignment after reconnect, rumble. |
| **Public online endpoint** | The service, Docker image and Caddy TLS stack work locally, including `wss://` through Caddy with a local CA, restart recovery and abuse handling | Deploy to a real host and domain (owner decision), then run `tests/net/run_e2e.sh wss://<domain>/game` across the internet. There has been no long-running soak or load test, and no test under real packet loss or latency. Capacity figures in `OPERATIONS.md` are estimates. |
| **Family playtests** | **None conducted** | See `docs/PLAYTEST_REPORT.md` for the procedure. Balance and "is it fun" are unvalidated with people. Reference runs come from a scripted bot. |

## Known imperfections

- **Draw calls exceed the 150-call budget in big scenes.** On L24 with 4 players there are
  up to about 620 draw calls. On the M1 Pro, frame time stays around 5–6 ms at 720p (see
  `docs/PERFORMANCE.md`). Low-end and integrated GPUs, and the Steam Deck, are unmeasured.
  The procedural meshes are cached and shared, but stations are not yet merged or
  multimesh-instanced.
- **Occasional frame-time spikes** of up to about 100 ms happen when a new mesh kind is
  first built (for example the first trunk or cloud in a session). Later instances reuse the
  cached mesh.
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
