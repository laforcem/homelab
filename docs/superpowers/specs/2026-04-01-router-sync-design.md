---
title: router-sync design
date: 2026-04-01
status: approved
---

# router-sync

A scheduled Docker service that synchronizes custom client names from an ASUS RT-AX86U (Asuswrt-Merlin) router into AdGuard Home persistent clients.

## Problem

AdGuard Home identifies clients by MAC address only when it acts as the DHCP server. Since the router handles DHCP, AGH cannot resolve MAC addresses to friendly names. The router already holds custom client names. This service bridges the gap by reading those names and pushing them to AGH keyed by IP address.

## Approach

A minimal Alpine container runs a shell script on a cron schedule. The script SSHs to the router, joins the custom name list against the active DHCP lease table on MAC address, and reconciles the result against AGH's persistent client list via its REST API.

## Repository layout

```
router-sync/
  Dockerfile
  compose.yaml
  sync.sh
  .env.example
```

The `.env` file and SSH private key are gitignored and live on the host only.

## Data sources

**Router nvram — custom client names**

```
nvram get custom_clientlist
```

Format: entries separated by `<`, each entry delimited by `>`:

```
NAME>MAC>...
```

Fields beyond MAC are ignored. Both `NAME` and `MAC` are extracted.

**Router dnsmasq lease table**

```
cat /var/lib/misc/dnsmasq.leases
```

Format: space-separated fields per line:

```
TIMESTAMP MAC IP HOSTNAME CLIENT_ID
```

Only `MAC` (field 2) and `IP` (field 3) are used.

**Join**

MAC is the key. For each entry in `custom_clientlist`, the script looks up the MAC in the lease table to find the current IP. Entries with no matching lease (device offline or never connected) are skipped. Because `custom_clientlist` stores MACs in uppercase and `dnsmasq.leases` stores them in lowercase, both sides are normalized to lowercase before comparison.

## Sync logic

1. SSH to the router and fetch both data sources in a single session.
2. Parse `custom_clientlist` into a MAC→Name map.
3. Parse `dnsmasq.leases` into a MAC→IP map.
4. Join on MAC to produce an IP→Name map.
5. Fetch the current AGH persistent client list (`GET /control/clients`).
6. Identify router-synced clients by the presence of the `router_sync` tag.
7. For each joined entry:
   - If no AGH client exists for that IP, create one (`POST /control/clients/add`).
   - If a router-synced AGH client exists for that IP with a different name, update it (`POST /control/clients/update`).
   - If a router-synced AGH client exists with the same name, skip it.
8. Remove any router-synced AGH client whose IP no longer appears in the joined result (device left the network or lost its custom name).
9. Leave all AGH clients that lack the `router_sync` tag untouched.

## Container

- **Base image:** `alpine:3.21`
- **Packages:** `openssh-client`, `curl`, `bash`
- **Network:** `caddy-internal` — reaches AGH at `http://adguard-home` without exposing ports
- **Scheduling:** Alpine `crond`; the entrypoint writes a crontab entry from `SYNC_INTERVAL_MINUTES` and runs `crond` in the foreground as PID 1
- **Restart policy:** `always`

## Configuration

All configuration passes in via environment variables. Sensitive values come from a `.env` file on the host.

| Variable | Description | Example |
|---|---|---|
| `ROUTER_HOST` | Router LAN IP or hostname | `192.168.10.1` |
| `ROUTER_USER` | SSH username on the router | `admin` |
| `AGH_URL` | AGH base URL (internal) | `http://adguard-home` |
| `AGH_USER` | AGH username | `admin` |
| `AGH_PASSWORD` | AGH password | — |
| `SYNC_INTERVAL_MINUTES` | How often to run the sync | `10` |

The SSH private key mounts into the container read-only at `/root/.ssh/id_ed25519`. The matching public key must be added to `~/.ssh/authorized_keys` on the router (persisted to `/jffs/.ssh/authorized_keys` on Merlin).

## SSH key setup (one-time)

Generate a dedicated keypair on the homelab host:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/router_sync_id -C "router-sync"
```

Append the public key to the router:

```bash
ssh admin@192.168.10.1 "cat >> /jffs/.ssh/authorized_keys" < ~/.ssh/router_sync_id.pub
```

Capture the router's host key into a `known_hosts` file that mounts into the container. Without this the SSH client will prompt for confirmation and hang:

```bash
ssh-keyscan 192.168.10.1 > router-sync/known_hosts
```

This file is committed to the repo — it contains no secrets.

## Error handling

- If the SSH connection fails, the script logs the error and exits with a non-zero code. `crond` will retry on the next interval.
- If the AGH API returns a non-2xx response, the script logs the response body and continues processing remaining entries rather than aborting the entire run.
- Partial failures are visible in `docker logs router-sync`.

## Logging

The script prints a short summary to stdout after each run:

```
[2026-04-01T10:00:00Z] sync complete: 18 clients fetched, 2 added, 1 updated, 0 removed
```

Docker captures this via its default logging driver.

## Out of scope

- Syncing in the reverse direction (AGH → router)
- Handling devices with multiple MACs as a single merged client
- Alerting on sync failures beyond container logs
