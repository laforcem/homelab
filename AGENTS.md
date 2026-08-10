# Agent Guidelines for homelab

Start-of-session orientation only. Durable rules that must hold deep into a session live in hooks or CI, not here — a file read once at the top can't be trusted to keep enforcing anything.

## What this is

Config and compose files for a personal homelab, one service per directory. Larger standalone projects live in their own repos.

## Substrate

Everything below runs on **docker-compose today**. The lab is migrating to k3s + Terraform + GitOps; that migration is tracked outside this repo, in a private roadmap document, and hasn't started yet. Don't assume any Kubernetes tooling exists until a workload actually shows up as manifests in this repo.

## Hosts

- **pve** (`192.168.10.2`) — Proxmox VE, single physical host, 6c/6t. Runs three VMs: **vm100** (`192.168.10.100`), **vm101** (`192.168.40.101`), and **pbs** (`192.168.10.103`, Proxmox Backup Server).
- **mrgutsy** — a separate cloud VM (OCI), not on the home network. **Its address is deliberately not committed to this repo — do not add it to any tracked file.**

What runs on each host, and the routes serving it, is inventory — see "Where state lives" below rather than assuming this list is current.

Each host's Caddy config lives under `caddy/<host>/`. Which Caddyfile a service's route appears in is the authoritative record of which host it runs on.

## Where state lives

- **`docs/current-state.md`** — hand-written current inventory: what runs where, storage, network, backup. Check here first for "what does the lab look like right now" — including per-host workload lists, which are deliberately not duplicated in this file.
- **Live systems** — anything a running system already knows (versions, capacity, health) is queried, not transcribed. Don't copy figures from `qm list`, `pvesm status`, or similar into a doc; they go stale immediately and the doc becomes actively misleading.
- **Obsidian vault** (private, not in this repo) — roadmap, sequencing, hardware planning, and the reasoning behind them.

## Local setup

Fresh clone, run once:

```
git config core.filemode false
```

The repo's only executable scripts (`media-backup/backup-media.sh`, `router-sync/entrypoint.sh`, `speedtest/custom-cont-init.d/99-configure-influxdb.sh`) report inconsistent permission bits through WSL mounts, which makes git — and any editor's git panel — flag them as modified with no actual content change. This setting is per-clone; `git clone` never carries local config, so it has to be run again after every fresh clone or worktree.

## Conventions

- Routes are templated as `*.$DOMAIN` / `*.lan.$DOMAIN` — never hardcode the real domain in a tracked file.
- Internal topology (VLANs, RFC1918 addresses) is fine to commit. Credentials, MAC addresses, and personal identifying information (real names, etc.) are not — sanitize before committing anything captured from a live system (router output, DHCP leases, and the like).
- When you finish a unit of work that changes what's running or how it's configured, update `docs/current-state.md` in the same change.
