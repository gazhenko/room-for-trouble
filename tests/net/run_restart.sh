#!/usr/bin/env bash
# NET04: restart the deployed service mid-shift; the client must reconnect with
# its token and the room must resume from the server checkpoint.
#   RFT_TLS_CA_FILE=... tests/net/run_restart.sh wss://localhost:18443/game <compose-project> <compose-file> <env-file>
set -uo pipefail
cd "$(dirname "$0")/../.."
URL="$1"; PROJ="$2"; FILE="$3"; ENVF="$4"
DIR=$(mktemp -d /tmp/rft_restart.XXXX)
godot --headless --path . --script res://tests/net/net_client.gd -- --role=r --url="$URL" --dir="$DIR" > "$DIR/r.log" 2>&1 &
C=$!
for i in $(seq 1 120); do [ -f "$DIR/restart_now" ] && break; sleep 0.5; done
echo "restarting service…"
docker compose -p "$PROJ" -f "$FILE" --env-file "$ENVF" restart rft > /dev/null 2>&1
wait $C
python3 - "$DIR" <<'PY'
import json, sys, os
r = json.load(open(os.path.join(sys.argv[1], "r.json")))
ok = r.get("reconnected") and r.get("resumed_after_restart_at", 0) >= r.get("restart_requested", 999) + 6 and not r["errors"]
print("restart at hotel s", r.get("restart_requested"), "| resumed to", r.get("resumed_after_restart_at"), "| reconnected", r.get("reconnected"), "| errors", r["errors"])
print("NET04:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
PY
