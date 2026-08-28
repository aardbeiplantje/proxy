# Agent Guidelines — Proxy Deployment Project

Multi-architecture Squid HTTP proxy with Docker Compose, deployable on amd64/arm64/aarch64. Bandwidth throttled via Linux `tc` (HTB) using netfilter marks. Dual-stack (IPv4 + IPv6). Only `proxy.sh` runs; everything else is config.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Alpine: squid, nginx, bash, iproute2-tc. Entry: `/proxy.sh`. |
| `docker-bake.hcl` | Multi-platform bake with registry cache. |
| `deploy.sh` | Buildx bake + `docker compose up -d`. |
| `docker-compose.yml` | Dual-stack bridge networks, security hardening. |
| `squid.conf` | ACL proxy rules, `[OUT]` token replaced by GW IP at startup. |
| `proxy.sh` | Entrypoint: runs `speed.sh`, injects GW into squid.conf, execs squid. |
| `speed.sh` | HTB qdisc: parent (10:1) → throttled (10:2, marked) + fast lane (10:30). |

## Deploy

```bash
IPV6_SUBNET=2001:db8:c::1:0/120 IPV6_GATEWAY=2001:db8:c::1:1 IPV6_ADDRESS=2001:db8:c::1:2 ./deploy.sh
TC_HTB_RATE=200Mbit ./deploy.sh          # override rate (default: 50Mbit)
APP_NAME=my-proxy ./deploy.sh             # custom name
```

Requires `docker` + `docker compose` on target. Build at deploy time.

## TC Mechanics

- Squid marks `slowdownlist` packets with `fwmark=0x12321`.
- `speed.sh` routes marked packets to HTB class 10:2 (rate-limited, burst-capable).
- Unmarked traffic goes to class 10:30 (full speed, 200Mbit).
- Parent ceiling (200Mbit) exceeds class rates so unmarked traffic uses spare bandwidth.
- `r2q=10`, `quantum=1500` for low scheduling overhead.

## Gotchas

- Registry credentials from environment only — never committed.
- IPv6 vars (`IPV6_SUBNET`, `IPV6_GATEWAY`, `IPV6_ADDRESS`) are required.
- Buildx builder defaults to `builder`; recreate if stale state.
