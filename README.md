# Homelab

Welcome to the repo for my homelab. The purpose of this repository is to keep the files and configurations for my self-hosted applications all in one place. Larger standalone projects will be contained in their own repos in an effort to not create too much of a monolith of this one.

> [!NOTE]
> Right now, this repo is in a bit of an "intermediate" state as I transition from Docker Compose to [k3s](https://k3s.io/). Some apps may contain Kubernetes manifests and some may not. The end goal is to have everything in here managed by Helm charts.

## Projects

Below is the software currently in use in this repo. The date which I first deployed the software is noted below. Whatever has been around a long time has proven itself to be reliable, since items in this list are removed when retired.

Most applications are proxied by [Traefik](/traefik/).

### Private services

Some services are used on my LAN at home:

- [AdGuard Home](/adguard-home/) (June 2025)
- [Airconnect](/airconnect/) (May 2025)
- [icloudpd](/icloudpd/) (October 2025)
- [Immich](/immich/) (June 2025)
- [Plex](/plex/) (March 2025)

### Public services

Other services are intended to be public and hosted on a generally available server.

- [Actual Budget](/actual/) (October 2025)
- [Audiobookshelf](/audiobookshelf/) (December 2024)
- [Miniflux](/miniflux/) (September 2024)
- [Tandoor](/tandoor/) (August 2024)
