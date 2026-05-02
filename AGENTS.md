# Agent Guidelines for homelab

## Caddy

After editing any Caddy `compose.yaml` (e.g. adding a network), run `docker compose up -d` in that directory — a running container won't pick up network changes without being recreated.
