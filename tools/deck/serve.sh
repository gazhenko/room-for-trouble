#!/usr/bin/env bash
# Serves the Linux build to a Steam Deck on the same network (after tools/build.sh):
#   tools/deck/serve.sh [port]
# then on the Deck, in Desktop Mode → Konsole:
#   curl -fsSL <this machine>:8765/deck | bash          install or update
#   bash <(curl -fsSL <this machine>:8765/ssh)          optional: allow SSH pushes
# Ctrl+C stops serving. Library art comes from tools/deck/steam_art.tscn.
set -euo pipefail
cd "$(dirname "$0")/../.."
PORT="${1:-8765}"
[ -x build/linux/RoomForTrouble.x86_64 ] || { echo "Run tools/build.sh first." >&2; exit 1; }
IP=$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
OUT=build/deck
rm -rf "$OUT" && mkdir -p "$OUT/stage/steam"
cp -R build/linux/. "$OUT/stage/"
if ls build/steam_art/*.png >/dev/null 2>&1; then
  cp build/steam_art/*.png "$OUT/stage/steam/"
else
  echo "note: no library art; run: godot --path . res://tools/deck/steam_art.tscn" >&2
fi
cp tools/deck/steam_shortcut.py "$OUT/stage/steam/"
COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -czf "$OUT/RoomForTrouble-linux.tar.gz" -C "$OUT/stage" . 2>/dev/null \
  || tar -czf "$OUT/RoomForTrouble-linux.tar.gz" -C "$OUT/stage" .
rm -rf "$OUT/stage"
(cd "$OUT" && shasum -a 256 RoomForTrouble-linux.tar.gz > SHA256SUMS)
sed "s|@SRC@|http://$IP:$PORT|" tools/deck/install.sh > "$OUT/deck"
KEY=$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || true)
[ -n "$KEY" ] && sed "s|@KEY@|$KEY|" tools/deck/allow_ssh.sh > "$OUT/ssh"
echo "Serving $(sed -n 1,2p build/linux/VERSION.txt | tr '\n' ' ')on http://$IP:$PORT"
echo "On the Deck (Desktop Mode → Konsole):  curl -fsSL $IP:$PORT/deck | bash"
cd "$OUT" && exec python3 -m http.server "$PORT" --bind 0.0.0.0
