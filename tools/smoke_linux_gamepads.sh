#!/usr/bin/env bash
# Exported Linux game + four kernel-level virtual gamepads (uinput/evdev, mixed
# Xbox 360 / DualShock 4 identities) in a privileged x86-64 container. Checks
# seat joining, per-device stick routing, Start/B, unplug and reclaim with a
# different controller. Real controllers remain untested; this exercises the
# OS → Godot joypad driver → InputRouter path end to end.
#   tools/smoke_linux_gamepads.sh        (expects build/linux)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build/smoke_linux_gamepads"
rm -rf "$OUT" && mkdir -p "$OUT"
IMG=rft-smoke-pads
docker build --platform linux/amd64 -q -t "$IMG" -f - . > /dev/null <<'DOCKER'
FROM debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb xauth libgl1 libgl1-mesa-dri libglx-mesa0 libxcursor1 libxinerama1 libxrandr2 libxi6 libxkbcommon0 \
    libasound2 libpulse0 libfontconfig1 libdbus-1-3 libudev1 udev ca-certificates procps python3-evdev \
    && rm -rf /var/lib/apt/lists/*
DOCKER
docker run --rm --privileged -v /dev:/dev --platform linux/amd64 -v "$PWD/build/linux:/game:ro" -v "$PWD/tools:/tools:ro" -v "$PWD/$OUT:/out" "$IMG" bash -c '
  # A desktop runs udevd; Godot needs its events to notice newly plugged pads.
  /lib/systemd/systemd-udevd --daemon && udevadm trigger --subsystem-match=input && udevadm settle
  python3 /tools/gamepad_driver.py /out > /out/driver.log 2>&1 &
  xvfb-run -a -s "-screen 0 1280x720x24" timeout 900 /game/RoomForTrouble.x86_64 --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy -- --gamepad-test --gamepad-out=/out > /out/game.log 2>&1; echo "exit=$?" >> /out/game.log
  wait'
grep -E '\[pads\] (PASS|FAIL|OK|FAILED)|exit=' "$OUT/game.log" || tail -30 "$OUT/game.log"
grep -q '\[pads\] OK' "$OUT/game.log" && echo "LINUX GAMEPADS: PASS" || { echo "LINUX GAMEPADS: FAIL"; tail -5 "$OUT/driver.log"; exit 1; }
