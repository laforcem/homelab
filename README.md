# Homelab

Welcome to the repo for my homelab. The purpose of this repository is to keep the Docker Compose files and configurations for my standalone self-hosted applications all in one place. Larger standalone projects, like [Sparecraft](https://docs.sparecraft.net/), will be contained in their own repos in an effort to not create too much of a monolith of this one.

## Projects

All applications are proxied by Traefik, either my [LAN instance](/traefik/lan/) or my [public instance](/traefik/cloud/).

### Private services

Some services are used on my LAN at home:

- [Airconnect](/airconnect/)
- [Pi-Hole](/pihole/)
- [Plex](/plex/)

### Public services

Other services are intended to be public and hosted on a generally available server.

- [Audiobookshelf](/audiobookshelf/)
- [Miniflux](/miniflux/)
- [Obsidian Livesync](/obsidian-livesync/)
- [Tandoor](/tandoor/)
