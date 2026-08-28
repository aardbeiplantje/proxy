# squid-proxy — Docker Compose Proxy with tc Bandwidth Shaping

Multi-architecture Squid HTTP proxy deployed via Docker Compose on a single host (amd64/arm64/aarch64). Rate-limited per-node at the kernel level using traffic control. Dual-stack networking (IPv4 + IPv6).

## Quick Start

```bash
IPV6_SUBNET=2001:db8:c::1:0/120 IPV6_GATEWAY=2001:db8:c::1:1 IPV6_ADDRESS=2001:db8:c::1:2 ./deploy.sh                    # deploy locally
IPV6_SUBNET=... IPV6_GATEWAY=... IPV6_ADDRESS=... export TC_HTB_RATE=200Mbit && ./deploy.sh   # custom rate limit
IPV6_SUBNET=... IPV6_GATEWAY=... IPV6_ADDRESS=... APP_NAME=my-proxy ./deploy.sh # custom name
```

**Prerequisites:** docker and `docker compose` plugin on target host. Build happens at deploy time; no pre-built images.

## How It Works

```
[client] → squid proxy (10.99.5.x) → [OUT gateway IP]
                         → squid proxy (${IPV6_SUBNET}) → [OUT gateway IP]
                          └── tc HTB marks packets (fwmark 0x12321) → rate-limited
```

### Components

- **Dockerfile** — Alpine image: squid, nginx, bash, cgroup-tools, iproute2-tc. Entrypoint `/proxy.sh`.
- **deploy.sh** — sets up buildx bake, runs `docker compose up -d`.
- **docker-compose.yml** — dual-stack compose: bridge networks (dmz-ipv4 + dmz-ipv6), single service.
- **squid.conf** — acl-based proxy rules, slow list throttling via squid's `mark_client_packet`, cache disabled.
- **proxy.sh** — entrypoint; runs `speed.sh`, injects default GW address into `squid.conf`.
- **speed.sh** — creates HTB qdisc with three classes: throttled (10:2, marked), fast lane (10:30), and parent (10:1).

### Squid ↔ tc Flow

Squid marks packets destined for the slowdown list (`slowdownlist` acl) with netfilter mark `fwmark=0x12321`. `speed.sh` configures a tc filter to route that same mark into HTB class 10:2, where SFQ pacing enforces the rate limit.

### HTB Class Hierarchy

```
10: root (htb, rate 200Mbit ceil 200Mbit)
 ├── 10:2  (htb, rate=$TC_HTB_RATE ceil=$TC_HTB_RATE)  ← marked packets (slowdownlist)
 │   └── 2: sfq
 └── 10:30 (htb, rate 200Mbit ceil 200Mbit)            ← unmarked traffic (fast lane)
```

Unmarked traffic flows at full speed (up to 200Mbit). Marked traffic is rate-limited but can burst within its allocated ceiling. The parent ceiling (200Mbit) exceeds individual class rates so unmarked traffic can use spare bandwidth. `r2q=10` and `quantum=1500` reduce scheduling overhead for large transfers.

Proxy is transparent — no caching, used as forwarding proxy only.

## Configuration

### Environment Variables (deploy.sh)

| Variable | Default | Description |
|---|---|---|
| `WORKSPACE` | `${BASH_SOURCE%/*}` | Build context directory |
| `APP_NAME` | `proxy` | Network and volume name prefix |
| `TC_HTB_RATE` | `50Mbit` | Network rate cap per node |
| `DOCKER_IMAGE` | `local/network/proxy:latest` | Image name and tag |
| `IPV6_SUBNET` | — *(required)* | IPv6 subnet (e.g. `2001:db8:c::1:0/120`) |
| `IPV6_GATEWAY` | — *(required)* | IPv6 gateway IP (e.g. `2001:db8:c::1:1`) |
| `IPV6_ADDRESS` | — *(required)* | IPv6 address for the proxy container (e.g. `2001:db8:c::1:2`) |

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
├── Dockerfile          # Alpine base, squid proxy build
├── docker-bake.hcl     # Multi-platform bake with registry cache
├── docker-compose.yml  # Compose: dual-stack bridge + service spec
├── deploy.sh           # Build + compose up
├── squid.conf          # Squid rules (acl, delay, logging)
├── proxy.sh            # Entrypoint
├── speed.sh            # tc HTB setup
└── .gitignore          # *~ (editor backups)
```

## Architecture Notes

- **Network**: Two bridge networks — `dmz-ipv4` (10.99.5.0/24, NAT masquerade) and `dmz-ipv6` (routed gateway mode, internal only).
- **Deployment mode**: Single container on the host, `restart: always`.
- **Image push**: buildx bake uses registry as both cache-from and output (`type=image,cache-to=registry`). BuildKit enabled.

## Known Issues / TODO

- `speed.sh` hardcodes default GW to `eth0`; may need tuning on multi-homed nodes.
- No systemd integration — container runs proxy in foreground (expected).
