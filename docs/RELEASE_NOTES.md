**Room for Trouble 2.0.1** is a small update to [2.0.0](https://github.com/gazhenko/room-for-trouble/releases/tag/v2.0.0), the Overcooked-scale rebuild of the cozy co-op monster-hotel game for 1–4 players.

### Easy installers

| Computer | Download |
| --- | --- |
| Mac, Apple Silicon or Intel | [RoomForTrouble-v2.0.1-macOS-universal.dmg](https://github.com/gazhenko/room-for-trouble/releases/download/v2.0.1/RoomForTrouble-v2.0.1-macOS-universal.dmg) |
| Windows 10/11, Intel/AMD 64-bit | [RoomForTrouble-v2.0.1-Windows-x64-Setup.exe](https://github.com/gazhenko/room-for-trouble/releases/download/v2.0.1/RoomForTrouble-v2.0.1-Windows-x64-Setup.exe) |

You can read [START-HERE.txt](https://github.com/gazhenko/room-for-trouble/releases/download/v2.0.1/START-HERE.txt) first. Both installers contain the whole game and work offline.
- **Mac:** open the disk image and drag the app to Applications. The app is ad-hoc signed but not notarized. If macOS blocks it, use **System Settings → Privacy & Security → Open Anyway**.
- **Windows:** the installer is unsigned and needs no administrator password.

**Portable archives:**
- `-macOS-universal.zip`, `-Windows-x64.zip`
- `-Linux-x64.tar.gz` (also for the Steam Deck)
- `-Server-Linux-x64.tar.gz`, the dedicated online server; see `OPERATIONS.md`

`SHA256SUMS.txt` lists every file.

### Changes in 2.0.1

- **Controller symbols stay right when a pad drops out.** A controller that is unplugged (or a Bluetooth pad that falls asleep) keeps its own button symbols until it comes back or another controller takes its seat. Before, prompts redrawn in the meantime showed Xbox symbols.
- **Measured on a Steam Deck.** On a Steam Deck OLED the game passes its smoke test and holds 90 fps with four players on every chapter finale, even on first launch, when it is still compiling shaders. See `docs/PERFORMANCE.md`.

Saves, online rooms and replays are unchanged from 2.0.0 (simulation version 2.0.1, protocol 2), so 2.0.0 and 2.0.1 players can share a room.

### Verified for this build

- **Automated suites:** about 2,660 headless tests, a controller-only walk through every menu (including 175% UI scale), and the online suites with 2 and 4 seats.
- **macOS:** the app's smoke test on Metal and on Vulkan (MoltenVK).
- **Linux:**
  - in a clean x86-64 container, on software OpenGL and on software Vulkan at the Steam Deck's 1280×800
  - with four kernel-level virtual gamepads, including unplugging and reclaiming a seat
- **Steam Deck OLED:** the smoke test of the exported build on the device.
- **Windows:** under Wine, with both renderers.
- **Online:** the server through a 100 ms link with 2% packet loss.
- **Installers:**
  - the DMG mounts and passes `codesign --verify`
  - the Setup.exe extracts
  - both contain every file of the archive they were built from

### Not verified yet

- a real Windows PC (neither the game nor the installer has run on one)
- playing on the Deck in Game Mode with its own controls
- physical controllers
- macOS notarization
- a permanent public online host
- real family playtests

[KNOWN_ISSUES.md](https://github.com/gazhenko/room-for-trouble/blob/v2.0.1/KNOWN_ISSUES.md) lists everything that remains.
