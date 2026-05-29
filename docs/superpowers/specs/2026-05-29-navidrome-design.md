# Navidrome Migration Design

**Date:** 2026-05-29  
**Branch:** navidrome-migration  
**Replaces:** Plex (music library only)

## Overview

Add Navidrome as the music server for the homelab, following the established Compose service pattern. Music files live on the production server at `/mnt/lab/music` via plain bind mount. The service sits behind the Caddy reverse proxy at `music.${DOMAIN}`.

## File Structure

```
navidrome/
├── compose.yml
└── .env.example
```

Matches the layout of `plex/`, `audiobookshelf/`, and other services in this repo.

## compose.yml

```yaml
name: navidrome

networks:
  navidrome-caddy:
    name: navidrome-caddy

volumes:
  data:
    name: navidrome-data

services:
  navidrome:
    image: deluan/navidrome:latest
    container_name: navidrome
    restart: unless-stopped
    user: 1000:1000
    networks:
      - navidrome-caddy
    volumes:
      - data:/data
      - /mnt/lab/music:/music:ro
    environment:
      - TZ=America/Denver
      - ND_MUSICFOLDER=/music
      - ND_DATAFOLDER=/data
      - ND_SCANSCHEDULE=@every 24h
      - ND_AGENTS=deezer,listenbrainz,lastfm
      - ND_LASTFM_APIKEY=${LASTFM_API_KEY}
      - ND_LASTFM_SECRET=${LASTFM_SECRET}
      - ND_LASTFM_SCROBBLEFIRSTARTISTONLY=true
```

- No port exposed — traffic enters via Caddy only
- `user: 1000:1000` matches recommended Navidrome permissions and server uid/gid
- Music mounted read-only

## .env.example

```env
LASTFM_API_KEY=your_lastfm_api_key_here
LASTFM_SECRET=your_lastfm_secret_here
```

## Configuration Decisions

**Agent order:** `deezer,listenbrainz,lastfm` — ListenBrainz prioritized over Last.fm for better obscure music coverage. Deezer first as it requires no credentials.

**Scan schedule:** Daily (`@every 24h`). Manual scans available in admin UI at any time.

**Last.fm scrobbling:** `ND_LASTFM_SCROBBLEFIRSTARTISTONLY=true` to avoid duplicate scrobbles for multi-artist tracks. Per-user scrobbling setup done in the Navidrome UI after first login.

**No Spotify integration:** Not a built-in agent in current Navidrome. Would require a plugin if needed later.

**No `navidrome.toml`:** All config via `ND_*` environment variables. Can migrate to toml later if config grows.

## WSL2 Local Testing

The rclone remote is mounted as `Z:` on Windows. To access it from WSL2 for local testing:

```bash
sudo mount -t drvfs 'Z:' /mnt/z
```

Then temporarily change the music volume in compose to `/mnt/z` while testing. The committed config always targets `/mnt/lab/music` (production server path).

## Caddy Integration

Navidrome joins the reverse proxy via the `navidrome-caddy` named network. Caddy config should proxy `music.${DOMAIN}` → `navidrome:4533`.
