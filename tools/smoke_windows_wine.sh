#!/usr/bin/env bash
# Best-effort check of the exported Windows build without a Windows machine:
# runs RoomForTrouble.exe under Wine (x86-64 Debian container, Xvfb, Mesa
# llvmpipe, Compatibility renderer) and executes the shipping smoke test.
# This is NOT a substitute for testing on real Windows hardware.
#   tools/smoke_windows_wine.sh        (expects build/windows/RoomForTrouble.exe)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build/smoke_windows_wine"
rm -rf "$OUT" && mkdir -p "$OUT"
IMG=rft-smoke-wine
docker build --platform linux/amd64 -t "$IMG" -f - . <<'DOCKER'
FROM debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8
RUN dpkg --add-architecture i386 && apt-get update && apt-get install -y --no-install-recommends \
    wine wine64 xvfb xauth libgl1-mesa-dri libglx-mesa0 mesa-vulkan-drivers ca-certificates procps \
    && rm -rf /var/lib/apt/lists/* && useradd -m player
USER player
WORKDIR /home/player
ENV WINEDEBUG=-all WINEPREFIX=/home/player/.wine
RUN wineboot --init 2>/dev/null || true
DOCKER
docker run --rm --platform linux/amd64 -v "$PWD/build/windows:/game:ro" -v "$PWD/$OUT:/out" "$IMG" \
  bash -c 'xvfb-run -a -s "-screen 0 1280x720x24" timeout 900 wine /game/RoomForTrouble.exe --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy -- --smoke-test "--smoke-out=Z:\\out\\game" > /out/game.log 2>&1; echo "exit=$?" >> /out/game.log'
grep -E '\[smoke\]|exit=' "$OUT/game.log" || tail -20 "$OUT/game.log"
grep -q '\[smoke\] OK' "$OUT/game.log" && echo "WINDOWS (WINE) SMOKE: PASS" || { echo "WINDOWS (WINE) SMOKE: FAIL"; exit 1; }
