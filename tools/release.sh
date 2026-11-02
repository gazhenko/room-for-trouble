#!/usr/bin/env bash
# Stages the exported builds (after tools/build.sh and tools/verify_artifacts.sh) as release
# archives, builds and verifies the offline installers, and publishes a GitHub release.
#   tools/release.sh v2.0.0 [--draft]      (RFT_NO_PUBLISH=1 packages without publishing)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TAG=${1:?tag like v2.0.0}; shift || true
DRAFT=""; [[ "${1:-}" == "--draft" ]] && DRAFT="--draft"
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
[ "v$VERSION" = "$TAG" ] || { echo "project.godot says $VERSION, not ${TAG#v}" >&2; exit 1; }
grep -q "^build $(git rev-parse --short HEAD)$" build/linux/VERSION.txt \
  || { echo "build/ is not from HEAD; run tools/build.sh first" >&2; exit 1; }
grep -q "^FAIL" build/verify_summary.txt 2>/dev/null && { echo "verify_summary.txt has failures" >&2; exit 1; }
OUT="$ROOT/build/release/$TAG"; rm -rf "$OUT"; mkdir -p "$OUT"
P="RoomForTrouble-$TAG"
cp build/macos/RoomForTrouble.zip "$OUT/$P-macOS-universal.zip"
(cd build/windows && zip -qrX9 "$OUT/$P-Windows-x64.zip" .)
# tar keeps the executable bit, which a Linux player (or a Steam Deck) needs.
COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -czf "$OUT/$P-Linux-x64.tar.gz" -C build/linux .
COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -czf "$OUT/$P-Server-Linux-x64.tar.gz" -C build/server .
(cd "$OUT" && shasum -a 256 * > SHA256SUMS.txt)
# Every release ships the offline Mac and Windows installers next to the portable archives,
# checked file by file against the archives they were built from (installer-validation.json).
python3 tools/installers/package.py "$TAG" --release-dir "$OUT" --output "$OUT"
(cd tools/installers && python3 verify.py "$TAG" --release-dir "$OUT" --output "$OUT")
(cd "$OUT" && files=(); for f in *; do [[ "$f" != SHA256SUMS.txt ]] && files+=("$f"); done; shasum -a 256 "${files[@]}" > SHA256SUMS.txt)
ls -lh "$OUT"
[[ "${RFT_NO_PUBLISH:-}" == 1 ]] && exit 0
# The README's download links and the release notes have to point at this release's installers.
for f in README.md docs/RELEASE_NOTES.md; do
  grep -q "releases/download/$TAG/$P-macOS-universal.dmg" "$f" || { echo "$f: installer links don't point at $TAG" >&2; exit 1; }
done
gh release create "$TAG" $DRAFT --title "Room for Trouble $TAG" --notes-file docs/RELEASE_NOTES.md "$OUT"/*
