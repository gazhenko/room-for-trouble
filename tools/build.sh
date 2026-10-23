#!/usr/bin/env bash
# Release build for Room for Trouble (§22.3, §22.6).
#   tools/build.sh [--skip-tests] [--only windows|linux|server|macos]
# Requires: godot 4.7.2 on PATH (or GODOT=...), matching export templates,
# python3 (3.11+). Produces build/<platform>/ packages, zips, SHA256SUMS and
# build/ARTIFACTS.json. Never call an export successful only because the
# command returned 0: run tools/smoke_linux.sh on the Linux artifact too.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SKIP_TESTS=0
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-tests) SKIP_TESTS=1 ;;
    --only) ONLY="$2"; shift ;;
  esac
  shift
done
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

ver=$("$GODOT" --version)
case "$ver" in 4.7.2.stable*) ;; *) echo "Godot 4.7.2 stable required, found $ver" >&2; exit 1 ;; esac
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
HASH=$(git rev-parse --short HEAD 2>/dev/null || echo nogit)
echo "== Room for Trouble $VERSION ($HASH) with Godot $ver"

echo "== import"
"$GODOT" --headless --editor --path . --quit >/dev/null 2>&1 || true
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

mkdir -p build
echo "== validate"
python3 tools/validate_manifest.py data/campaign_manifest.json
"$GODOT" --headless --path . --script res://tools/validate_content.gd

if [ "$SKIP_TESTS" = 0 ]; then
  echo "== tests"
  out=$("$GODOT" --headless --path . --script res://tests/run_all.gd 2>&1 | tee build/test_report.txt)
  if echo "$out" | grep -q "SCRIPT ERROR"; then echo "script errors during tests" >&2; exit 1; fi
  echo "$out" | grep "^== .*checks"
  echo "$out" | grep -q " 0 failures" || { echo "test failures" >&2; exit 1; }
  echo "== UI01 controller traversal"
  "$GODOT" --headless --path . res://tests/ui/ui_focus_test.tscn > build/ui_report.txt 2>&1 || { tail -5 build/ui_report.txt; echo "UI01 failed" >&2; exit 1; }
  grep "^== UI01" build/ui_report.txt
  echo "== online: two clients (NET01/02/03) and four seats + abuse (NET03/05)"
  tests/net/run_e2e.sh > build/net_e2e.txt 2>&1 || { tail -15 build/net_e2e.txt; exit 1; }
  tail -1 build/net_e2e.txt
  tests/net/run_quad.sh > build/net_quad.txt 2>&1 || { tail -18 build/net_quad.txt; exit 1; }
  tail -1 build/net_quad.txt
  tests/net/run_ready.sh > build/net_ready.txt 2>&1 || { tail -9 build/net_ready.txt; exit 1; }
  tail -1 build/net_ready.txt
fi

export_one() { # preset path
  local preset="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  "$GODOT" --headless --path . --export-release "$preset" "$out" 2>&1 | grep -v -E '^\s*$|savepack|^\[' || true
  [ -s "$out" ] || { echo "export failed: $preset" >&2; exit 1; }
}

package_dir() { # dir name
  local dir="$1" name="$2"
  cp README.md BUILD.md CREDITS.md THIRD_PARTY_NOTICES.md KNOWN_ISSUES.md "$dir/" 2>/dev/null || true
  mkdir -p "$dir/licenses"
  cp assets/export/fonts/OFL-*.txt "$dir/licenses/"
  printf 'Room for Trouble %s\nbuild %s\nGodot %s\n' "$VERSION" "$HASH" "$ver" > "$dir/VERSION.txt"
  (cd "$(dirname "$dir")" && rm -f "$name.zip" && zip -qr "$name.zip" "$(basename "$dir")")
}

if want windows; then
  echo "== export Windows"
  rm -rf build/windows && export_one Windows build/windows/RoomForTrouble.exe
  package_dir build/windows "RoomForTrouble-$VERSION-windows-x86_64"
fi
if want linux; then
  echo "== export Linux"
  rm -rf build/linux && export_one Linux build/linux/RoomForTrouble.x86_64
  chmod +x build/linux/RoomForTrouble.x86_64
  package_dir build/linux "RoomForTrouble-$VERSION-linux-x86_64"
fi
if want server; then
  echo "== export ServerLinux"
  rm -rf build/server && export_one ServerLinux build/server/RoomForTroubleServer.x86_64
  chmod +x build/server/RoomForTroubleServer.x86_64
  cp -r server/deploy build/server/deploy 2>/dev/null || true
  package_dir build/server "RoomForTrouble-$VERSION-server-linux-x86_64"
fi
if want macos; then
  echo "== export macOS (candidate: ad-hoc signed, not notarized)"
  rm -rf build/macos && export_one macOS build/macos/RoomForTrouble.zip
fi

echo "== checksums"
(cd build && find . -maxdepth 2 -name '*.zip' -o -maxdepth 2 -name '*.exe' -o -maxdepth 2 -name '*.x86_64' -o -maxdepth 2 -name '*.pck' | sort | xargs shasum -a 256 > SHA256SUMS)
python3 - "$VERSION" "$HASH" "$ver" <<'PY'
import json, os, sys, hashlib
version, h, gv = sys.argv[1:4]
arts = []
for root, _, files in os.walk("build"):
    for f in files:
        p = os.path.join(root, f)
        if f.endswith((".zip", ".exe", ".x86_64", ".pck")) and root.count(os.sep) <= 2:
            arts.append({"path": p, "bytes": os.path.getsize(p), "sha256": hashlib.sha256(open(p, "rb").read()).hexdigest()})
json.dump({"version": version, "build": h, "godot": gv, "artifacts": sorted(arts, key=lambda a: a["path"])},
          open("build/ARTIFACTS.json", "w"), indent=1)
print(f"{len(arts)} artifacts")
PY
cat build/SHA256SUMS
