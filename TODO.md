# Homelab TODO

Ideas and future improvements to revisit.

## Security

- **Secrets management** — plaintext `.env` files work but aren't great. Two options worth evaluating:
  - [SOPS + age](https://github.com/getsops/sops) — encrypt secrets files with an age key, commit encrypted versions to git, decrypt on deploy. Lightweight and git-native.
  - [Bitwarden Secrets Manager](https://bitwarden.com/products/secrets-manager/) — self-hostable (via Vaultwarden?), centralised, with a CLI that can inject secrets at deploy time. Could integrate nicely if already using Bitwarden for passwords.
  - Whichever is chosen, it should be applied consistently across all services in one go.
