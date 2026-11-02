#!/usr/bin/env bash
# Installs or updates Room for Trouble on a Steam Deck (or another Linux PC with Steam)
# from a build machine on the same network running tools/deck/serve.sh:
#   curl -fsSL <build machine>:8765/deck | bash
# The game goes to ~/Games/RoomForTrouble and appears in the Steam library as
# "Room for Trouble". Saves and logs stay in
# ~/.local/share/godot/app_userdata/Room for Trouble and survive updates.
set -euo pipefail
if [ "$(uname -s)" != "Linux" ]; then
  echo "This installs the Linux build: run it on the Steam Deck (Desktop Mode → Konsole)." >&2
  exit 1
fi
SRC="${RFT_SRC:-@SRC@}"
DEST="$HOME/Games/RoomForTrouble"
NAME="Room for Trouble"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $NAME from $SRC"
curl -fL --progress-bar "$SRC/RoomForTrouble-linux.tar.gz" -o "$tmp/game.tar.gz"
want=$(curl -fsS "$SRC/SHA256SUMS" | awk '$2=="RoomForTrouble-linux.tar.gz"{print $1}')
got=$(sha256sum "$tmp/game.tar.gz" | awk '{print $1}')
if [ -z "$want" ] || [ "$want" != "$got" ]; then
  echo "The download is damaged (checksum mismatch). Run the command again." >&2
  exit 1
fi
mkdir -p "$tmp/game"
tar -xzf "$tmp/game.tar.gz" -C "$tmp/game"
[ -f "$DEST/endpoint.txt" ] && cp "$DEST/endpoint.txt" "$tmp/game/"

# Steam names a non-Steam shortcut after its target file, so the target is a
# small launcher called "Room for Trouble". It also retries the library art,
# in case Steam had not saved the new shortcut yet when this script ran.
cat > "$tmp/game/$NAME" <<'EOF'
#!/bin/sh
cd "$(dirname "$0")" || exit 1
python3 steam/steam_shortcut.py art steam >/dev/null 2>&1
exec ./RoomForTrouble.x86_64 "$@"
EOF
chmod +x "$tmp/game/$NAME" "$tmp/game/RoomForTrouble.x86_64"

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST.old"
[ -d "$DEST" ] && mv "$DEST" "$DEST.old"
mv "$tmp/game" "$DEST"
rm -rf "$DEST.old"
echo "Installed $(head -2 "$DEST/VERSION.txt" | tr '\n' ' ')to $DEST"

# Use the same launcher for the desktop entry and Steam, so adding the desktop
# entry to Steam does not create a second shortcut targeting the raw executable.
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/room-for-trouble.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$NAME
Comment=Cozy co-op monster hotel
Exec="$DEST/$NAME"
Path=$DEST
Icon=$DEST/steam/icon.png
Categories=Game;
EOF

helper="$DEST/steam/steam_shortcut.py"
if python3 "$helper" has; then
  echo "Already in your Steam library."
else
  echo "Adding to Steam…"
  if command -v steamos-add-to-steam >/dev/null; then
    steamos-add-to-steam "$DEST/$NAME" >/dev/null 2>&1 || true
  else
    touch /tmp/addnonsteamgamefile
    url="steam://addnonsteamgame/$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$DEST/$NAME")"
    (steam "$url" >/dev/null 2>&1 &)
  fi
  for _ in $(seq 1 20); do python3 "$helper" has && break; sleep 1; done
fi
if python3 "$helper" art "$DEST/steam"; then
  echo "Library artwork added (it shows after Steam restarts, e.g. when you switch to Game Mode)."
elif ! python3 "$helper" has; then
  echo "Steam has not saved the shortcut yet. If Room for Trouble is missing from your library,"
  echo "add it in Steam → Games → Add a Non-Steam Game → Browse: $DEST/$NAME"
fi
echo
echo "Done. Switch to Game Mode and find $NAME under Library → Non-Steam."
