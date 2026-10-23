# Building Room for Trouble

## Requirements

| Tool | Version | Notes |
|---|---|---|
| Godot Engine | **4.7.2-stable, standard (non-.NET)** | `godot --version` must print `4.7.2.stable…`. `tools/build.sh` refuses anything else. |
| Export templates | 4.7.2-stable | Installed by the editor, or unzip `Godot_v4.7.2-stable_export_templates.tpz` into the templates folder (macOS: `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`). Verify against the official `SHA512-SUMS.txt`. |
| Python | 3.11+ (stdlib only) | Content generation and manifest validation |
| Docker (optional) | 24+ with `buildx` | Linux smoke test, server image, online WSS tests |
| `zip`, `shasum` | any | Packaging and checksums |

The project has no third-party addons, GDExtensions or package downloads. All game assets
are committed.

On the development machine, Godot lives at `~/.local/opt/godot-4.7.2/Godot.app`, with a
`godot` launcher on `PATH`. Any 4.7.2 binary works; set `GODOT=/path/to/godot` to use a
different one.

## The repository command contract (§22.3)

```bash
godot --headless --editor --path . --import                         # import resources (first run)
python3 tools/validate_manifest.py data/campaign_manifest.json      # DATA01–03, SOLO01 bounds
godot --headless --path . --script res://tools/validate_content.gd  # references, cameras, props, icons, loc
godot --headless --path . --script res://tests/run_all.gd           # all headless suites (~5 min)
godot --headless --path . --export-release Windows build/windows/RoomForTrouble.exe
godot --headless --path . --export-release Linux build/linux/RoomForTrouble.x86_64
godot --headless --path . --export-release ServerLinux build/server/RoomForTroubleServer.x86_64
godot --headless --path . --export-release macOS build/macos/RoomForTrouble.zip   # candidate only
```

Required export presets are `Windows`, `Linux`, `ServerLinux` and `macOS` (in
`export_presets.cfg`, with no signing data).

## One-command release build

```bash
tools/build.sh                 # import, validate, all tests, UI01, online tests, 4 exports, zips, checksums
tools/build.sh --skip-tests    # exports and packaging only
tools/build.sh --only linux    # one platform: windows | linux | server | macos
```

Outputs:

- `build/<platform>/` holds the exported executable and its support files. Each package
  carries:
  - `README.md`, `BUILD.md`, `CREDITS.md`, `THIRD_PARTY_NOTICES.md` and `KNOWN_ISSUES.md`
  - the font licences in `licenses/`
  - `VERSION.txt` (version, git hash and engine)
- `build/RoomForTrouble-<version>-<platform>.zip`: one archive per desktop platform plus
  the server.
- `build/SHA256SUMS` and `build/ARTIFACTS.json`: the artifact manifest (path, bytes, sha256,
  version, git hash, engine).
- `build/test_report.txt`, `build/ui_report.txt`, `build/net_e2e.txt` and
  `build/net_quad.txt`: the evidence from that build.

A zero exit code from an export is **not** treated as success. Run the smoke tests below
against the actual artifacts.

## Smoke-testing artifacts (§24.5)

Every exported game accepts `--smoke-test` after Godot's `--` separator:

```bash
"build/macos/Room for Trouble.app/Contents/MacOS/Room for Trouble" -- --smoke-test --smoke-out=/tmp/rft_smoke   # macOS
build/linux/RoomForTrouble.x86_64 -- --smoke-test --smoke-out=/tmp/rft_smoke [--smoke-endpoint=ws://host:8080]
```

The smoke test does the following, then writes `smoke_report.json` and screenshots:
1. Boots to the title screen and opens the main menu.
2. Plays L01 with the reference driver at high speed, using a throwaway profile.
3. Checks the results screen and that completion is saved, then reloads the profile from
   disk.
4. Opens the Playground, Settings and Credits.
5. With `--smoke-endpoint`, also creates an online room.

The process exits `0` only if every step passed.

`tools/smoke_linux.sh` runs the Linux game in a clean `linux/amd64` Debian container, under
Xvfb with Mesa llvmpipe and the Compatibility renderer. It then starts the dedicated server
with no GPU, display or audio and runs its health probe.

`tools/smoke_windows_wine.sh` runs the exported Windows `.exe` the same way under Wine
(`RENDERER=vulkan` exercises Forward+ via Mesa lavapipe). This is a best-effort check
without a Windows machine; it does not replace testing on real Windows hardware.

`tools/smoke_linux_gamepads.sh` runs the Linux game in a privileged container with four
kernel-level virtual gamepads. `tools/gamepad_driver.py` creates them with
uinput/evdev, using Xbox 360 and DualShock 4 identities, and udev announces hotplug. The
in-game `--gamepad-test` harness (`src/dev/gamepad_test.gd`) checks:
- joining with Carry
- glyph families
- per-device stick routing
- Start/B
- unplug and reclaim

`tests/net/run_netem.sh` runs the online e2e suite against the exported Linux server behind
a delayed, lossy link (`tc netem`, 100 ± 20 ms and 2% loss by default).

`tests/net/run_tunnel.sh` runs it over the public internet through a temporary Cloudflare
quick tunnel (needs `cloudflared`; the tunnel closes when the script ends).

`tools/verify_artifacts.sh` runs all of the above (and the macOS smoke test on a Mac) and
writes `build/verify_summary.txt`.

