#!/usr/bin/env bash
# Runs the exported Linux artifacts in a clean x86-64 Debian container (§24.5):
# the game under Xvfb with software OpenGL (Compatibility renderer) and with
# software Vulkan (Forward+ at 1280x800, the Steam Deck's renderer and panel),
# and the dedicated server without any GPU/display/audio device plus its probe.
#   tools/smoke_linux.sh            (expects build/linux and build/server)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="build/smoke_linux"
rm -rf "$OUT" && mkdir -p "$OUT"
IMG=rft-smoke-linux
docker build --platform linux/amd64 -t "$IMG" -f - . <<'DOCKER'
FROM debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb xauth libgl1 libgl1-mesa-dri libglx-mesa0 libvulkan1 mesa-vulkan-drivers libxcursor1 libxinerama1 libxrandr2 libxi6 libxkbcommon0 \
    libasound2 libpulse0 libfontconfig1 libdbus-1-3 libudev1 ca-certificates procps \
    && rm -rf /var/lib/apt/lists/* && useradd -m player
USER player
WORKDIR /home/player
DOCKER
echo "== game (Compatibility renderer, llvmpipe)"
docker run --rm --platform linux/amd64 -v "$PWD/build/linux:/game:ro" -v "$PWD/$OUT:/out" "$IMG" \
  bash -c 'xvfb-run -a -s "-screen 0 1280x720x24" timeout 600 /game/RoomForTrouble.x86_64 --rendering-method gl_compatibility --rendering-driver opengl3 --audio-driver Dummy -- --smoke-test --smoke-out=/out/game > /out/game.log 2>&1; echo "exit=$?" >> /out/game.log'
grep -E '\[smoke\]|exit=' "$OUT/game.log" || true
echo "== game (Forward+ on Vulkan, lavapipe, 1280x800)"
docker run --rm --platform linux/amd64 -v "$PWD/build/linux:/game:ro" -v "$PWD/$OUT:/out" "$IMG" \
  bash -c 'xvfb-run -a -s "-screen 0 1280x800x24" timeout 2400 /game/RoomForTrouble.x86_64 --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy -- --smoke-test --smoke-timeout=2000 --smoke-out=/out/game_vk > /out/game_vk.log 2>&1; echo "exit=$?" >> /out/game_vk.log'
grep -E '\[smoke\]|exit=' "$OUT/game_vk.log" || true
echo "== server (headless) + health probe"
docker run --rm --platform linux/amd64 -v "$PWD/build/server:/srv:ro" -v "$PWD/$OUT:/out" "$IMG" bash -c '
  /srv/RoomForTroubleServer.x86_64 --headless -- --server --port 8080 --data-dir /tmp/rft > /out/server.log 2>&1 &
  sleep 8
  timeout 30 /srv/RoomForTroubleServer.x86_64 --headless -- --probe ws://127.0.0.1:8080 > /out/probe.log 2>&1; echo "probe_exit=$?" >> /out/probe.log
  kill %1; sleep 1'
cat "$OUT/probe.log" | grep -E 'probe|rooms|exit' || true
grep -q '\[smoke\] OK' "$OUT/game.log" && grep -q '\[smoke\] OK' "$OUT/game_vk.log" && grep -q 'probe_exit=0' "$OUT/probe.log" && echo "LINUX SMOKE: PASS" || { echo "LINUX SMOKE: FAIL"; exit 1; }
