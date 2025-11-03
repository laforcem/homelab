# Homelab

Welcome to the repo for my homelab. The purpose of this repository is to keep the files and configurations for my self-hosted applications all in one place. Larger standalone projects will be contained in their own repos in an effort to not create too much of a monolith of this one.

> [!NOTE]
> Right now, this repo is in a bit of an "intermediate" state as I transition from Docker Compose to [k3s](https://k3s.io/). Some apps may contain Kubernetes manifests and some may not. The end goal is to have everything in here managed by Helm charts.

## Projects

Most applications are proxied by Traefik.

### Private services

Some services are used on my LAN at home:

- [AdGuard Home](/adguard-home/)
- [Airconnect](/airconnect/)
- [Calibre](/calibre/)
- [Discord Rich Presence for Plex](/discord-rich-presence-plex/)
- [icloudpd](/icloudpd/)
- [Immich](/immich/)
- [Plex](/plex/)

### Public services

Other services are intended to be public and hosted on a generally available server.

- [Actual Budget](/actual/)
- [Audiobookshelf](/audiobookshelf/)
- [Miniflux](/miniflux/)
- [Obsidian Livesync](/obsidian-livesync/)
- [Tandoor](/tandoor/)
