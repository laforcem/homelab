<!-- AI AGENTS: READ THIS
When editing this file, DO:
- Be as clear and concise as possible
- Write as few words as are grammatically necessary to convey important information
- Add information that is descriptive of the current state and nothing more
- Use technical terms when they are descriptive and necessary
- Include information about hardware, which is less mutable than software
DO NOT:
- Add any narratives, stories, or long tales
- Be overly verbose
- Use unnecessary jargon in places where plain English suffices
- Add information that will naturally rot: volume sizes, memory usage, or anything that could otherwise be accessed by pulling live state. Software is more mutable than software.
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
| `chimaera` | VMID 100, vm101's successor — single-node k3s cluster, DMZ VLAN 40, provisioned via Terraform (#54) and configured via Ansible (#99); no workloads migrated yet | `192.168.40.10` | Debian 13 |
| `mrgutsy` | Cloud VM (OCI), docker-compose | not committed — see AGENTS.md | Ubuntu 24.04 |

`vm100` was fully decommissioned, freeing VMID 100 for reuse — Proxmox's next-free-VMID allocation then assigned it to the unrelated `chimaera` VM described above.

Static IP allocation on VLAN 10 (`192.168.10.0/24`): `.1-9` network equipment, `.10-19` servers/hypervisors, `.20-29` reserved for other static infra, `.100-254` DHCP pool. `warden`/`pve`/`pbs`/`valet` all sit in `.10-19`; `vm100`'s old `.100` address predated the scheme and is now retired along with the VM. VLAN 40 (`192.168.40.0/24`) has no formal ranges yet — `vm101` (`.101`) predates any scheme, `chimaera` (`.10`) follows VLAN 10's "servers start at `.10`" convention.

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

doco-cd (main instance) polls this repo and deploys everything above except itself; a second, minimal `doco-cd-updater` instance (scheduler disabled) polls independently and redeploys the main instance, since a single instance can't safely redeploy itself (see [doco-cd's Self-Updating docs](https://doco.cd/latest/Advanced/Self-Updating/)). Both instances reach Docker through a shared `docker-socket-proxy` sidecar rather than mounting `/var/run/docker.sock` directly.

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

- **PBS** — whole-VM backup for vm101/warden/valet/chimaera's OS disks (vm101's media disk exceeds the datastore and is out of scope), landing in the local `backups` datastore, via a single vzdump job (daily 03:00, `vmid: 101,104,105,100`). A nightly sync job (`backups-to-b2`, 04:30, via a loopback remote) copies it offsite into a second, Backblaze B2-backed datastore (`b2-offsite`, bucket `starcliff-lab`). Both jobs are healthchecks.io-monitored via PVE's/PBS's native webhook+matcher notifications (success/failure ping separate check URLs). B2 bucket lifecycle must be "Keep only the last version of the file" (not the B2 default), so PBS's own prune/GC deletes actually free B2 storage.
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

`warden` runs as the sole Tailscale subnet router, advertising `192.168.10.0/24` and `192.168.40.0/24`. It does not use Tailscale for its own DNS resolution (`--accept-dns=false`) — that would conflict with AdGuard Home needing `0.0.0.0:53`.

## Terraform

`terraform/` provisions `pve` VMs via `bpg/proxmox`, authenticating with an API token pulled from Bitwarden Secrets Manager — no secrets committed, state is local-only. A Debian 13 cloud-init template exists (VMID 103, `debian-template`). `warden.tf` and `valet.tf` provision VMID 104/105 respectively. All of vm100's workloads migrated to warden and vm100 itself has been decommissioned (#51–#53 complete). `chimaera.tf` provisions the k3s node VM (#54, VMID 100 — reused from decommissioned vm100), DMZ VLAN 40 (`vlan_id = 40` on the shared `vmbr0` bridge, unlike `warden`/`valet`'s untagged VLAN 10 network device).

## Ansible

`ansible/` configures `warden` and `chimaera` — a shared `common` role (every host) plus host-specific roles: `utility-services` (warden-only) and `k3s` (chimaera-only, #99). Run via `cd ansible && set -a && source ../terraform/.env && set +a && ansible-playbook playbooks/main.yaml` (see `ansible/README.md`).

- **`common`** — static hostname (set to match the inventory hostname), `qemu-guest-agent`, unattended-upgrades, timezone/NTP, SSH hardening (no password auth, no root login), `ufw` (deny-by-default, SSH + Tailscale allowed, plus routed-traffic rules for warden's subnet-router role).
- **`utility-services`** — disables systemd-resolved's stub DNS listener (AdGuard Home needs `0.0.0.0:53`), Tailscale (reusable auth key from the same Bitwarden Secrets Manager project Terraform uses; rotates every 90 days; `--accept-dns=false`, see Network above), Docker + Compose plugin, and Doco-CD — deployed once via Ansible bootstrap, then self-managing via git push (see Workloads above for the doco-cd/doco-cd-updater split), no SSH needed after the initial bootstrap.
- **`k3s`** — installs k3s with defaults (Traefik ingress, ServiceLB, `local-path-provisioner`), no per-app workloads yet. `--tls-san k3s.lan.$DOMAIN` is baked in at install time so the control plane is reachable by name instead of raw IP; `k3s.lan.$DOMAIN` is a manual AdGuard Home DNS rewrite to `192.168.40.10` (not tracked as code — AdGuard's config isn't a file in this repo). `ufw` opens `6443/tcp` (kube API) from the LAN (`192.168.10.0/24`) and Tailscale's range (`100.64.0.0/10`), and `443/tcp` (ingress, HTTPS only) from the DMZ subnet. The role also fetches the kubeconfig to the operator's `~/.kube/config` (rewritten to point at `k3s_tls_san` and named `starcliff`, per `group_vars/k3s.yaml`), plus a WSL-interop copy to the Windows-side `%USERPROFILE%\.kube\config`. Local `kubectl`/`kubectx`/`fzf` tooling and aliases are tracked in `laforcem/dotfiles`, not here.

## Known gaps as of this writing

- No Grafana/Prometheus cluster observability yet (roadmap Phase 0, not started) — distinct from the standalone `speedtest-grafana` instance already running on warden.
- `speedtest-tracker`, `speedtest-grafana`, and `samba` run `:latest` rather than a pinned tag — the only unpinned images in the estate.
- `speedtest-grafana`'s Telegram alerting was removed (not just disabled) after it turned out an empty bot token crash-loops Grafana's whole provisioning module rather than failing gracefully — will get rebuilt when alerting gets real attention.
- `router-sync`'s AGH API user (`router-sync`, a dedicated AdGuard Home account, not the personal admin login) was created directly in AGH's live config — AGH has no web UI for user management, config-file only. Not reproducible from a fresh deploy without redoing this by hand.
- speedtest-influxdb, speedtest-grafana, and doco-cd's own `/data` volume have no app-level backup yet (tracked in [#95](https://github.com/laforcem/homelab/issues/95)).
