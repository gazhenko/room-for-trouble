#!/usr/bin/env bash
# NET03 + NET05: four seats from three clients (2+1+1), a refused fifth seat,
# and an abusive client in a separate room, all against one real server.
#   tests/net/run_quad.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
DIR=$(mktemp -d /tmp/rft_quad.XXXX)
URL="ws://127.0.0.1:18081"
"$GODOT" --headless --path . -- --server --port 18081 --data-dir "$DIR/server" > "$DIR/server.log" 2>&1 &
S=$!
sleep 3
RSS0=$(ps -o rss= -p $S | tr -d ' ')
pids=()
for role in h j1 j2 j3 x; do
  "$GODOT" --headless --path . --script res://tests/net/net_quad.gd -- --role=$role --url="$URL" --dir="$DIR" > "$DIR/$role.log" 2>&1 &
  pids+=($!)
  sleep 0.7
done
for p in "${pids[@]}"; do wait $p; done
ALIVE=0; kill -0 $S 2>/dev/null && ALIVE=1
RSS1=$(ps -o rss= -p $S 2>/dev/null | tr -d ' ')
# Server still answers a protocol health probe after the abuse.
"$GODOT" --headless --path . -- --probe "$URL" > "$DIR/probe.log" 2>&1; PROBE=$?
kill $S 2>/dev/null; wait $S 2>/dev/null
python3 - "$DIR" "$ALIVE" "$PROBE" "${RSS0:-0}" "${RSS1:-0}" <<'PY'
import json, sys, os
d, alive, probe, rss0, rss1 = sys.argv[1], sys.argv[2] == "1", int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5] or 0)
o = {r: json.load(open(os.path.join(d, r + ".json"))) for r in ["h", "j1", "j2", "j3", "x"]}
h, j1, j2, j3, x = (o[k] for k in ["h", "j1", "j2", "j3", "x"])
rid = h["result"].get("result_id")
checks = [
  ("host has two local seats", len(h["seats"]) == 2),
  ("joiners have one seat each", len(j1["seats"]) == 1 and len(j2["seats"]) == 1),
  ("lobby reached four seats from three clients (NET03)", h["max_lobby_seats"] == 4 and h["max_lobby_peers"] == 3),
  ("fifth seat refused as full (NET03)", j3["rejected"] == "ui.online.full"),
  ("shift simulated four controllable seats", h["seats_seen_in_shift"] == 4 and j1["seats_seen_in_shift"] == 4),
  ("every main-room client moved its avatar", min(h["moved_m"], j1["moved_m"], j2["moved_m"]) > 0.5),
  ("all three main clients got the same result", rid and j1["result"].get("result_id") == rid and j2["result"].get("result_id") == rid),
  ("abusive client saw no other room's data", not x["foreign_room_data"] and x["max_lobby_seats"] == 1),
  ("abusive client ran every attack", x["attacks"] >= 1500),
  ("server answered after the input flood (NET05)", x["hb_after_flood"]),
  ("server process survived (NET05)", alive),
  ("health probe passes after abuse (NET05)", probe == 0),
  ("server memory bounded (<200 MB growth)", rss1 == 0 or rss1 - rss0 < 200_000),
  ("no client errors", not (h["errors"] or j1["errors"] or j2["errors"] or x["errors"])),
]
ok = True
for name, passed in checks:
    print(("PASS " if passed else "FAIL ") + name)
    ok = ok and bool(passed)
print("server RSS %d KB -> %d KB" % (rss0, rss1))
print("QUAD:", "PASS" if ok else "FAIL", d)
sys.exit(0 if ok else 1)
PY
