# Operations: the private-room service

Online play in *Room for Trouble* is optional. Local couch play and saves never need the
service. When a group plays online, one authoritative **room service** runs every room's
hotel simulation. Clients connect to it over secure WebSockets (`wss://`). This document
covers deploying and running it.

Nothing here has been deployed to a public host. Choosing a domain, a host and hosting spend
is the owner's decision (§22.5). The commands below were exercised locally with Docker
Desktop and Caddy's local CA (see *Verification* at the end).

## What runs

| Piece | What it is | Where |
|---|---|---|
| `RoomForTroubleServer.x86_64` | Headless Godot export of this project (`ServerLinux` preset, `dedicated_server` feature). It has no GPU, display or audio. | `build/server/` after `tools/build.sh` |
| Docker image | `debian:bookworm-slim` (pinned digest) with the server binary, running as non-root user `rft` | `server/deploy/Dockerfile` |
| TLS proxy | Caddy 2.8 (pinned digest). It terminates TLS and proxies `/game` to the service. | `server/deploy/Caddyfile` |
| Compose stack | `rft` + `proxy` on a private network; only Caddy publishes ports | `server/deploy/docker-compose.yml` |
| systemd unit (alternative) | Runs the binary directly on a Linux host behind any TLS proxy | `server/deploy/room-for-trouble.service` |

Pinned inputs are recorded in `server/deploy/deploy.lock`.

## Configuration

Command-line arguments come after Godot's `--` separator:

```bash
./RoomForTroubleServer.x86_64 --headless -- --server --port 8080 --max-rooms 16 --data-dir /var/lib/rft
```

Environment overrides take precedence over arguments:

| Variable | Default | Meaning |
|---|---|---|
| `RFT_PORT` | `8080` | Listener port (plain WS; keep it private) |
| `RFT_BIND` | `*` (`0.0.0.0` in the image) | Listener address |
| `RFT_MAX_ROOMS` | `16` | Room cap. **Set `0` to stop new rooms** (drain) while existing rooms finish. |
| `RFT_DATA_DIR` | `user://server` (`/var/lib/rft` in the image) | Checkpoints live in `<data-dir>/rooms/` |
| `RFT_LOG_LEVEL` | `info` | `debug` adds per-message diagnostics |
| `RFT_JOINS_PER_MIN` | `10` | New connections per IP per minute |
| `RFT_CREATES_PER_MIN` | `3` | Room creations per IP per minute |
| `RFT_INPUTS_PER_S` | `60` | Input messages per second per local seat (excess is dropped) |
| `RFT_CHECKPOINT_TTL_H` | `24` | Checkpoints older than this are discarded on start |

The compose file reads these from `server/deploy/.env`. Copy `.env.example` to create it.
Also set `RFT_DOMAIN` and, if needed, `RFT_HTTPS_PORT` / `RFT_HTTP_PORT`. No secrets or
third-party API keys are required.

Built-in limits:
- WebSocket frames are capped at 64 KiB. Protocol messages are capped at 2 KiB for
  hello, join, create and reconnect, 1 KiB for input frames and 8 KiB for anything else.
- An input message carries at most 4 frames.
- Only lobby actions on seats the sender owns are honoured.
- An abandoned lobby closes after 10 minutes.
- A disconnected seat stays reserved for 90 s.

## First deployment (Docker Compose + Caddy)

Prerequisites: a Linux x86-64 host with Docker Engine 24+ and the Compose plugin. You also
need a DNS name that points at the host, with ports 80 and 443 reachable so Caddy can obtain
a certificate.

```bash
# On a build machine (any OS with Godot 4.7.2 + templates):
tools/build.sh --only server             # → build/server/RoomForTroubleServer.x86_64
# Copy the repository's server/deploy/ and build/server/ to the host, then on the host:
cp server/deploy/.env.example server/deploy/.env
$EDITOR server/deploy/.env              # RFT_DOMAIN=rooms.example.org
docker compose -f server/deploy/docker-compose.yml --env-file server/deploy/.env up -d --build
docker compose -f server/deploy/docker-compose.yml --env-file server/deploy/.env ps   # rft should be "healthy"
```

Caddy obtains and renews certificates automatically for `RFT_DOMAIN`. Players then use the
endpoint `wss://rooms.example.org/game`.

**Without Docker:** install the binary to `/opt/rft/`, create a system user `rft` and
`/var/lib/rft`, then install `room-for-trouble.service`. Put any TLS reverse proxy that
supports WebSockets in front, proxying `wss://<domain>/game` to `127.0.0.1:8080`.

## Client endpoint configuration

Players can join any endpoint. In order of precedence:

1. The `RFT_ENDPOINT` environment variable, for a single launch.
2. An `endpoint.txt` file next to the game executable, containing one line such as
   `wss://rooms.example.org/game`. Operators can ship this inside a package, and it
   replaces the built-in placeholder.
3. **Settings → Online** in the game. Typing an endpoint there persists in the player's profile.

For a private CA (a homelab or test environment), set `RFT_TLS_CA_FILE=/path/ca.crt`;
verification stays on. `RFT_ALLOW_INSECURE_TLS=1` disables verification and exists only
for local testing.

