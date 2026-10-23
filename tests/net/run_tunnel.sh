#!/usr/bin/env bash
# Internet play check: a local room service behind a temporary Cloudflare quick
# tunnel (public https/wss URL, real TLS certificate, real internet path), the
# e2e suite against it from this machine, then everything is shut down.
#   tests/net/run_tunnel.sh        (needs cloudflared; nothing stays public)
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
DIR=$(mktemp -d /tmp/rft_tunnel.XXXX)
"$GODOT" --headless --path . -- --server --port 18300 --data-dir "$DIR/server" > "$DIR/server.log" 2>&1 &
S=$!
cloudflared tunnel --no-autoupdate --url http://127.0.0.1:18300 > "$DIR/tunnel.log" 2>&1 &
T=$!
cleanup() { kill $T $S 2>/dev/null; wait $T $S 2>/dev/null; }
trap cleanup EXIT
URL=""
for i in $(seq 1 60); do
  URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$DIR/tunnel.log" | head -1)
  [ -n "$URL" ] && break
  sleep 1
done
[ -z "$URL" ] && { echo "no tunnel URL"; tail -20 "$DIR/tunnel.log"; exit 1; }
WSS="wss://${URL#https://}"
echo "public endpoint: $WSS"
# Wait until the tunnel answers the protocol health probe over TLS.
for i in $(seq 1 30); do
  "$GODOT" --headless --path . -- --probe "$WSS" > "$DIR/probe.log" 2>&1 && break
  sleep 2
done
grep -h "probe" "$DIR/probe.log" | tail -1
tests/net/run_e2e.sh "$WSS" > "$DIR/e2e.txt" 2>&1; R=$?
tail -13 "$DIR/e2e.txt"
echo "TUNNEL E2E over the internet ($WSS): $([ $R = 0 ] && echo PASS || echo FAIL)"
exit $R
