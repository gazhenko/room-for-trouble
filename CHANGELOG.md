# Changelog

All notable changes to *Room for Trouble*. Versions follow `config/version` in
`project.godot`. Protocol and content changes are noted, because mismatched clients cannot
share an online room.

## 1.0.0 — 2026-10-23

First complete build of the game described in `docs/DESIGN_BRIEF.md`.

### Game

- 1–4 player couch co-op with per-device seats. Two keyboard slots and any number of
  controllers, each with its own bindings and assists. Drop-in seat lobby.
- Private online rooms: create, or join with an 8-character code; any local/remote seat mix
  up to 4; leader controls; reconnect with a token; per-seat auto-pause.
- The campaign:
  - 3 tutorials and 24 shifts in 6 chapters on 6 floor layouts (P1–P6)
  - an opening, 5 chapter bridges and an ending
  - a pre-shift beat, a live gag and a postcard for every shift
  - progression never depends on stars
- Six guest families with comfort, quirk, helper and visual behaviour. Hotel systems:
  - tickets, gifts, requests, laundry and stock
  - relocation, thermal vents and gates, acoustic curtains
  - moisture, steam and puddles
  - lifts, the shutter, festival trunks and parcels
- Cozy, Family and Busy pace. Gus as a solo helper. A soft wrap-up with a Cozy Corner, and
  one team result with stars and three ribbons per shift.
- The hub hotel, Scrapbook (postcards, guest guide, ribbons, story replays), Wardrobe (8
  cosmetic sets), Quick Shift (8 modifiers, visible seed) and the Playground sandbox.
- Accessibility:
  - remapping and UI scale
  - readable font, high contrast and colour-blind palettes
  - reduced motion, transparency, flashes and camera shake
  - captions with speaker names and sound visualisations
  - mono audio and read-aloud
  - per-seat Auto Catch, toggle Work, Quick Step and Steady Feet

### Presentation

- An Overcooked-style fixed perspective camera over a pixel-art 3D scene: low-resolution
  render, integer upscale, toon shading with dithered bands, and an outline pass on Forward+.
- Procedural low-poly actors, stations, items and props, 143 text-authored pixel icons, and
  188 procedurally synthesised music, effect and voice cues.

### Engineering

- Characters are single skinned meshes, station bodies are one merged floor mesh, and only
  main masses cast shadows. The busiest floor dropped from 622 to 154 draw calls (131 on
  the new Low graphics preset).

- A pure, integer, fixed-tick (30 Hz) deterministic simulation shared by local play, the
  online service, tests, the reference bot and replays.
- An authoritative WebSocket room service with strict schema validation, rate limits,
  checkpoints, graceful shutdown and a protocol health probe. Docker and Caddy deployment.
- Versioned, checksummed saves with atomic writes, three backups, migration and idempotent
  results.
- Tests:
  - headless suites with about 2,200 checks
  - controller UI traversal
  - online end-to-end, four-seat and abuse tests
  - restart recovery
  - Linux container smoke tests
  - 126 reference runs
- Protocol version 1. The content hash is printed by the server at startup and by
  `validate_content.gd`.
