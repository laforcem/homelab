<!-- AI AGENTS: READ THIS
When editing this file, DO:
- Be as clear and concise as possible
- Write as few words as are grammatically necessary to convey important information
- Add information that is descriptive of the current state and nothing more
- Use technical terms when they are descriptive and necessary
DO NOT:
- Add any narratives, stories, or long tales
- Be overly verbose
- Use unnecessary jargon in places where plain English suffices
 -->

# Current State

Last verified: 2026-09-15, against live hosts (`qm list`, `docker ps`, `pvesm status`, `ansible-playbook`, `tailscale status`, `pvesh`, `proxmox-backup-manager`) — not from the compose files alone.

This file describes what's running today, on docker-compose. It gets rewritten wholesale at the k3s migration rather than incrementally patched toward that future — see the documentation plan (private, Obsidian vault) for why. Per `AGENTS.md`'s routing rule, anything a live system can answer belongs there, not here — this file stops at facts nothing live currently reports.

## Hosts

| Host | Role | Address | OS |
|---|---|---|---|
| `pve` | Proxmox VE, physical, 6c/6t | `192.168.10.10` | PVE 9.2.10 |
| `pbs` | VMID 102, Proxmox Backup Server | `192.168.10.11` | PBS 4.2.0 |
| `warden` | VMID 104, vm100's successor — fully migrated (#51–#53), all workloads live here | `192.168.10.12` | Debian 13 |
| `vm101` | VMID 101, docker-compose | `192.168.40.101` | Debian 12 |
| `valet` | VMID 105, personal assistant host — workload config lives in the separate Moltron repo, not this one | `192.168.10.14` | Debian 13 |
| `mrgutsy` | Cloud VM (OCI), docker-compose | not committed — see AGENTS.md | Ubuntu 24.04 |

`vm100` has been fully decommissioned — VMID 100 no longer exists on `pve0` (confirmed live, not just emptied of containers).

Static IP allocation on VLAN 10 (`192.168.10.0/24`): `.1-9` network equipment, `.10-19` servers/hypervisors, `.20-29` reserved for other static infra, `.100-254` DHCP pool. `warden`/`pve`/`pbs`/`valet` all sit in `.10-19`; `vm100`'s old `.100` address predated the scheme and is now retired along with the VM.

`mrgutsy` deliberately holds only workloads that don't belong on the home network: bandwidth/latency-sensitive voice and game traffic, plus a handful of services repatriated ahead of the k3s migration. Everything else runs on `pve`'s VMs.

## Workloads

Each host's Caddy config (`caddy/<host>/conf/Caddyfile`) is the source of truth for which host serves which route — this table is a snapshot of it, not a replacement for it.

**warden** — trusted VLAN 10, internal-only (`*.lan.$DOMAIN`):

| Service | Route |
|---|---|
| adguard-home | `adguard.lan.$DOMAIN` |
| speedtest-grafana | `grafana.lan.$DOMAIN` |
| speedtest-tracker | `speedtest.lan.$DOMAIN` |
| openclaw (proxied on warden, runs on `valet`) | `openclaw.lan.$DOMAIN` |
| caddy, doco-cd (+ docker-socket-proxy), doco-cd-updater, oci-backup, porkbun-ddns, router-sync, speedtest-influxdb | not proxied |

