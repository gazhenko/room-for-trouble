# Performance measurements

All numbers on this page are actual measurements from one machine. Targets in §19.6 that
could not be measured are listed as **unmeasured**, never as met.

## Machine and method

- **Hardware:** MacBook Pro, Apple M1 Pro (8 performance + 2 efficiency cores), 16 GB RAM.
  macOS 26.4. Godot 4.7.2-stable, Metal.
- **Method:**
  `godot --path . res://tools/dev/autoplay.tscn -- --level=<L> --humans=<n> --secs=<s> --size=<WxH> --speed=1 --perf`
  - The real presentation (pixel stage, hotel view, HUD, audio) plays a shift at real-time
    speed. Every seat is driven by the reference bot.
  - Sampling starts after 3 s. The 3 frames after each screenshot are excluded, because the
    PNG save is synchronous.
  - The simulation cost per action tick is timed separately over 60 ticks.
- **Caveats:**
  - Frame intervals are paced by the macOS compositor (about 5.6 ms), so the average and
    p95 show headroom, not true GPU cost.
  - The reference bot's own planning (up to about 18 ms on some ticks) is included in these
    frames. Real players don't have that cost.
- **Raw logs:** `build/perf/f_*.log` and `build/perf_summary3.txt`.

## v2 floors (2026-11-01, 2.0.0-alpha, same machine and method)

The v2 rebuild renders a denser 19x13 six-room floor with characters at twice the scale,
per-item outlines and the per-chapter light. One measurement so far, the densest case:

| Scenario | Renderer / graphics | Frame avg | p95 | Max | Sim per tick | Floor DC (max) | Total DC (max) | Primitives | Static mem | VRAM |
|---|---|---|---|---|---|---|---|---|---|---|
| L24, 4 players, 1280x800, 120 s | Forward+ / Standard | 10.5 ms | 11.1 ms | 175 ms (one spike at 114 s; others <= 60 ms) | 0.85 ms | 175 | 404 | 86k | 115 MB | 79 MB |

- Floor draw calls on Standard (175) sit above the brief's 150 low-preset budget; the Low
  preset drops the shadow pass (about a sixth of the floor calls) and is expected near the
  v1 figure, **unmeasured** on v2 so far. The Deck is unmeasured.
- The spikes coincide with guest arrivals that build rigs and with the synchronous screenshot;
  average and p95 are unchanged from v1 (10.8 ms max then).
- Raw log: `build/shots/fable/m2/perf/L24_4p_perf.log`.

## Results (2026-10-23, final build)

"Floor DC" counts draw calls in the 3D floor viewport (colour plus shadow passes), which is
what the §17.4 budget covers. "Total DC" also includes the 2D HUD.

| Scenario | Renderer / graphics | Frame avg | p95 | Max | Sim per tick | Floor DC (max) | Total DC (max) | Primitives | Static mem | VRAM |
|---|---|---|---|---|---|---|---|---|---|---|
| L24 *Room for Everyone*, 4 players, 1280×720, 150 s | Forward+ / Standard | 5.56 ms | 5.56 ms | 10.8 ms | 0.88 ms | 154 | 352 | 95k | 128 MB | 76 MB |
| L24, 4 players, 1280×720, 150 s | Forward+ / **Low** | 5.56 ms | 5.56 ms | 10.1 ms | 0.84 ms | **131** | 329 | 60k | 128 MB | 66 MB |
| L24, 4 players, 1280×800 (Deck resolution), 90 s | Forward+ / Standard | 5.56 ms | 5.56 ms | 9.3 ms | 0.88 ms | 163 | 353 | 93k | 115 MB | 79 MB |
| L24, 4 players, 1920×1080, 90 s | Forward+ / Standard | 5.56 ms | 5.56 ms | 9.3 ms | 0.89 ms | 154 | 344 | 93k | 119 MB | 99 MB |
| L12 *The Quiet-ish Concert*, 2 players, 1280×720, 90 s | Forward+ / Standard | 5.56 ms | 5.56 ms | 10.7 ms | 0.43 ms | 114 | 247 | 78k | 113 MB | 74 MB |
| L01 *First Bell*, solo, 1280×720, 60 s | Forward+ / Standard | 5.56 ms | 5.56 ms | 10.5 ms | 0.16 ms | 80 | 149 | 59k | 105 MB | 72 MB |
| L24, 4 players, 1280×720, 90 s | Compatibility (GL) / Standard | 8.66 ms | 11.1 ms | 15.8 ms | 0.93 ms | 206 | 396 | 93k | 96 MB | 33 MB |

L24 with four players is the brief's worst case. It has:
- four staff and six occupied rooms
- a visible queue
- all systems except shutter and lift
- a steam cloud, festival parcels and story decorations

**What changed since the first measurement:**
- Frame-wide draw calls on L24 with 4 players fell from 622 to about 350.
- Isolated 78–133 ms hitches no longer appear: max 9–16 ms across all runs.

The fixes:
- Each character is now one skinned mesh, and station bodies are merged into one floor
  mesh (D28).
- Only main body masses cast shadows.
- Guest rigs, item meshes and common guest paths are prebuilt at load.
- Music stems are preloaded.

## Against the §19.6 and §17.4 targets

| Target | Result |
|---|---|
| Main gameplay frame ≤16.7 ms at 60 fps (desktop reference) | ✅ on the M1 Pro: p95 5.6 ms and max ≤10.8 ms at 720p, 800p and 1080p in the worst case |
| Pure simulation ≤2 ms per action tick | ✅ 0.16–0.93 ms (L24 with 4 players is the worst case) |
| Normal client RAM ≤1 GB | ✅ The process's static memory was 96–128 MB. Total RSS was not separately recorded. |
| Compressed distribution ≤1.5 GB | ✅ The game is about 90 MB uncompressed (executable plus 20 MB PCK) |
| UI layout not rebuilt every frame; no per-frame scene-tree searches | ✅ The HUD draws via `_draw`. Menus rebuild only on change. |
| Actors ≤5k triangles, stations ≤3k, most props ≤1k | ✅ for 75 of 76 models (`tools/dev/mesh_budget.gd`, `build/mesh_budget.txt`). Actors use 310–692 triangles, stations up to 2,100 (heat pump), items and props mostly under 900. The festival trunk is 1,078, just over the "most props" guideline. |
| Busy floor <350k visible triangles | ✅ about 95k primitives at the peak (60k on Low) |
| Busy floor <150 draw calls (low preset) | ✅ **131 on Low** (no shadows or outlines) and 154 on Standard, in the 3D floor viewport (colour plus shadow passes) on L24 with 4 players. Before D28 it was 622 frame-wide. The HUD adds about 200 2D draw calls (panels, icons and text interleaved), which the floor budget doesn't cover. |
| 1080p60 on a modest discrete-GPU desktop | ⛔ **unmeasured** (no such machine) |
| 720p30 low on Intel UHD 630-class iGPU | ⛔ **unmeasured** |
| 800p60 low on Steam Deck LCD | ⛔ **unmeasured** (no device). 1280×800 runs on the M1 Pro are above. |
| Headless server loads no graphics or audio | ✅ The dedicated-server export (`dedicated_server` feature) runs in a container without GPU, display or audio (`tools/smoke_linux.sh`) |

## Server

The authoritative service steps each room's simulation at 30 Hz. Measured per-tick cost of
the simulation is 0.16–0.92 ms per room on the M1 Pro (table above), and the network
snapshot work is extra. The 16-room default should fit in one core, but this is
**unmeasured under load**; see `OPERATIONS.md` → *Capacity notes*.
