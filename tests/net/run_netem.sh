#!/usr/bin/env bash
# NET05 under a WAN-like link: the exported Linux server runs in a container
# whose interface adds delay, jitter and packet loss (tc netem), and the real
# e2e / four-seat suites run against it from the host.
#   tests/net/run_netem.sh ["delay 100ms 20ms loss 2%"]
set -uo pipefail
cd "$(dirname "$0")/../.."
NETEM="${1:-delay 100ms 20ms distribution normal loss 2%}"
IMG=rft-netem-server
docker build --platform linux/amd64 -q -t "$IMG" -f - . > /dev/null <<'DOCKER'
FROM debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8
RUN apt-get update && apt-get install -y --no-install-recommends iproute2 libfontconfig1 ca-certificates && rm -rf /var/lib/apt/lists/*
DOCKER
docker rm -f rft-netem >/dev/null 2>&1
docker run -d --name rft-netem --platform linux/amd64 --cap-add NET_ADMIN -p 18095:8080 \
  -v "$PWD/build/server:/srv:ro" "$IMG" bash -c "tc qdisc add dev eth0 root netem $NETEM && tc qdisc show dev eth0 && /srv/RoomForTroubleServer.x86_64 --headless -- --server --port 8080 --data-dir /tmp/rft" > /dev/null
sleep 8
docker logs rft-netem 2>&1 | grep -E "netem|listening" | head -3
ok=0
tests/net/run_e2e.sh ws://127.0.0.1:18095 > /tmp/rft_netem_e2e.txt 2>&1 || ok=1
tail -13 /tmp/rft_netem_e2e.txt
docker rm -f rft-netem > /dev/null
echo "NETEM ($NETEM):" $([ $ok = 0 ] && echo PASS || echo FAIL)
exit $ok
