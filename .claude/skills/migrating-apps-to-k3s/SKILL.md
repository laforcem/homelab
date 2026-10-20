---
name: migrating-apps-to-k3s
description: Use when moving a docker-compose service from warden, vm101 or mrgutsy onto the chimaera k3s cluster, or adding a new workload under k3s/apps/.
---

# Migrating an app to chimaera

One app is one directory, `k3s/apps/<app>/`. Copy the shape of `k3s/apps/audiobookshelf/` (data + bulk library + backup + probe) or `k3s/apps/actual/` (data + backup only). The source stays intact until Phase 5.

Commands and gotchas: `runbook.md` in this directory. Current topology: `docs/current-state.md`.

## Phases

1. **Inventory.** From the compose file and the live host, list each volume: path or driver, size, owner uid, what it holds. Note the DB engine, the Caddy route, env and secrets, and any rclone-plugin volumes.
2. **Place each volume.**
   - DB, config, small state → a `local-path` PVC. SQLite never goes on a network filesystem.
   - Bulk media → the `lab` drive on vm101, exported over NFS to chimaera only (interim until the drive moves). Back it up through `media-backup/`, not VolSync.
3. **Write the manifests.** Namespace, PVCs, Deployment (`strategy: Recreate`, `replicas: 0` until data is restored, `enableServiceLinks: false`, requests and limits, image tag pinned to what the source runs), Service, Ingress (cert-manager annotation, host `<app>.$DOMAIN`), restic ExternalSecret and ReplicationSource copied from an existing app. Apply with `envsubst '$DOMAIN'`.
4. **Cut over.** Pre-seed bulk data while the source still serves. Record a baseline from the source's DB (item counts, one in-progress record). Stop the source. Delta-copy and verify, export config, restore it into the PVC through a temporary pod, set `replicas: 1`. Verify with `curl --resolve` and compare against the baseline. Then hand the DNS change to the user.
5. **Gate, then decommission.**
   - **Gate:** a VolSync backup finished (`status.latestMoverStatus.result` is `Successful`), the app answers on its public name with a Let's Encrypt cert whose serial matches the cluster Secret, and the user confirmed from a phone on cellular.
   - **After the gate:** remove the container and volumes by name, drop the Caddy route and network, recreate Caddy, delete the compose directory, update `docs/current-state.md`. Keep the config export until the first scheduled backup passes.
6. **Make it observable.** Add a probe CronJob and a Healthchecks check, and a `media-backup` entry for any bulk library.
7. **Hand off.** File a GitHub issue with the verification that can only happen later (the first scheduled backup run) and the exact commands to check it. A new session must not need this one's history.

## Hand the user these, then wait

The DNS change, any `sudo` on vm101 or mrgutsy (it asks for a password), creating Bitwarden secrets, `rclone authorize`, and deleting a source's data. Give the exact command; check the result with read-only commands.

## Common mistakes

| Mistake | Fix |
|---|---|
| Leaving `spec.trigger.manual` on a `ReplicationSource` | It pauses the schedule. Trigger with a unique value, wait for `status.lastManualSync` to match, then patch `manual` to `null`. |
| rclone token without the app's client id/secret | Refreshes go through rclone's default app and fail after 4h. Copy the ExternalSecret from an existing app. |
| New Bitwarden secret, ExternalSecret stuck `SecretSyncedError` | Grant the external-secrets machine account read on that secret. |
| Declaring a long check done | Only the next scheduled run proves a token fix. Write it into the handoff issue. |
