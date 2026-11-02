**Room for Trouble 2.0.0** is a cozy cooperative monster-hotel game for 1–4 players, rebuilt at Overcooked scale.

### Easy installers

| Computer | Download |
| --- | --- |
| Mac, Apple Silicon or Intel | [RoomForTrouble-v2.0.0-macOS-universal.dmg](https://github.com/gazhenko/room-for-trouble/releases/download/v2.0.0/RoomForTrouble-v2.0.0-macOS-universal.dmg) |
| Windows 10/11, Intel/AMD 64-bit | [RoomForTrouble-v2.0.0-Windows-x64-Setup.exe](https://github.com/gazhenko/room-for-trouble/releases/download/v2.0.0/RoomForTrouble-v2.0.0-Windows-x64-Setup.exe) |

Read [START-HERE.txt](https://github.com/gazhenko/room-for-trouble/releases/download/v2.0.0/START-HERE.txt) first if you like. Both installers contain the whole game and work offline.
- **Mac:** open the disk image and drag the app to Applications. The app is ad-hoc signed but not notarized; if macOS blocks it, use **System Settings → Privacy & Security → Open Anyway**.
- **Windows:** the installer is unsigned and needs no administrator password.

**Portable archives:**
- `-macOS-universal.zip`, `-Windows-x64.zip`
- `-Linux-x64.tar.gz` (also for the Steam Deck)
- `-Server-Linux-x64.tar.gz`, the dedicated online server; see `OPERATIONS.md`

Every file is listed in `SHA256SUMS.txt`.

### What's new in 2.0

- **Small floors you can read at a glance.** Chapter 1 has four rooms on a 13×13 floor; chapters 2–6 have six rooms on 19×13, and the split lobby is 19×14. Staff are about 70 px tall at 1280×800, up from 28.
- **Order cards.** Each guest gets a card with their key, gift and requests in order, plus a timer. Fast service earns tips. Arrivals are continuous, and the first guest arrives within four seconds. A missed order costs points, but a shift still never fails.
- **Snappy hands.**
  - Picking up and putting down are instant and never stop you moving.
  - Quick Step is now a real dash.
  - Pass counters let you hand anything across.
- **A middle step.**
  - Towels for dragons are warmed and snacks for yetis are chilled, at the heat pump, at an open vent, or by asking a helping dragon or yeti.
  - A sprout's watering is a step on its card.
  - Festival trunks are job cards showing both handles.
- **Hazards you can see.** Steam slows you, frost and puddles make you slide, and howls startle you. The lift has a car that sinks and rises.
- **A look for every chapter,** from late morning to a lantern-lit festival night.
- **New front end.** A new title logo, matching menus over the new hotel, and a "What's new in 2.0" page.
- **Readability and accessibility.**
  - The HUD has a minimum text and icon size for a 7" screen and stays clear of overlaps at 175% UI scale.
  - Reduced motion, colour-safe hazard cues and captions cover every new action.
- **Sound.** Nine new sound effects. The music rises when orders get close to their deadline.
- **Story scenes** are reframed for the new floors and the larger characters.

Simulation version 2.0.1, protocol 2: 1.x clients can't share an online room with 2.0, and 1.x replays are refused.

### Verified for this build

- **Automated suites:** about 2,660 headless tests, a controller-only walk through every menu (including 175% UI scale), and the online suites with 2 and 4 seats.
- **macOS:** the app's smoke test on Metal and on Vulkan (MoltenVK).
- **Linux:**
  - in a clean x86-64 container, on software OpenGL and on software Vulkan at the Steam Deck's 1280×800
  - with four kernel-level virtual gamepads
- **Windows:** under Wine, with both renderers.
- **Online:** the server through a 100 ms, 2%-loss link.
- **Installers:**
  - the DMG mounts and passes `codesign --verify`
  - the Setup.exe extracts
  - both contain every file of the archive they were built from

### Not verified yet

- a real Windows PC (neither the game nor the installer has run on one)
- the Steam Deck itself
- physical controllers
- macOS notarization
- a permanent public online host
- real family playtests

[KNOWN_ISSUES.md](https://github.com/gazhenko/room-for-trouble/blob/v2.0.0/KNOWN_ISSUES.md) lists everything that remains.
