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

Last verified: 2026-09-25, against live hosts (`qm list`, `docker ps`, `kubectl`, `pvesm status`, `ansible-playbook`, `tailscale status`, `pvesh`, `proxmox-backup-manager`) — not from the compose/manifest files alone.

This file describes what's running today, across docker-compose and k3s, and gets patched incrementally as things change. Per `AGENTS.md`'s routing rule, anything a live system can answer belongs there, not here — this file stops at facts nothing live currently reports.

## Hosts

| Host | Role | Address | OS |
|---|---|---|---|
| `pve` | Proxmox VE, physical, 6c/6t | `192.168.10.10` | PVE 9.2.10 |
| `pbs` | VMID 102, Proxmox Backup Server | `192.168.10.11` | PBS 4.2.0 |
| `warden` | VMID 104, vm100's successor — fully migrated (#51–#53), all workloads live here | `192.168.10.12` | Debian 13 |
| `valet` | VMID 105, personal assistant host — workload config lives in the separate Moltron repo, not this one | `192.168.10.14` | Debian 13 |
| `chimaera` | VMID 100, vm101's successor — single-node k3s cluster, DMZ VLAN 40, provisioned via Terraform (#54) and configured via Ansible (#99); runs Actual, actual-mcp, Audiobookshelf, Immich, Miniflux, Navidrome (+ AudioMuse) and Tandoor in production, and is the public entrypoint (router port-forward) | `192.168.40.10` | Debian 13 |
| `mrgutsy` | Cloud VM (OCI), docker-compose | not committed — see AGENTS.md | Ubuntu 26.04 |

