# Agent Guidelines for homelab

Start-of-session orientation only. Durable rules that must hold deep into a session live in hooks or CI, not here — a file read once at the top can't be trusted to keep enforcing anything.

## What this is

Config and compose files for a personal homelab, one service per directory. Larger standalone projects live in their own repos.

## Substrate

Docker-compose and k3s both run here; `docs/current-state.md` says what runs where. Direction and sequencing live in a private roadmap document outside this repo. Debian's cloud images don't ship `qemu-guest-agent`, so `proxmox_virtual_environment_vm` resources need `agent.timeout` set short (not the 15m default) until Ansible installs it — otherwise `plan`/`apply`/`destroy` hang.

Run Terraform from `terraform/` after `set -a && source .env && set +a` (see `terraform/README.md`); without it, `plan` fails on the missing Bitwarden token. Every disk attached to a VM must be declared in that VM's `.tf`: the provider detaches undeclared disks on any in-place update, and `plan` hides the removal among unchanged blocks. Before applying a VM change, compare `qm config <vmid>` on pve with the resource's `disk` blocks. `reboot_after_update` defaults to true, so a change the VM can't take live (disk attach, CPU) reboots it — on chimaera that's a full k3s outage; say so before applying.

## Hosts

- **pve** — the single physical Proxmox host. `pve` is only the SSH/DNS target; its actual Proxmox cluster node name (needed for Terraform's `node_name`) is **pve0**.
- **mrgutsy** — a separate cloud VM (OCI), not on the home network. **Its address is deliberately not committed to this repo — do not add it to any tracked file.**

What runs on each host, and the routes serving it, is inventory — see "Where state lives" below rather than assuming this list is current.

Each host's Caddy config lives under `caddy/<host>/`. Which Caddyfile a service's route appears in is the authoritative record of which host it runs on.

## Where state lives

- **`docs/current-state.md`** — hand-written current inventory: what runs where, storage, network, backup. Check here first for "what does the lab look like right now" — including per-host workload lists, which are deliberately not duplicated in this file.
- **Live systems** — anything a running system already knows (versions, capacity, health) is queried, not transcribed. Don't copy figures from `qm list`, `pvesm status`, or similar into a doc; they go stale immediately and the doc becomes actively misleading.
- **Obsidian vault** (private, not in this repo) — roadmap, sequencing, hardware planning, and the reasoning behind them.
- **GitHub Issues** (https://github.com/laforcem/homelab/issues) — day-to-day task status. The vault roadmap sets direction and reasoning; it deliberately doesn't track task-level status itself.

## Local setup

Fresh clone, run once:

```
git config core.filemode false
```

The repo's only executable scripts (`media-backup/backup-media.sh`, `speedtest/custom-cont-init.d/99-configure-prometheus.sh`) report inconsistent permission bits through WSL mounts, which makes git — and any editor's git panel — flag them as modified with no actual content change. This setting is per-clone; `git clone` never carries local config, so it has to be run again after every fresh clone or worktree.

## Conventions

- Routes are templated as `*.$DOMAIN` / `*.lan.$DOMAIN` — never hardcode the real domain in a tracked file.
- Internal topology (VLANs, RFC1918 addresses) is fine to commit. Credentials, MAC addresses, and personal identifying information (real names, etc.) are not — sanitize before committing anything captured from a live system (router output, DHCP leases, and the like).
- When you finish a unit of work that changes what's running or how it's configured, update `docs/current-state.md` in the same change.