## Installing on a Steam Deck over the network

1. On the build machine, render the library art once
   (`godot --path . res://tools/deck/steam_art.tscn`).
2. Run `tools/deck/serve.sh`. It packs `build/linux/` with the art and serves it on port
   8765.
3. On the Deck, in Desktop Mode → Konsole, run:

   ```sh
   curl -fsSL <build machine IP>:8765/deck | bash
   ```

The installer:
- verifies the checksum
- installs to `~/Games/RoomForTrouble`, keeping saves and any `endpoint.txt`
- adds a Desktop Mode menu entry
- adds the game to Steam as the non-Steam shortcut *Room for Trouble* with its library art

Run the same command again to update. Play from Game Mode, so that Steam Input presents the
Deck's controls as a gamepad.

`bash <(curl -fsSL <IP>:8765/ssh)` optionally authorises the build machine's SSH key and
starts `sshd` (it asks for the Deck's sudo password). After that, builds can be pushed with
`rsync` and logs read from `~/.local/share/godot/app_userdata/Room for Trouble/logs/`.

## Tests

| Command | What it covers |
|---|---|
| `godot --headless --path . --script res://tests/run_all.gd` | Headless suites `tests/test_*.gd`. Covers DATA, MAP, ITEM, WORK, ROOM, GUEST, ENV, DIR, SCORE, SOLO, SAVE, REPLAY, NET01, MOD and STORY, plus tutorials and the 1/2/4-player reference runs of all 24 shifts. Options: `-- --only=<suite or test>`, `-- --level=L06`, `-- --all-counts`. |
| `godot --headless --path . res://tests/ui/ui_focus_test.tscn` | UI01. A virtual controller walks every menu and settings tab, checks focus, B/back, the seat lobby, the pause menu and rebinding. |
| `tests/net/run_e2e.sh [wss://…]` | NET01–03. A real server and two clients: create, join, play, forged seat, reconnect, shared result. |
| `tests/net/run_quad.sh` | NET03 and NET05. 2+1+1 seats, full-room refusal, abusive client, probe after abuse. |
| `tests/net/run_restart.sh <wss-url> <project> <compose-file> <env>` | NET04. Restarts the Compose service mid-shift; the room resumes from its checkpoint. |
| `tools/check_scripts.sh` | Parse-checks every GDScript file. |
| `godot --headless --path . --script res://tools/dev/reference_runs.gd` | Regenerates `docs/REFERENCE_RUNS.md`: 126 bot runs with metrics. |
| `godot --headless --path . --script res://tools/dev/replay.gd -- [file]` | Replays a recorded shift and reports the first divergent checkpoint. |

## Editable sources and generators

| Source | Generator | Output |
|---|---|---|
| `tools/content/strings_en.py`, `tools/content/story_src.py`, `docs/DESIGN_BRIEF.md` (purposes and payoffs), `data/campaign_manifest.json` | `python3 tools/build_content.py` | `data/localization/en.json`, `data/story/*.json`, `data/levels/Lxx.json`, `data/credits.json` |
| `tools/audio/*.py` | `tools/audio/.venv/bin/python tools/audio/synth.py` (numpy + vorbis-tools; see `tools/audio/README.md`) | `assets/export/audio/**` and `audio_manifest.json` |
| `data/art/icons/*.txt` (text-pixel icons) | Loaded at runtime. `tools/icons/preview.py` renders sheets; `tools/icons/export_app_icon.py` writes the app icon. | `assets/export/icons/app_icon.png/.ico` |
| `src/view/models/*.gd` | Procedural meshes built at runtime | none |
| Engine licence data | `godot --headless --path . --script res://tools/gen_notices.gd` | `THIRD_PARTY_NOTICES.md` |
| Save fixtures | `godot --headless --path . --script res://tools/dev/make_save_fixtures.gd` | `tests/fixtures/saves/*.json` |

After editing a source, run its generator, then `validate_content.gd` and the tests. Commit
both the source and the generated files.

## Dev tools

These scenes need a window. Run them with `godot --path . <scene> -- <args>`.

- `res://tools/dev/autoplay.tscn -- --level=L24 --humans=4 --secs=120 --speed=2 --perf --size=1280x720`
  shows bot play with a perf report: frame time, draw calls, primitives and memory.
- `res://tools/dev/ui_tour.tscn -- --out=build/shots/tour [--only=name]` screenshots every
  front-end screen and story beat.
- `res://tools/shots/shot.tscn` is the gallery of models and icons.

## Reproducibility notes

- Engine and templates are pinned (`server/deploy/deploy.lock` records the digests used for
  the server image).
- Audio generation is byte-identical: fixed seeds and fixed Ogg stream serials.
- Content generation is deterministic: sorted keys and no timestamps.
- Every export is self-contained, with no hidden dependency on the developer folder. The
  Windows and Linux games ship `RoomForTrouble.pck` beside the executable (keep them
  together). macOS keeps it inside the `.app`, and the server embeds it. Exports include
  only `*.json`, the font licences and the icon sources. `tests/`, `tools/`, `docs/`,
  `server/` and `build/` are excluded.
- macOS exports are unsigned and not notarized. They are **candidate** builds until signed
  on real hardware with the owner's credentials. No credentials are kept in this repository.
- The Windows `.exe` is exported with `modify_resources=false`, so the icon is not embedded
  (that needs rcedit or Wine, which are not part of this toolchain).