`vm101` (VMID 101, the old docker-compose host) was retired and destroyed once its `lab` drive moved to chimaera (#144, #145); its PBS snapshots remain in the datastore until pruned by hand.

`vm100` was fully decommissioned, freeing VMID 100 for reuse — Proxmox's next-free-VMID allocation then assigned it to the unrelated `chimaera` VM described above.

Static IP allocation on VLAN 10 (`192.168.10.0/24`): `.1-9` network equipment, `.10-19` servers/hypervisors, `.20-29` reserved for other static infra, `.100-254` DHCP pool. `warden`/`pve`/`pbs`/`valet` all sit in `.10-19`; `vm100`'s old `.100` address predated the scheme and is now retired along with the VM. VLAN 40 (`192.168.40.0/24`) has no formal ranges yet — `chimaera` (`.10`) follows VLAN 10's "servers start at `.10`" convention.

`mrgutsy` deliberately holds only workloads that don't belong on the home network: bandwidth/latency-sensitive voice and game traffic (TeamSpeak, Minecraft). Everything else runs on `pve`'s VMs.

## Workloads

Each host's Caddy config (`caddy/<host>/conf/Caddyfile`) is the source of truth for which host serves which route — this table is a snapshot of it, not a replacement for it.

**warden** — trusted VLAN 10, internal-only (`*.lan.$DOMAIN`):

| Service | Route |
|---|---|
| adguard-home | `adguard.lan.$DOMAIN` |
| monitoring-grafana | `grafana.lan.$DOMAIN` |
| speedtest-tracker | `speedtest.lan.$DOMAIN` |
| openclaw (proxied on warden, runs on `valet`) | `openclaw.lan.$DOMAIN` |
| audiomuse-ai (proxied on warden, runs on `chimaera`) | `audiomuse.lan.$DOMAIN` |
| music-assistant | `mass.lan.$DOMAIN` — host-network container (Cast discovery is mDNS multicast). Web UI on 8095 (ufw: `caddy-internal` only); stream server on 8097, which the Google Cast speakers on the IoT VLAN fetch audio from (ufw: `192.168.20.0/24`, plus an `IOT_FWD` accept on the router — IoT → VLAN 10 is otherwise dropped). Speakers are found through the router's Avahi mDNS reflector (`br0` ↔ `br52`). Sources are configured in the MA UI, not in git — state lives in the `/data` volume (`settings.json`, backed up nightly): Navidrome via the Subsonic provider at `https://music.$DOMAIN` (port 443); Spotify via Soloist, paired once from the Spotify app, using a personal Spotify developer Client ID (redirect `https://music-assistant.io/callback`). The web server's Base URL (advanced setting) is `https://mass.lan.$DOMAIN`, so sign-in redirects don't fall back to the raw IP. Soloist's pairing listener uses a random TCP port that `ufw` blocks, so re-pairing needs a temporary rule for that port |
| caddy, doco-cd (+ docker-socket-proxy), oci-backup, porkbun-ddns, ppld-calendar, router-sync, monitoring-prometheus, monitoring-node-exporter, monitoring-cadvisor, monitoring-adguard-exporter | not proxied |
| icloudpd, icloudpd-telegram-bot | not proxied — kept on the trusted VLAN so Apple credentials stay out of the DMZ. Writes the library over NFS to the lab drive (`/mnt/lab/icloud`, automounted by `utility-services`); `require_mount_marker` skips a run if `.mounted` is missing. `state.db` and sign-in sessions live in the local `icloudpd_sessions` volume |

doco-cd polls this repo and deploys everything above, including itself: `SELF_UPDATE_ENABLED` is on (v0.122+) and its own stack is defined in the repo-root `.doco-cd.yaml`, since self-update reads that file rather than the inline `POLL_CONFIG` (see [doco-cd's Self-Updating docs](https://doco.cd/latest/Advanced/Self-Updating/)). A self-update is a brief restart, not zero-downtime, because `container_name` rules out the scale-out strategy. It reaches Docker through a separate `docker-socket-proxy` sidecar rather than mounting `/var/run/docker.sock` directly; Ansible owns that proxy so doco-cd never recreates the connection it is deploying through.

router-sync's image source lives in a separate repo ([`laforcem/router-sync`](https://github.com/laforcem/router-sync), public, GH Actions builds/pushes to GHCR) — this repo only holds its deployment config.

ppld-calendar's image source lives in a separate repo ([`laforcem/ppld-calendar`](https://github.com/laforcem/ppld-calendar), public, GH Actions builds/pushes to GHCR on `v*` tags) — this repo only holds its deployment config, pinned to a version tag.

**chimaera** — external (`$DOMAIN`), VLAN 40 (DMZ), k3s. Public entrypoint: the router's port-forward (`asusrouter`'s `vts_rulelist`, GUI/nvram-managed, not tracked in `.network/iptables.sh`) sends `80`/`443` here:

| Service | Route |
|---|---|
| actual | `budget.$DOMAIN` |
| actual-mcp | `budget.$DOMAIN/mcp` |
| audiobookshelf | `audiobooks.$DOMAIN` |
| miniflux (+ its own Postgres) | `miniflux.$DOMAIN` |
| navidrome (stock web UI), plus AudioMuse-AI (flask + worker, its own Postgres and Redis) | `music.$DOMAIN`; `nd.$DOMAIN` 302-redirects to it (old mobile-app address). Music is `/mnt/lab/music` on chimaera's `lab` drive (local PV, read-only mount); the file watcher sees changes, with a daily scan (`ND_SCANNER_SCHEDULE`) as a backstop. AudioMuse has no public route: warden's Caddy serves it at `audiomuse.lan.$DOMAIN`, via a NodePort restricted to warden |
| tandoor | `recipes.$DOMAIN` |
| samba | not proxied — SMB (445) on the node via ServiceLB, `externalTrafficPolicy: Local` plus a NetworkPolicy allowing only the trusted LAN (`192.168.10.0/24`) and the pod network (ufw can't see this traffic). One share, `[homelab]` (full `/mnt/lab` tree, `malc` only). Valet gets the music library over NFS instead (see the lab-drive entry). Not reachable from the tailnet: chimaera isn't on it. Account password from Bitwarden via ExternalSecret |
| media-backup (CronJob) | not proxied — nightly 01:00 rclone `copy` of `/mnt/lab` libraries to Dropbox, see Backup |
| immich (server, ML, Valkey via the official Helm chart; its own Postgres) | `photos.$DOMAIN`. Uploads (`/mnt/lab/immich`) and the read-only external libraries (`/mnt/lab/icloud`) are on chimaera's `lab` drive (local PVs); `values.yaml` and manifests in `k3s/apps/immich/`, release applied by hand (`helm upgrade --install`, see the header of `values.yaml`) |

Cluster infra (`ansible/roles/cert-manager/`, see below): `cert-manager` issues via Let's Encrypt HTTP-01 — `ingress-shim` only auto-creates a Certificate for an Ingress carrying the `cert-manager.io/cluster-issuer` annotation; `ingressShim.defaultIssuerName` alone does not trigger it. Traefik (k3s-bundled) redirects HTTP to HTTPS on every route except ACME challenge paths.

**valet** — trusted VLAN 10, admin access via Tailscale only:

| Service | Route |
|---|---|
| OpenClaw (personal assistant) | proxied via warden's Caddy at `openclaw.lan.$DOMAIN`; config and deploy tooling live in the separate Moltron repo, not this one |

**mrgutsy** — external (`$DOMAIN`):

| Service | Route |
|---|---|
| teamspeak | has its own subdomain, but not through Caddy — it's raw UDP (9987), not HTTP, so it can't be reverse-proxied; the DNS record points straight at mrgutsy. amd64-only image, run under QEMU emulation registered at boot by the host's `qemu-user-binfmt` package (see `teamspeak/README.md`). Probed from chimaera (`k3s/infra/external-probes/`, UDP handshake every 5 min → Healthchecks) |
| herobrines-mansion, mc-sloth-kingdom (Minecraft) | not proxied, no subdomain — voice/game traffic, kept off the home network deliberately |

Portainer is retired outright (not carried to warden or anywhere else) — Doco-CD replaces it for GitOps-style compose deploys.

## Storage

`pve` has three storage pools, none shared with the others:

| Pool | Backing | Holds |
|---|---|---|
| `local-zfs` (`rpool`) | 238GB NVMe, ZFS | All VMs' OS/boot disks |
| `truelab` | ~500GB HDD, LVM-thin | chimaera's media data disk (`scsi1`, `backup=0`, mounted at `/mnt/lab`); declared in `terraform/chimaera.tf` so applies don't detach it |
| `pbs-b2-cache` | ~500GB USB HDD (ex-`lab` drive) | The `pbs` VM's local datastore (`backups`) and the local cache for its B2-backed offsite datastore (`b2-offsite`), as two virtual disks on one drive |

The former `local-lvm` (LVM-thin on the NVMe) no longer exists — it was migrated to `local-zfs` (issue #34). Current pool usage is live state; query it (`pvesm status`, `zpool list`) rather than trusting a number written here.

## Backup

- **PBS** — whole-VM backup for warden/valet/chimaera's OS disks (chimaera's media disk exceeds the datastore and is out of scope: `backup=0`), landing in the local `backups` datastore, via a single vzdump job (daily 03:00, `vmid: 104,105,100`). A nightly sync job (`backups-to-b2`, 04:30, via a loopback remote) copies it offsite into a second, Backblaze B2-backed datastore (`b2-offsite`, bucket `starcliff-lab`). Both jobs are healthchecks.io-monitored via PVE's/PBS's native webhook+matcher notifications (success/failure ping separate check URLs). B2 bucket lifecycle must be "Keep only the last version of the file" (not the B2 default), so PBS's own prune/GC deletes actually free B2 storage. Retention is a PBS prune job per datastore (`backups-prune` 05:30, `b2-offsite-prune` 05:45; keep 7 daily / 4 weekly / 3 monthly), with weekly GC (Sun 06:30 local, 07:00 B2). The sync job runs with `remove-vanished false`, so B2 is trimmed only by its own prune job, never by an empty or damaged local store.
- **Media library** (`truelab`, `/mnt/lab` on chimaera) — the `media-backup` CronJob (`k3s/apps/media-backup/`) rclone-copies it to a Dropbox remote (`dropbox:Homelab/<name>`), independent of PBS. One Healthchecks check per source ("<Name> Backup (chimaera)"). Dropbox rate-limits small-file writes (`too_many_write_operations`), so a run with many new iCloud sidecar files can take much longer than usual.
- **Audiobookshelf's library** lives on chimaera's `lab` drive (`/mnt/lab/audiobooks`, local PV) and is backed up to `dropbox:Homelab/audiobooks` by `media-backup/`. Its config and metadata are a k3s PVC.
- **Immich** — uploads are `/mnt/lab/immich` (covered by `media-backup/`, thumbs and encoded video excluded). Its Postgres is not backed up by copying its data directory: a nightly `pg-dump` CronJob (02:30) writes `immich.dump` to a separate PVC, VolSync backs that PVC up to `dropbox:Homelab/backups/immich-dump`. The ML model cache is not backed up (re-downloadable).
- **k3s PVCs** (Actual, Audiobookshelf, Miniflux, Tandoor) — VolSync restic to `dropbox:Homelab/backups/<app>`, nightly, 7 daily / 4 weekly / 3 monthly. Tandoor's Postgres is backed up as a nightly `pg_dump` onto its own PVC (`tandoor-dump`, repo `tandoor-dump`); its media PVC has its own repo (`tandoor-media`). rclone must be given the Dropbox app's client id/secret (the token is bound to that app); never leave `spec.trigger.manual` set on a `ReplicationSource`, it pauses the schedule. Miniflux's Postgres is not backed up by copying its data directory: a nightly `pg-dump` CronJob (02:30) writes `miniflux.dump` to a separate PVC, and VolSync backs up that PVC.
- **`oci-backup`** (on warden) backs up OCI-hosted resources — see `oci-backup/README.md` for scope.
- **Music Assistant's `/data`** (warden, `music-assistant_data` volume) — same sidecar pattern, nightly at 04:00, to `Homelab/music-assistant`, 30-day retention, healthchecks.io-monitored.
- **AdGuard Home's config** (warden, `adguard-home_config` volume) — an `offen/docker-volume-backup` sidecar tars it nightly (03:15) to Dropbox (`Homelab/adguard-home`), 30-day retention, healthchecks.io-monitored.
- **speedtest-tracker's config/DB** (warden, `speedtest-tracker` volume) — same pattern, nightly at 03:30, to `Homelab/speedtest-tracker`, 30-day retention, healthchecks.io-monitored. Grafana's state and Prometheus's data are deliberately not backed up this way — dashboards and datasources are provisioned from git and metrics are regenerable.
- **icloudpd's sessions and `state.db`** (warden, `icloudpd_sessions` volume) — same pattern, nightly at 03:45, to `Homelab/icloudpd`, 30-day retention, healthchecks.io-monitored. The photos themselves are on the lab drive, covered by `media-backup/`.

## Network

VLANs, by number and purpose (router config: `.network/iptables.sh`):

| VLAN | Bridge | Purpose |
|---|---|---|
| 10 | `br0` | Servers — `pve` and its VMs |
| 20 | `br52` (`IOT_BR`) | IoT |
| 30 | `br54` (`GST_BR`) | Guest |
| 40 | `br53` (`DMZ_BR`) | DMZ — `chimaera` lives here and is the public `80`/`443` port-forward target |

The router enforces isolation between VLANs via custom iptables chains (`IOT_FWD`, `DMZ_FWD`, etc.) rather than relying on switch-level ACLs alone.

`warden` runs as the sole Tailscale subnet router, advertising `192.168.10.0/24` and `192.168.40.0/24`. It does not use Tailscale for its own DNS resolution (`--accept-dns=false`) — that would conflict with AdGuard Home needing `0.0.0.0:53`.

## Terraform

`terraform/` provisions `pve` VMs via `bpg/proxmox`, authenticating with an API token pulled from Bitwarden Secrets Manager — no secrets committed, state is local-only. A Debian 13 cloud-init template exists (VMID 103, `debian-template`). `warden.tf` and `valet.tf` provision VMID 104/105 respectively. All of vm100's workloads migrated to warden and vm100 itself has been decommissioned (#51–#53 complete). `chimaera.tf` provisions the k3s node VM (#54, VMID 100 — reused from decommissioned vm100), DMZ VLAN 40 (`vlan_id = 40` on the shared `vmbr0` bridge, unlike `warden`/`valet`'s untagged VLAN 10 network device).

## Ansible

`ansible/` configures `warden` and `chimaera` — a shared `common` role (every host) plus host-specific roles: `utility-services` (warden-only), and `k3s` + `cert-manager` (chimaera-only, #99). Run via `cd ansible && set -a && source ../terraform/.env && set +a && ansible-playbook playbooks/main.yaml` (see `ansible/README.md`).

- **`common`** — static hostname (set to match the inventory hostname), `qemu-guest-agent`, unattended-upgrades, timezone/NTP, SSH hardening (no password auth, no root login), `ufw` (deny-by-default, SSH + Tailscale allowed, plus routed-traffic rules for warden's subnet-router role).
- **`utility-services`** — disables systemd-resolved's stub DNS listener (AdGuard Home needs `0.0.0.0:53`), Tailscale (reusable auth key from the same Bitwarden Secrets Manager project Terraform uses; rotates every 90 days; `--accept-dns=false`, see Network above), Docker + Compose plugin, and Doco-CD — deployed once via Ansible bootstrap, then self-managing via git push (self-update, see Workloads above), no SSH needed after the initial bootstrap. Also installs `nfs-common` and automounts the lab drive's `icloud/` at `/mnt/lab/icloud` (`hard`, so an outage blocks rather than exposing the empty local mountpoint).
- **`k3s`** — installs k3s with defaults (Traefik ingress, ServiceLB, `local-path-provisioner`). `--tls-san k3s.lan.$DOMAIN` is baked in at install time so the control plane is reachable by name instead of raw IP; `k3s.lan.$DOMAIN` is a manual AdGuard Home DNS rewrite to `192.168.40.10` (not tracked as code — AdGuard's config isn't a file in this repo). `ufw` opens `6443/tcp` (kube API) from the LAN (`192.168.10.0/24`) and Tailscale's range (`100.64.0.0/10`), and `80/tcp`/`443/tcp` (ingress) from anywhere — chimaera is a public entrypoint, so ingress isn't DMZ-subnet-restricted the way the kube API is. The role also fetches the kubeconfig to the operator's `~/.kube/config` (rewritten to point at `k3s_tls_san` and named `starcliff`, per `group_vars/k3s.yaml`). Local `kubectl`/`kubectx`/`fzf` tooling and aliases are tracked in `laforcem/dotfiles`, not here.
- **`k3s/infra/monitoring/`** — cluster-side observability, three Helm releases in the `monitoring` namespace (hand-run, see its README): `kube-prometheus-stack` (Prometheus, node-exporter, kube-state-metrics; Grafana and Alertmanager off), `loki` (single binary, 14-day retention) and `alloy` (DaemonSet shipping every container's logs to Loki). Prometheus and Loki are published as NodePorts `30090`/`30100` for warden's Grafana, restricted to warden (`192.168.10.12`) by a NetworkPolicy plus `externalTrafficPolicy: Local` — ufw can't restrict NodePort traffic. Nothing is pushed out of the cluster, and the DMZ never initiates a connection to the trusted network. Traefik (PodMonitor), cert-manager and VolSync (ServiceMonitors; VolSync's `/metrics` sits behind an auth proxy, so Prometheus's ServiceAccount is bound to `volsync-metrics-reader`, see `k3s/infra/volsync/metrics.*`) are scraped. The single Grafana lives on warden (`monitoring/`) and queries these over the NodePorts.
- **Lab drive** — the `k3s` role mounts the `lab` drive at `/mnt/lab` (XFS, by UUID, deliberately no `nofail`: a missing drive fails the mount unit instead of local PVs landing on an empty directory on the 32G root disk), runs `nfs-kernel-server`, and exports `/mnt/lab/icloud` to warden and `/mnt/lab/music` to valet (each to its one host only, `all_squash`, uid/gid 1000; ufw allows 2049/tcp from warden and valet only). Valet mounts the music export at `/mnt/music` (`valet-music` role; valet is otherwise managed from the Moltron repo, so it skips the `common` role).
- **`cert-manager`** — installs cert-manager via Helm (`ingressShim.defaultIssuerName: letsencrypt`), a `letsencrypt` `ClusterIssuer` (HTTP-01), and a Traefik `HelmChartConfig` redirecting `web` (`80`) to `websecure` (`443`) except on ACME challenge paths.

## Known gaps as of this writing

- **`k3s/infra/coredns-custom/`** — makes every public name chimaera serves (`budget`, `audiobooks`, `miniflux`, `recipes`, `music`, `nd`) resolve to chimaera inside the cluster. chimaera resolves DNS through 1.1.1.1 (not AdGuard) and the DMZ can't reach its own public address (no hairpin NAT), so cert-manager's HTTP-01 self-check otherwise times out. A newly migrated app's host goes in this file.
- VolSync metrics are scraped but nothing alerts on them, and a stopped backup once went unnoticed for nine days. Candidate alerts are in [#109](https://github.com/laforcem/homelab/issues/109). Audiobookshelf and Miniflux each have a `/healthcheck` probe (`k3s/apps/<app>/health-probe.cronjob.yaml`, every 5 min) that pings a Healthchecks check, so it alerts without Alertmanager; its `/fail` path is untested. TeamSpeak on mrgutsy gets the same treatment from `k3s/infra/external-probes/teamspeak.cronjob.yaml`, a UDP handshake over the public internet.
- Alerting doesn't exist yet (tracked in [#109](https://github.com/laforcem/homelab/issues/109)). The one Grafana on warden has no alert rules; the old Telegram alerting went with `speedtest-grafana`.
- speedtest-tracker's `/prometheus` endpoint has no allowed-IP restriction of its own (`prometheus_allowed_ips` is empty); it is kept off the LAN by a Caddy rule returning 404 for it on `speedtest.lan.$DOMAIN`, while Prometheus scrapes it container-to-container.
- `monitoring-adguard-exporter` has its own AdGuard Home account (`adguard-exporter`), also created directly in AGH's live config (see the `router-sync` account above) — same not-reproducible-from-a-fresh-deploy caveat. AGH has no read-only role, so it still has full API access.
- `monitoring-node-exporter` runs on the host network (real NIC metrics) and listens on `:9100`; ufw only allows that port from `172.21.0.0/16`, the `caddy-internal` Docker network's auto-assigned subnet (`ansible/roles/utility-services`). If that network is ever recreated with a different subnet, Prometheus loses the target until the rule is updated.
- `speedtest-tracker` and `samba` run `:latest` rather than a pinned tag — the only unpinned images in the estate.
- `router-sync`'s AGH API user (`router-sync`, a dedicated AdGuard Home account, not the personal admin login) was created directly in AGH's live config — AGH has no web UI for user management, config-file only. Not reproducible from a fresh deploy without redoing this by hand.
- doco-cd's own `/data` volume has no app-level backup yet (tracked in [#95](https://github.com/laforcem/homelab/issues/95)).
