# squid-proxy — Docker Swarm Proxy with tc Bandwidth Shaping

Multi-architecture Squid HTTP proxy deployed via Docker Swarm on `proxy==1` nodes (amd64/arm64/aarch64). Rate-limited per-node at the kernel level using traffic control.

## Quick Start

```bash
./deploy.sh                          # deploy to swarm cluster
export TC_HTB_RATE=200Mbit && ./deploy.sh   # custom rate limit
APP_NAME=my-proxy STACK_NAME=sp ./deploy.sh # custom names
```

**Prerequisites:** docker on target, `docker` binary in path. Worker node must have label `proxy==1`. Build happens at deploy time; no pre-built images.

## How It Works

```
[client] → squid proxy (10.99.5.x) → [OUT gateway IP]
                         └── tc HTB marks packets (fwmark 0x12321) → rate-limited
```

### Components

- **Dockerfile** — Alpine image: squid, nginx, bash, cgroup-tools, iproute2-tc. Entrypoint `/proxy.sh`.
- **deploy.sh** — sets up buildx builder, logs in to registry (or local fallback), runs `docker stack deploy`.
- **proxy.yml** — Swarm compose; encrypted overlay network (`dmz-${APP_NAME}` on 10.99.5.x/24), single global service.
- **squid.conf** — acl-based proxy rules, slow list throttling via squid's `mark_client_packet`, cache disabled.
- **proxy.sh** — entrypoint; runs `speed.sh`, injects default GW address into `squid.conf`.
- **speed.sh** — creates HTB qdisc (rate class 10:2 marked with fwmark 0x12321).

### Squid ↔ tc Flow

Squid marks packets destined for the slowdown list (`slowdownlist` acl) with netfilter mark `fwmark=0x12321`. `speed.sh` configures a tc filter to route that same mark into HTB class 10:2, where SFQ pacing enforces the rate limit.

Proxy is transparent — no caching, used as forwarding proxy only.

## Configuration

### Environment Variables (deploy.sh)

| Variable | Default | Description |
|---|---|---|
| `WORKSPACE` | `${BASH_SOURCE%/*}` | Build context directory |
| `APP_NAME` | `proxy` | Swarm stack and network name prefix |
| `STACK_NAME` | `${APP_NAME}` | Swarm compose deploy target |
| `TC_HTB_RATE` | `50Mbit` | Network rate cap per node |
| `DOCKER_REGISTRY`, `USER`, `PASS` | — | Registry auth (or deploys from local) |

### Environment Variables (proxy.sh / speed.sh)

| Variable | Default | Description |
|---|---|---|
| `SQUID_CONFIG_FILE` | `/etc/squid/squid.conf` | Squid config path |
| `TC_HTB_RATE` | `10Mbit` | Rate limit passed to speed.sh |

### Key Squid Settings (squid.conf)

- `[OUT]` token replaced by default GW IP at startup — update if your network changes.
- Cache disabled (`cache deny all`). UFS cache dir configured but won't store anything.
- DNS resolution uses Docker's embedded resolver `127.0.0.11`.
- Nginx is installed alongside Squid (useful for HTTPS termination), but currently commented out.

## File Reference

```
├── Dockerfile          # Alpine base, squash proxy build stages
├── docker-bake.hcl     # Multi-platform bake with registry cache
├── deploy.sh           # Build + push + swarm stack deploy
├── proxy.yml           # Swarm compose: overlay + service spec
├── squid.conf          # Squid rules (acl, delay, logging)
├── proxy.sh            # Entrypoint
├── speed.sh            # tc HTB setup
└── .gitignore          # *~ (editor backups)
```

## Architecture Notes

- **Network**: `dmz-${APP_NAME}` overlay subnet `/24` with iptables encryption (`encrypted: "1"`). Gateway defaults to 10.99.5.1; configure `[OUT]` in `squid.conf`.
- **Deployment mode**: `global` (one container per proxy-labeled node) with stop-first update strategy.
- **Image push**: buildx bake uses registry as both cache-from and output (`type=image,cache-to=registry`). BuildKit enabled.

## Known Issues / TODO

- `speed.sh` hardcodes default GW to `eth0`; may need tuning on multi-homed nodes.
- No systemd integration — container runs proxy in foreground (expected).
