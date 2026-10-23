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
  - Some runs overlapped a headless test run on the same machine.
- **Raw logs:** `build/perf/*.log` and `build/perf_summary2.txt`.

## Results (2026-10-23)

| Scenario | Renderer | Frame avg | p95 | Max (single frame) | Sim per tick | Draw calls (max) | Objects | Primitives | Static mem | VRAM |
|---|---|---|---|---|---|---|---|---|---|---|
| L24 *Room for Everyone*, 4 players, 1280×720, 150 s | Forward+ | 5.57 ms | 5.56 ms | 10.5 ms | 0.89 ms | 622 | 885 | 105k | 126 MB | 73 MB |
| L24, 4 players, 1280×800 (Deck resolution), 90 s | Forward+ | 5.57 ms | 5.56 ms | 111 ms (one hitch) | 0.91 ms | 616 | 885 | 104k | 114 MB | 76 MB |
| L24, 4 players, 1920×1080, 90 s | Forward+ | 5.57 ms | 5.56 ms | 16.7 ms | 0.92 ms | 607 | 885 | 104k | 118 MB | 98 MB |
| L12 *The Quiet-ish Concert*, 2 players, 1280×720, 90 s | Forward+ | 5.57 ms | 5.56 ms | 133 ms (one hitch) | 0.44 ms | 421 | 658 | 86k | 112 MB | 71 MB |
| L01 *First Bell*, solo, 1280×720, 60 s | Forward+ | 5.57 ms | 5.56 ms | 9.6 ms | 0.16 ms | 264 | 447 | 62k | 104 MB | 70 MB |
| L24, 4 players, 1280×720, 90 s | Compatibility (GL) | 6.81 ms | 11.1 ms | 77.8 ms (one hitch) | 0.88 ms | 717 | 884 | 104k | 98 MB | 30 MB |

L24 with four players is the brief's worst case. It has:
- four staff and six occupied rooms
- a visible queue
- all systems except shutter and lift
- a steam cloud, festival parcels and story decorations

**Single-frame hitches.** Three runs showed one isolated hitch (78–133 ms). Each was a
CPU-side spike: `process_ms` peaked in the same frame, and no simulation event was emitted
on that tick. The p95 was unaffected.

Two load-time fixes cut first-occurrence hitches. Before them, the busiest runs showed
repeated 40–80 ms spikes:
- Every scheduled guest rig and item mesh is now built at load.
- Common guest A* paths are memoised and pre-warmed, and the chapter's music stems are
  preloaded.

The remaining single hitch is not fully attributed. Candidates are the bot's planning burst,
the concurrent test run, and first-use pipeline compilation.

## Against the §19.6 and §17.4 targets

| Target | Result |
|---|---|
| Main gameplay frame ≤16.7 ms at 60 fps (desktop reference) | ✅ on the M1 Pro: p95 5.6 ms at 720p, 800p and 1080p in the worst case |
| Pure simulation ≤2 ms per action tick | ✅ 0.16–0.92 ms (L24 with 4 players is the worst case) |
| Normal client RAM ≤1 GB | ✅ The process's static memory was 98–126 MB. Total RSS was not separately recorded. |
| Compressed distribution ≤1.5 GB | ✅ The game is about 90 MB uncompressed (executable plus 20 MB PCK) |
| UI layout not rebuilt every frame; no per-frame scene-tree searches | ✅ The HUD draws via `_draw`. Menus rebuild only on change. |
| Actors ≤5k triangles, stations ≤3k, most props ≤1k | ✅ for 75 of 76 models (`tools/dev/mesh_budget.gd`, `build/mesh_budget.txt`). Actors use 310–692 triangles, stations up to 2,100 (heat pump), items and props mostly under 900. The festival trunk is 1,078, just over the "most props" guideline. |
| Busy floor <350k visible triangles | ✅ about 105k primitives at the peak |
| Busy floor <150 draw calls (low preset) | ❌ **Not met: 607–622 draw calls on L24 with 4 players (Forward+) and 717 on Compatibility.** Stations are separate mesh instances, each with depth-prepass and shadow passes. The frame-time cost is negligible on the M1 Pro but unmeasured on weak GPUs. Remedy: merge static station meshes per floor, or use MultiMesh for repeated decor. |
| 1080p60 on a modest discrete-GPU desktop | ⛔ **unmeasured** (no such machine) |
| 720p30 low on Intel UHD 630-class iGPU | ⛔ **unmeasured** |
| 800p60 low on Steam Deck LCD | ⛔ **unmeasured** (no device). 1280×800 runs on the M1 Pro are above. |
| Headless server loads no graphics or audio | ✅ The dedicated-server export (`dedicated_server` feature) runs in a container without GPU, display or audio (`tools/smoke_linux.sh`) |

## Server

The authoritative service steps each room's simulation at 30 Hz. Measured per-tick cost of
the simulation is 0.16–0.92 ms per room on the M1 Pro (table above), and the network
snapshot work is extra. The 16-room default should fit in one core, but this is
**unmeasured under load**; see `OPERATIONS.md` → *Capacity notes*.
