# Homelab

Welcome to the repo for my homelab. The purpose of this repository is to keep the Docker Compose files and configurations for my standalone self-hosted applications all in one place. Larger standalone projects, like [Sparecraft](https://docs.sparecraft.net/), will be contained in their own repos in an effort to not create too much of a monolith of this one.

## Projects

### Private services

Some services are not public-facing and can be run on any sort of private network that you please:

- [pihole](/pihole/): For use on a home network to block ads and does not need port forwarding.

- [redbot](/redbot/): Uses a Discord bot token, so does not need port forwarding.

Private services will not include Traefik-related labels in their Compose files.

### Public services

Other services are intended to be public and hosted on a generally available server. All these services are oriented around [Traefik](/traefik/), which functions as a reverse proxy that routes HTTP requests to their corresponding service.

- [Traefik](/traefik/) (includes test app `whoami`)
- [FreshRSS](/freshrss/)
- [`Obsidian Livesync`](/obsidian-livesync/)

Before running any public applications, set up Traefik first.

## TODO

- Refactor Traefik's Compose file to use config files instead
- Find a better way to develop locally without maintaining two Compose files (Compose profiles?)
- Refactor FreshRSS's Compose file to make backups of mySQL database