doco-cd (main instance) polls this repo and deploys everything above except itself; a second, minimal `doco-cd-updater` instance (scheduler disabled) polls independently and redeploys the main instance, since a single instance can't safely redeploy itself (see [doco-cd's Self-Updating docs](https://doco.cd/latest/Advanced/Self-Updating/)).

router-sync's image source lives in a separate repo ([`laforcem/router-sync`](https://github.com/laforcem/router-sync), public, GH Actions builds/pushes to GHCR) — this repo only holds its deployment config.

**vm101** — external (`$DOMAIN`), VLAN 40 (DMZ):

| Service | Route |
|---|---|
| immich_server | `photos.$DOMAIN` |
| feishin | `music.$DOMAIN` |
| navidrome | `nd.$DOMAIN` |
| icloudpd, icloudpd-telegram-bot, samba, audiomuse-ai (flask + worker) | not proxied — samba serves two SMB shares off `/mnt/lab`: `[homelab]` (full tree, `malc` only) and `[music]` (`/mnt/lab/music`, read/write for `malc` and `moltron`, the latter for the OpenClaw agent on the home LAN) |

**valet** — trusted VLAN 10, admin access via Tailscale only:

| Service | Route |
|---|---|
| OpenClaw (personal assistant) | proxied via warden's Caddy at `openclaw.lan.$DOMAIN`; config and deploy tooling live in the separate Moltron repo, not this one |

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

Portainer is retired outright (not carried to warden or anywhere else) — Doco-CD replaces it for GitOps-style compose deploys.

## Storage

`pve` has three storage pools, none shared with the others:

| Pool | Backing | Holds |
|---|---|---|
| `local-zfs` (`rpool`) | 238GB NVMe, ZFS | All VMs' OS/boot disks |
| `truelab` | ~500GB HDD, LVM-thin | vm101's media data disk only (`/mnt/lab`) |
| `pbs-ssd` | 180GB SSD | The `pbs` VM's local datastore (`backups`) |
| `pbs-b2-cache` | ~500GB HDD (ex-`lab` drive) | Local cache for the `pbs` VM's B2-backed offsite datastore (`b2-offsite`) |

The former `local-lvm` (LVM-thin on the NVMe) no longer exists — it was migrated to `local-zfs` (issue #34). Current pool usage is live state; query it (`pvesm status`, `zpool list`) rather than trusting a number written here.

## Backup

- **PBS** — whole-VM backup for vm101/warden/valet's OS disks (vm101's media disk exceeds the datastore and is out of scope), landing in the local `backups` datastore, via a single vzdump job (daily 03:00, `vmid: 101,104,105`). A nightly sync job (`backups-to-b2`, 04:30, via a loopback remote) copies it offsite into a second, Backblaze B2-backed datastore (`b2-offsite`, bucket `starcliff-lab`). Both jobs are monitored via PVE's/PBS's native webhook notification system — a matcher on job type/severity routes success and failure to separate healthchecks.io check URLs. B2 bucket lifecycle should be set to "Keep only the last version of the file" (not the B2 default), otherwise PBS's own prune/GC deletes don't actually free B2 storage.
- **vm101 media library** (`truelab`, `/mnt/lab`) — `media-backup/` rclone-syncs it to a Dropbox remote (`dropbox:Homelab/<name>`), independent of PBS.
- **`audiobookshelf`** mounts a Dropbox rclone remote directly (`dropbox:Homelab/audiobookshelf/audiobooks`) rather than being backed up after the fact.
- **`oci-backup`** (on warden) backs up OCI-hosted resources — see `oci-backup/README.md` for scope.
- **AdGuard Home's config** (warden, `adguard-home_config` volume) — an `offen/docker-volume-backup` sidecar tars it nightly (03:15) to Dropbox (`Homelab/adguard-home`), 30-day retention, healthchecks.io-monitored.
- **speedtest-tracker's config/DB** (warden, `speedtest-tracker` volume) — same pattern, nightly at 03:30, to `Homelab/speedtest-tracker`, 30-day retention, healthchecks.io-monitored. speedtest-influxdb and speedtest-grafana are deliberately not backed up this way — their data (speedtest history, dashboard layout) is regenerable and lower-value than config state.

## Network

VLANs, by number and purpose (router config: `.network/iptables.sh`):

| VLAN | Bridge | Purpose |
|---|---|---|
| 10 | `br0` | Servers — `pve` and its VMs |
| 20 | `br52` (`IOT_BR`) | IoT |
| 30 | `br54` (`GST_BR`) | Guest |
| 40 | `br53` (`DMZ_BR`) | DMZ — `vm101` lives here |

The router enforces isolation between VLANs via custom iptables chains (`IOT_FWD`, `DMZ_FWD`, etc.) rather than relying on switch-level ACLs alone.

`warden` runs as the sole Tailscale subnet router, advertising both `192.168.10.0/24` and `192.168.40.0/24` (vm100's identical advertisement was torn down along with removing Tailscale from vm100 entirely). `warden` itself does not use Tailscale for its own DNS resolution (`--accept-dns=false`) — its resolver claiming the default route conflicted with AdGuard Home needing `0.0.0.0:53`, and was unreliable for general internet lookups once systemd-resolved's stub listener was disabled for the same reason.

## Terraform

`terraform/` provisions `pve` VMs via `bpg/proxmox`, authenticating with an API token pulled from Bitwarden Secrets Manager — no secrets committed, state is local-only. A Debian 13 cloud-init template exists (VMID 103, `debian-template`). `warden.tf` and `valet.tf` provision VMID 104/105 respectively. All of vm100's workloads migrated to warden and vm100 itself has been decommissioned (#51–#53 complete).

## Ansible

`ansible/` configures `warden` — a shared `common` role (every host, including the future k3s node) plus a `utility-services` role (warden-only). Run via `cd ansible && set -a && source ../terraform/.env && set +a && ansible-playbook playbooks/main.yaml` (see `ansible/README.md`).

- **`common`** — static hostname (set to match the inventory hostname), `qemu-guest-agent`, unattended-upgrades, timezone/NTP, SSH hardening (no password auth, no root login), `ufw` (deny-by-default, SSH + Tailscale allowed, plus routed-traffic rules for warden's subnet-router role).
- **`utility-services`** — disables systemd-resolved's stub DNS listener (AdGuard Home needs `0.0.0.0:53`), Tailscale (reusable auth key from the same Bitwarden Secrets Manager project Terraform uses; rotates every 90 days; `--accept-dns=false`, see Network above), Docker + Compose plugin, and Doco-CD — deployed once via Ansible bootstrap, then self-managing: it polls this repo's `doco-cd/` and `doco-cd-updater/` directories and redeploys on a git push, no SSH needed after the initial bootstrap. A single doco-cd instance can't safely redeploy itself (stopping its own container kills the process driving its own recreation), so a second, minimal `doco-cd-updater` instance — scheduler disabled, no `external_secrets` of its own — polls independently and is the one that redeploys the main instance; the main instance deploys everything else, including `doco-cd-updater` itself. Both instances talk to Docker through the same shared `docker-socket-proxy` sidecar (endpoint allow-list) rather than mounting `/var/run/docker.sock` directly.

## Known gaps as of this writing

- No Grafana/Prometheus cluster observability yet (roadmap Phase 0, not started) — distinct from the standalone `speedtest-grafana` instance already running on warden.
- `speedtest-tracker`, `speedtest-grafana`, and `samba` run `:latest` rather than a pinned tag — the only unpinned images in the estate.
- `speedtest-grafana`'s Telegram alerting was removed (not just disabled) after it turned out an empty bot token crash-loops Grafana's whole provisioning module rather than failing gracefully — will get rebuilt when alerting gets real attention.
- `router-sync`'s AGH API user (`router-sync`, a dedicated AdGuard Home account, not the personal admin login) was created directly in AGH's live config — AGH has no web UI for user management, config-file only. Not reproducible from a fresh deploy without redoing this by hand.
- speedtest-influxdb, speedtest-grafana, and doco-cd's own `/data` volume have no app-level backup yet (tracked in [#95](https://github.com/laforcem/homelab/issues/95)).
