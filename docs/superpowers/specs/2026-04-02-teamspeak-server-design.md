# TeamSpeak 3 Server Design

**Date:** 2026-04-02
**Branch:** teamspeak-server
**Target host:** mrgutsy (OCI free tier VPS)

## Summary

A minimal, password-protected TeamSpeak 3 server for small private use (2 people). Voice only — no file transfers, no admin query port. Deployed as a single Docker container on mrgutsy, accessible at `ts3.<DOMAIN>` via a DNS A record pointing directly at the VPS IP.

## Architecture

Single container using the official `teamspeak:3.13.7` image with SQLite for storage. No database sidecar needed at this scale. Caddy is not involved — TeamSpeak voice runs on UDP, which Caddy cannot proxy.

```
TS3 client → DNS A record (ts3.<DOMAIN> → mrgutsy IP) → 9987/UDP → teamspeak container
```

## Repository Layout

```
teamspeak/
├── compose.yaml      # Service definition
├── .env              # Secrets and tunables (not in git)
└── .env.example      # Committed template documenting all variables
```

Follows the same per-service directory pattern used by all other mrgutsy services (actual, miniflux, tandoor, etc.).

## compose.yaml

```yaml
name: teamspeak

volumes:
  data:

services:
  teamspeak:
    image: teamspeak:3.13.7
    container_name: teamspeak
    restart: unless-stopped
    ports:
      - "9987:9987/udp"
    environment:
      - TS3SERVER_LICENSE=accept
      - TS3SERVER_DB_PLUGIN=ts3db_sqlite3
      - TS3SERVER_DB_SQLCREATEPATH=create_sqlite
      - TS3SERVER_SERVER_NAME=${TS3_SERVER_NAME}
      - TS3SERVER_SERVER_PASSWORD=${TS3_SERVER_PASSWORD}
      - TS3SERVER_MAXCLIENTS=${TS3_SLOTS}
      - TS3SERVER_WELCOME_MESSAGE=${TS3_WELCOME_MESSAGE}
    volumes:
      - data:/var/ts3server
    healthcheck:
      test: ["CMD-SHELL", "nc -zu localhost 9987 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

`TS3SERVER_LICENSE=accept` is hardcoded in compose (not in `.env`) since it is a required non-secret constant, not a tuneable.

## Environment Variables (.env.example)

```bash
# Server display name shown in the TS3 client
TS3_SERVER_NAME=My TeamSpeak Server

# Password required to join the server
TS3_SERVER_PASSWORD=changeme

# Maximum concurrent users (free license max: 32)
TS3_SLOTS=10

# Message shown to users on connect (optional, leave blank to disable)
TS3_WELCOME_MESSAGE=
```

## Networking & DNS

- Port `9987/UDP` is exposed directly on the mrgutsy host — no Caddy involvement.
- `ts3.<DOMAIN>` is a DNS A record pointing at the mrgutsy public IP (configured outside this repo, in the DNS provider).
- No changes required to `caddy/mrgutsy/Caddyfile` or `caddy/mrgutsy/compose.yaml`.

## Out of Scope

- File transfers (`30033/TCP`) — not needed for this use case
- ServerQuery admin port (`10011/TCP` or `10022/TCP`) — not needed
- Caddy reverse proxy — not applicable for UDP voice traffic
- TeamSpeak web admin interface through Caddy — overkill for this use case
