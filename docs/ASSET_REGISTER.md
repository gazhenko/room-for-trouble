# Asset register

Every asset that ships in *Room for Trouble*, with its provenance, licence, source file,
export file and final status (§0.3, §17.3). The project contains **no** stock, sampled,
scraped or AI-image assets. Apart from the two OFL fonts, everything is generated from
source code in this repository and is owned by the project.

"Final" means finished to the art direction for release, not a debug stand-in.

## Summary

| Category | Count | Provenance | Licence | Source | Shipped as | Final |
|---|---|---|---|---|---|---|
| Fonts | 2 | Third-party (Google Fonts repository) | SIL OFL 1.1 | `assets/export/fonts/*.ttf` | Embedded in the PCK; licence texts beside the executable (`licenses/`) | yes |
| Music and stings | 33 cues | Original procedural synthesis | Project-owned | `tools/audio/music.py`, `instruments.py`, `theory.py`, `dsp.py` | `assets/export/audio/music/*.ogg` | yes |
| Sound effects | 139 cues | Original procedural synthesis | Project-owned | `tools/audio/sfx.py` | `assets/export/audio/sfx/*.ogg` | yes |
| Voice "babble" syllables | 16 cues | Original procedural synthesis (formant-filtered tones, no recordings) | Project-owned | `tools/audio/sfx.py` | `assets/export/audio/voice/*.ogg` | yes |
| UI, system, family, guest, staff, item and action icons | 143 icons, plus high-contrast variants | Original pixel art authored as text grids | Project-owned | `data/art/icons/*.txt` (palette in `palette.txt`) | The same text files, decoded at runtime (`src/ui/icons.gd`) | yes |
| App icon | 1 | Original, rendered from the icon sources | Project-owned | `tools/icons/export_app_icon.py` | `assets/export/icons/app_icon.png`, `.ico`; macOS `.icns` generated at export | yes |
| Actors (4 staff, 3 hosts, 6 guest families with named variants) | 13 rigs | Original procedural low-poly meshes | Project-owned | `src/view/models/model_actors.gd`, `src/view/actor_rig.gd` | Built at runtime | yes |
| Stations and fixtures (beds, shelves, kiosk, pump, gates, lifts, shutter…) | 23 kinds | Original procedural meshes | Project-owned | `src/view/models/model_stations.gd`, `station_node.gd` | Built at runtime | yes |
| Items (tickets, linen, towels, snacks, 6 welcome gifts, tools, trunk, parcels) | 18 kinds | Original procedural meshes | Project-owned | `src/view/models/model_items.gd` | Built at runtime | yes |
| Story and hub props, and cosmetic-set decorations | 22 kinds | Original procedural meshes | Project-owned | `src/view/models/model_props.gd` | Built at runtime | yes |
| Hotel shell (walls, floors, rugs, windows, trees, backdrop) | 6 layouts | Original procedural geometry from layout data | Project-owned | `src/view/hotel_builder.gd`, `backdrop.gd`, `data/layouts/*.json` | Built at runtime | yes |
| Shaders: toon with dither bands, dither alpha, highlight hull, outline post-process | 4 | Original | Project-owned | `src/view/shaders/*.gdshader` | Compiled by Godot | yes |
| Story scenes (opening, 5 bridges, ending, 24 pre-shift beats, 24 postcards, live gags) | 55 scenes | Original writing and staging | Project-owned | `tools/content/story_src.py` and `docs/DESIGN_BRIEF.md` | `data/story/*.json` | yes |
| Localization (English) | 933 strings | Original writing | Project-owned | `tools/content/strings_en.py` plus brief text | `data/localization/en.json` | yes |
| Campaign and content data | 24 levels, 6 templates, 3 tutorials, 8 modifiers, 9 cosmetic sets (8 unlockable plus default) | Design brief Appendix A (manifest copied verbatim) and original data | Project-owned | `data/*.json` | Same files | yes |

## Fonts

| File | Family | Copyright | Licence | Source | Final |
|---|---|---|---|---|---|
| `assets/export/fonts/PixelifySans.ttf` | Pixelify Sans (variable) | © The Pixelify Sans Project Authors | SIL OFL 1.1 (`OFL-PixelifySans.txt`) | github.com/google/fonts, `ofl/pixelifysans` | yes |
| `assets/export/fonts/Nunito.ttf` | Nunito (variable) | © The Nunito Project Authors | SIL OFL 1.1 (`OFL-Nunito.txt`) | github.com/google/fonts, `ofl/nunito` | yes |

The fonts are unmodified and are not sold on their own. The reserved font names are not used
for any derivative.

## Audio

The per-file register, with all 188 cues, is
[`assets/export/audio/REGISTER.md`](../assets/export/audio/REGISTER.md). Durations, loop
points, peak levels and buses are recorded in `assets/export/audio/audio_manifest.json`.

Rebuilding is byte-identical: fixed seeds and fixed Ogg stream serials. See
`tools/audio/README.md`.

Generation dependencies are NumPy (pinned in `tools/audio/requirements.txt`) and
vorbis-tools. Both are used only at authoring time and are not shipped.

## Icons

Icons are 16-colour pixel grids in text form (`data/art/icons/*.txt`), grouped as actions,
badges, families, guests, items, staff, systems and UI. The runtime decodes them into
textures. It applies the active colour palette (default, deuteranopia, protanopia or tritanopia) and the
high-contrast outline variant (`src/ui/icons.gd`). The authoring helpers `tools/icons/*.py`
outline, mirror, preview and export the app icon. `tools/icons/selftest.gd` checks that
every referenced icon exists.

## Engine

Godot Engine 4.7.2-stable (MIT) and the third-party components compiled into it are listed
with full licence texts in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md). The same
texts are viewable in game under **Credits → Licences**.
