# Agent Guidelines — Proxy Deployment Project

## Project Overview

Multi-architecture Squid-based HTTP proxy with Docker Swarm, deployable on amd64/arm64/aarch64 nodes labeled `proxy=1`. Bandwidth throttled via Linux `tc` (HTB qdisc) using netfilter marks. Only the `proxy.sh` entrypoint script runs; everything else is config/data.

## Repository Layout

| File             | Purpose |
|-------------------|---------|
| `Dockerfile`     | Alpine image installing squid, nginx, bash, cgroup-tools, iproute2-tc. Entry point: `/proxy.sh`. |
| `docker-bake.hcl`| bake target producing tagged images per platform with registry cache-back and provenance/SBOM attestation. |
| `deploy.sh`      | One-shot build-and-deploy script. Sets up a persistent multi-architecture buildx builder, pushes to registry, runs `docker stack deploy`. |
| `proxy.yml`      | Swarm compose file: encrypted iptables-enabled overlay network (`dmz-${APP_NAME}` on 10.99.5.x/24), single `proxy` service. |
| `squid.conf`     | Base proxy config with acl-based slowing list, dynamic gateway IP injection via `[OUT]` token in `proxy.sh`. |
| `proxy.sh`       | Entrypoint: runs `speed.sh`, injects default GW address into squid.conf, then execs squid foreground. |
| `speed.sh`       | Configures tc root qdisc with HTB classes; attached to same interface(s) as proxy. |

## Build & Deploy (human-in-the-loop preferred)

```bash
./deploy.sh                        # uses defaults; needs DOCKER_REGISTRY_* or falls back to local
export TC_HTB_RATE=200Mbit && ./deploy.sh   # override bandwidth cap per host
APP_NAME=my-proxy STACK_NAME=sp ./deploy.sh  # custom names (default: APP_NAME=proxy, STACK_NAME=$APP_NAME)
```

**Preconditions on target node:** `docker` binary available and in path. Target swarm workers must carry label `node.labels.proxy==1`. Build happens at deploy time; no pre-built artifacts.

## Squid & TC Mechanics

- `[OUT]` token is replaced by the default gateway IP at container start (via `proxy.sh`).
- Bandwidth throttle: tc class 10:2 gets `fwmark 0x12321`; squid marks packets destined for `slowdownlist` with that mark, creating a controlled drop lane. No-cache policy enforced (`cache deny all`, `no_store` in cache dir).

## Conventions & Gotchas

- Scripts use strict mode implicitly via the deploy file (never sources or forks without explicit error handling; exit on failure).
- Registry credentials come from environment at runtime only — never committed. Buildx builder name defaults to `builder`; recreate it if you hit stale state.
- Network subnet is `/24` by default (`proxy.yml`). Recent commits include IPv6 work, though the active branch doesn't expose a `v6` label yet.
