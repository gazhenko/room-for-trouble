#!/usr/bin/env bash
# Online end-to-end test: real server process + two client processes.
#   tests/net/run_e2e.sh [ws://127.0.0.1:18080]   (local plain WS by default)
# With a URL argument it targets an already running endpoint (e.g. wss via TLS proxy).
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
DIR=$(mktemp -d /tmp/rft_e2e.XXXX)
URL="${1:-}"
SERVER_PID=""
if [ -z "$URL" ]; then
  URL="ws://127.0.0.1:18080"
  "$GODOT" --headless --path . -- --server --port 18080 --data-dir "$DIR/server" > "$DIR/server.log" 2>&1 &
  SERVER_PID=$!
  sleep 3
fi
"$GODOT" --headless --path . --script res://tests/net/net_client.gd -- --role=a --url="$URL" --dir="$DIR" > "$DIR/a.log" 2>&1 &
A=$!
sleep 1
"$GODOT" --headless --path . --script res://tests/net/net_client.gd -- --role=b --url="$URL" --dir="$DIR" > "$DIR/b.log" 2>&1 &
B=$!
wait $A; wait $B
[ -n "$SERVER_PID" ] && kill $SERVER_PID 2>/dev/null
python3 - "$DIR" <<'PY'
import json, sys, os
d = sys.argv[1]
a = json.load(open(os.path.join(d, "a.json"))); b = json.load(open(os.path.join(d, "b.json")))
checks = [
  ("both connected", a["connected"] and b["connected"]),
  ("b joined a's room by code (case-insensitive)", a["room"] != "" and a["room"] == b["room"]),
  ("two peers in one room (NET03)", a["lobby_peers"] >= 2),
  ("shift started for both", a["shift_started"] and b["shift_started"]),
  ("snapshots streamed (>=50 each)", a["snapshots"] >= 50 and b["snapshots"] >= 50),
  ("hotel time advanced", a["hotel_s_max"] >= 20),
  ("server moved a's avatar from its inputs", a["my_moved_m"] > 1.0),
  ("forged frame for another seat ignored (NET01)", not a["other_seat_forged_moved"]),
  ("b reconnected with its token (NET02)", b["reconnected"]),
  ("both received the same result", a["result"].get("result_id") and a["result"].get("result_id") == b["result"].get("result_id")),
  ("no client errors", not a["errors"] and not b["errors"]),
]
ok = True
for name, passed in checks:
    print(("PASS " if passed else "FAIL ") + name)
    ok = ok and bool(passed)
print("E2E:", "PASS" if ok else "FAIL", d)
sys.exit(0 if ok else 1)
PY
