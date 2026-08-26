# Agent Guidelines — Proxy Deployment Project

## Project Overview

Multi-architecture Squid-based HTTP proxy with Docker Compose, deployable on amd64/arm64/aarch64 hosts. Bandwidth throttled via Linux `tc` (HTB qdisc) using netfilter marks. Dual-stack networking (IPv4 + IPv6). Only the `proxy.sh` entrypoint script runs; everything else is config/data.

## Repository Layout

| File             | Purpose |
|-------------------|---------|
| `Dockerfile`     | Alpine image installing squid, nginx, bash, cgroup-tools, iproute2-tc. Entry point: `/proxy.sh`. |
| `docker-bake.hcl`| bake target producing tagged images per platform with registry cache-back and provenance/SBOM attestation. |
| `deploy.sh`      | Builds images with buildx bake and runs `docker compose up -d`. |
| `docker-compose.yml` | Compose file: single-stack bridge networks (`dmz-ipv4` on 10.99.5.x/24 with NAT, `dmz-ipv6` with routed gateway mode), explicit IPv6 address assignment, security hardening (least-privilege caps, tmpfs, resource limits). |
| `squid.conf`     | Base proxy config with acl-based slowing list, dynamic gateway IP injection via `[OUT]` token in `proxy.sh`. |
| `proxy.sh`       | Entrypoint: runs `speed.sh`, injects default GW address into squid.conf, then execs squid foreground. |
| `speed.sh`       | Configures tc root qdisc with HTB classes; attached to same interface(s) as proxy. |

## Build & Deploy (human-in-the-loop preferred)

```bash
IPV6_SUBNET=2001:db8:c::1:0/120 IPV6_GATEWAY=2001:db8:c::1:1 IPV6_ADDRESS=2001:db8:c::1:2 ./deploy.sh
export TC_HTB_RATE=200Mbit && ./deploy.sh   # override bandwidth cap
APP_NAME=my-proxy ./deploy.sh  # custom name (default: APP_NAME=proxy)
```

**Preconditions on target host:** `docker` binary and `docker compose` plugin in path. Build happens at deploy time; no pre-built artifacts.

## Squid & TC Mechanics

- `[OUT]` token is replaced by the default gateway IP at container start (via `proxy.sh`).
- Bandwidth throttle: tc class 10:2 gets `fwmark 0x12321`; squid marks packets destined for `slowdownlist` with that mark, creating a controlled drop lane. No-cache policy enforced (`cache deny all`, `no_store` in cache dir).

## Conventions & Gotchas

- Scripts use strict mode implicitly via the deploy file (never sources or forks without explicit error handling; exit on failure).
- Registry credentials come from environment at runtime only — never committed. Buildx builder name defaults to `builder`; recreate it if you hit stale state.
- Network subnet is `/24` by default for IPv4 (`docker-compose.yml`). IPv6 subnet, gateway, and container address are required environment variables (`IPV6_SUBNET`, `IPV6_GATEWAY`, `IPV6_ADDRESS`) and will fail if not provided.
