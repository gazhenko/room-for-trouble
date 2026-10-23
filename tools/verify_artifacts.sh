#!/usr/bin/env bash
# Runs every check that exercises the exported artifacts (after tools/build.sh):
#   macOS app smoke test (on a Mac), Linux game + server in a clean container,
#   Linux game with four kernel-level gamepads, Windows .exe under Wine with
#   both renderers, and the online e2e suite through a delayed, lossy link.
#   tools/verify_artifacts.sh            (needs Docker; ~30–60 min under emulation)
set -uo pipefail
cd "$(dirname "$0")/.."
results=()
run() { # name command...
  local name="$1"; shift
  echo "== $name"
  if "$@" > "build/verify_${name}.log" 2>&1; then results+=("PASS $name"); else results+=("FAIL $name"); fi
  tail -3 "build/verify_${name}.log"
}
if [ "$(uname)" = "Darwin" ] && [ -f build/macos/RoomForTrouble.zip ]; then
  rm -rf /tmp/rft_verify_mac && mkdir -p /tmp/rft_verify_mac && (cd /tmp/rft_verify_mac && unzip -q "$OLDPWD/build/macos/RoomForTrouble.zip")
  run macos "/tmp/rft_verify_mac/Room for Trouble.app/Contents/MacOS/Room for Trouble" -- --smoke-test --smoke-out=/tmp/rft_verify_mac/smoke
fi
run linux tools/smoke_linux.sh
run linux_gamepads tools/smoke_linux_gamepads.sh
run windows_wine_gl env RENDERER=opengl3 tools/smoke_windows_wine.sh
run windows_wine_vulkan env RENDERER=vulkan tools/smoke_windows_wine.sh
run online_netem tests/net/run_netem.sh
echo
printf '%s\n' "${results[@]}" | tee build/verify_summary.txt
! grep -q "^FAIL" build/verify_summary.txt
