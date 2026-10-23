#!/usr/bin/env bash
# §11.4 "Start with ready players": refused before 20 s; afterwards the shift
# starts with only the ready seat and the unready player is told they sit out.
#   tests/net/run_ready.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
DIR=$(mktemp -d /tmp/rft_ready.XXXX)
"$GODOT" --headless --path . -- --server --port 18082 --data-dir "$DIR/server" > "$DIR/server.log" 2>&1 &
S=$!
sleep 3
"$GODOT" --headless --path . --script res://tests/net/net_ready.gd -- --role=h --url=ws://127.0.0.1:18082 --dir="$DIR" > "$DIR/h.log" 2>&1 &
H=$!
sleep 1
"$GODOT" --headless --path . --script res://tests/net/net_ready.gd -- --role=j --url=ws://127.0.0.1:18082 --dir="$DIR" > "$DIR/j.log" 2>&1 &
J=$!
wait $H; wait $J
kill $S 2>/dev/null
python3 - "$DIR" <<'PY'
import json, sys, os
d = sys.argv[1]
h = json.load(open(os.path.join(d, "h.json"))); j = json.load(open(os.path.join(d, "j.json")))
checks = [
  ("early start refused (<20 s)", h["early_start_refused"]),
  ("shift started after the 20 s wait", h["shift_started"] and h["started_after_s"] >= 20),
  ("only the ready seat has a character", h["staff_in_shift"] == 1 and h["my_seat_in_shift"]),
  ("unready player told they sit out", "ui.online.sitting_out" in j["notices"]),
  ("unready player has no character in the shift", j["shift_started"] and not j["my_seat_in_shift"]),
  ("both received the result", h["result"].get("result_id") and h["result"].get("result_id") == j["result"].get("result_id")),
  ("no client errors", not h["errors"] and not j["errors"]),
]
ok = True
for name, passed in checks:
    print(("PASS " if passed else "FAIL ") + name)
    ok = ok and bool(passed)
print("READY:", "PASS" if ok else "FAIL", d)
sys.exit(0 if ok else 1)
PY