## Health checks

- **Protocol probe (authoritative):**
  `RoomForTroubleServer.x86_64 --headless -- --probe ws://127.0.0.1:8080`
  The probe connects, sends a protocol `hello` with `probe: true` and expects `hello_ok`
  carrying `status` (`ready` or `draining`), the room count, the protocol version and the
  content hash. It exits `0` on success and `1` on failure, within about 6 s. The Docker
  `HEALTHCHECK` runs it every 30 s.
- **Through TLS:** `--probe wss://rooms.example.org/game` exercises the whole chain.
- **`/healthz` on Caddy** only shows that the proxy is up. It is **not** proof that the room
  service is healthy.

Neither probe exposes room codes or player identity.

## Logs

The service logs one line per event to stdout, e.g.
`2026-10-23T03:03:51 [info] room 106479 created (1 rooms)`.

- Docker: `docker compose … logs -f rft`
- systemd: `journalctl -u room-for-trouble -f`

Room ids are truncated to 6 hex characters. Room codes and reconnect tokens are never logged.
Malformed input, forged seats and rate-limit drops are counted rather than logged per message.

## Backups

The only state is `<data-dir>/rooms/*.json`, written as an atomic temp-file rename, with
one `.prev` copy each. It holds short-lived checkpoints of rooms in progress. Player
progress lives on the players' machines, so losing the volume loses at most the shifts in
progress.

```bash
docker run --rm -v room-for-trouble_rft-data:/d -v "$PWD":/b debian:bookworm-slim tar czf /b/rft-data-$(date +%F).tgz -C /d .
```

## Restarts and checkpoint recovery

- Every room checkpoints every 5 action seconds and at each shift end.
- On **SIGTERM** (`docker compose restart rft`, `systemctl restart`), the service stops
  accepting rooms, sends every room a "restarting" notice, writes checkpoints and exits
  within about 1 s. The compose `stop_grace_period` is 15 s.
- On start, it restores checkpoints that are younger than `RFT_CHECKPOINT_TTL_H` **and**
  carry the same content hash. Everything else is deleted.
- Clients reconnect automatically with their reconnect token for up to 90 s and resume from
  the checkpoint, losing at most a few seconds of play ("Restored a few seconds of the
  visit"). If restore is impossible, they return to their hub with progress intact.

## Version rollout and rollback

The client and service must share the **protocol version and content hash**. Mismatched
clients are refused at `hello` ("Someone needs to update the game first"), so they can never
share a room.

Rollout:
1. Build the new server (`tools/build.sh --only server`). Note its content hash in the
   startup log line `… listening on …:8080 (max rooms 16, content <hash>)`.
2. **Drain:** set `RFT_MAX_ROOMS=0` and `docker compose up -d`. A restart restores current
   rooms, and no new rooms can be created. Wait until the probe reports `rooms: 0`, or for
   at most one shift (about 6 minutes).
3. Replace `build/server/`, set `RFT_VERSION` and the room cap back, then
   `docker compose up -d --build`.
4. Release the matching client packages.

To keep the old version available for players who have not updated, run it as a second
stack on another path or domain (for example `/game-1.0`) and keep its endpoint in old
packages.

**Rollback:** redeploy the previous image tag (`RFT_VERSION=<old>`). Checkpoints from the
newer content hash are discarded automatically.

## Disabling online play while keeping local play

- **Server side:** `RFT_MAX_ROOMS=0` refuses new rooms with "That room is full".
  `docker compose stop` turns online off completely.
- **Client side:** nothing to do. When the service is unreachable, the online menu says
  "Couldn't reach the server. Local play still works." Couch play, saves and the campaign
  never contact the network.

## Capacity notes

On an Apple M1 Pro, the service simulated one 4-player room for about 0.8 ms of every
33 ms tick. A 1-CPU / 512 MB container (the compose limits) should therefore carry the
default 16 rooms comfortably. This is an estimate, not a load test; see `KNOWN_ISSUES.md`.

## Verification performed

- `tests/net/run_e2e.sh`: a real server process and two clients over local `ws://`.
  Checks create, join by code, two peers, snapshots, movement, forged-seat rejection
  (NET01), reconnect with token (NET02) and a shared result.
- The same test over **`wss://` through the Compose Caddy stack**, with Caddy's local CA
  trusted through `RFT_TLS_CA_FILE`.
- `tests/net/run_restart.sh`: `docker compose restart rft` mid-shift. The client reconnects
  and the room resumes from its checkpoint (NET04).
- `tests/net/run_quad.sh` (NET03 and NET05):
  - 2+1+1 seats from three clients
  - the fifth seat refused as full
  - an abusive client in its own room: garbage, forged seats, wrong shift id, a
    1,500-message flood and an oversized message. The service stayed healthy, other rooms
    saw nothing, and the probe passed.
- `tools/smoke_linux.sh`: the exported server under Docker `linux/amd64`, plus the probe.

**Not verified:** a public internet endpoint, long-running soak tests, and real-world
packet loss or latency (only local loopback and Docker networking).
