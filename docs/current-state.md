# Current State

Last verified: 2026-08-18, against live hosts (`qm list`, `docker ps`, `pvesm status`, `ansible-playbook`, `tailscale status`) — not from the compose files alone.

This file describes what's running today, on docker-compose. It gets rewritten wholesale at the k3s migration rather than incrementally patched toward that future — see the documentation plan (private, Obsidian vault) for why. Per `AGENTS.md`'s routing rule, anything a live system can answer belongs there, not here — this file stops at facts nothing live currently reports.

## Hosts

| Host | Role | Address | OS |
|---|---|---|---|
| `pve` | Proxmox VE, physical, 6c/6t | `192.168.10.2` | PVE 9.2.10 |
| `vm100` | VMID 100, docker-compose | `192.168.10.100` | Debian 12 |
| `vm101` | VMID 101, docker-compose | `192.168.40.101` | Debian 12 |
| `pbs` | VMID 102, Proxmox Backup Server | `192.168.10.103` | PBS 4.2.0 |
| `constrainer` | VMID 104, vm100 successor — Ansible-configured (#52); vm100's real workloads not yet migrated (#53) | `192.168.10.104` | Debian 13 |
| `mrgutsy` | Cloud VM (OCI), docker-compose | not committed — see AGENTS.md | Ubuntu 24.04 |

`mrgutsy` deliberately holds only workloads that don't belong on the home network: bandwidth/latency-sensitive voice and game traffic, plus a handful of services repatriated ahead of the k3s migration. Everything else runs on `pve`'s VMs.

## Workloads

Each host's Caddy config (`caddy/<host>/conf/Caddyfile`) is the source of truth for which host serves which route — this table is a snapshot of it, not a replacement for it.

**vm100** — internal-only (`*.lan.$DOMAIN`), VLAN 10:

| Service | Route |
|---|---|
| adguard-home | `adguard.lan.$DOMAIN` |
| portainer | `portainer.lan.$DOMAIN` |
| speedtest-grafana | `grafana.lan.$DOMAIN` |
| speedtest-tracker | `speedtest.lan.$DOMAIN` |
| portainer_agent, oci-backup, porkbun-ddns, router-sync, speedtest-influxdb | not proxied |

**constrainer** — trusted VLAN 10, not yet proxied through Caddy:

| Service | Route |
|---|---|
| doco-cd (+ docker-socket-proxy) | not proxied — self-managed via git-push polling against this repo's `doco-cd/` directory, no SSH needed to redeploy |

**vm101** — external (`$DOMAIN`), VLAN 40 (DMZ):

| Service | Route |
|---|---|
| immich_server | `photos.$DOMAIN` |
| feishin | `music.$DOMAIN` |
| navidrome | `nd.$DOMAIN` |
| icloudpd, icloudpd-telegram-bot, samba, audiomuse-ai (flask + worker) | not proxied |

**mrgutsy** — external (`$DOMAIN`):

| Service | Route |
|---|---|
| actual | `budget.$DOMAIN` |
| actual-mcp | `budget.$DOMAIN/mcp` |
| audiobookshelf | `audiobooks.$DOMAIN` |
| miniflux | `miniflux.$DOMAIN` |
| tandoor-web | `recipes.$DOMAIN` |
| teamspeak | has its own subdomain, but not through Caddy — it's raw UDP (9987), not HTTP, so it can't be reverse-proxied; the DNS record points straight at mrgutsy |
| herobrines-mansion, mc-sloth-kingdom (Minecraft) | not proxied, no subdomain — voice/game traffic, kept off the home network deliberately |


## Storage

`pve` has three storage pools, none shared with the others:

| Pool | Backing | Holds |
|---|---|---|
| `local-zfs` (`rpool`) | 238GB NVMe, ZFS | All three VMs' OS/boot disks |
| `truelab` | ~500GB HDD, LVM-thin | vm101's media data disk only (`/mnt/lab`) |
| `pbs-ssd` | 180GB SSD | The `pbs` VM's local datastore (`backups`) |
| `pbs-b2-cache` | ~500GB HDD (ex-`lab` drive) | Local cache for the `pbs` VM's B2-backed offsite datastore (`b2-offsite`) |

The former `local-lvm` (LVM-thin on the NVMe) no longer exists — it was migrated to `local-zfs` (issue #34). Current pool usage is live state; query it (`pvesm status`, `zpool list`) rather than trusting a number written here.

## Backup

- **PBS** — whole-VM backup for vm100 and vm101's OS disks (vm101's media disk exceeds the datastore and is out of scope), landing in the local `backups` datastore. A nightly sync job (`backups-to-b2`, 04:30, via a loopback remote) copies it offsite into a second, Backblaze B2-backed datastore (`b2-offsite`).
- **vm101 media library** (`truelab`, `/mnt/lab`) — `media-backup/` rclone-syncs it to a Dropbox remote (`dropbox:Homelab/<name>`), independent of PBS.
- **`audiobookshelf`** mounts a Dropbox rclone remote directly (`dropbox:Homelab/audiobookshelf/audiobooks`) rather than being backed up after the fact.
- **`oci-backup`** (on vm100) backs up OCI-hosted resources — see `oci-backup/README.md` for scope.

## Network

VLANs, by number and purpose (router config: `.network/iptables.sh`):

| VLAN | Bridge | Purpose |
|---|---|---|
| 10 | `br0` | Servers — `pve` and its VMs |
| 20 | `br52` (`IOT_BR`) | IoT |
| 30 | `br54` (`GST_BR`) | Guest |
| 40 | `br53` (`DMZ_BR`) | DMZ — `vm101` lives here |

The router enforces isolation between VLANs via custom iptables chains (`IOT_FWD`, `DMZ_FWD`, etc.) rather than relying on switch-level ACLs alone.

`constrainer` also runs as a Tailscale subnet router, advertising both `192.168.10.0/24` and `192.168.40.0/24` (mirroring vm100's existing subnet-router config — both currently advertise the same routes, ahead of vm100's eventual decommission in #53).

## Terraform

`terraform/` provisions `pve` VMs via `bpg/proxmox`, authenticating with an API token pulled from Bitwarden Secrets Manager — no secrets committed, state is local-only. A Debian 13 cloud-init template exists (VMID 103, `debian-template`). `constrainer.tf` clones it into VMID 104 (`192.168.10.104`, VLAN 10) — the vm100 successor from #51. Workload migration is #53, not done yet.

## Ansible

`ansible/` configures `constrainer` (#52) — a shared `common` role (every host, including the future k3s node) plus a `utility-services` role (constrainer-only). Run via `cd ansible && set -a && source ../terraform/.env && set +a && ansible-playbook playbooks/main.yaml` (see `ansible/README.md`).

- **`common`** — `qemu-guest-agent`, unattended-upgrades, timezone/NTP, SSH hardening (no password auth, no root login), `ufw` (deny-by-default, SSH + Tailscale allowed, plus routed-traffic rules for constrainer's subnet-router role).
- **`utility-services`** — Tailscale (reusable auth key from the same Bitwarden Secrets Manager project Terraform uses; rotates every 90 days), Docker + Compose plugin, and Doco-CD — deployed once via Ansible bootstrap, then self-managing: it polls this repo's `doco-cd/` directory and redeploys itself on a git push, no SSH needed after the initial bootstrap. Doco-CD talks to Docker through a `docker-socket-proxy` sidecar (endpoint allow-list) rather than mounting `/var/run/docker.sock` directly.

## Known gaps as of this writing

- No Grafana/Prometheus cluster observability yet (roadmap Phase 0, not started).
- `speedtest-tracker`, `speedtest-grafana`, and `samba` run `:latest` rather than a pinned tag — the only unpinned images in the estate.
