---
name: migrating-apps-to-k3s
description: Use when moving a docker-compose service from warden or mrgutsy onto the chimaera k3s cluster, or adding a new workload under k3s/apps/.
---

# Migrating an app to chimaera

One app is one directory, `k3s/apps/<app>/`. Copy the shape of `k3s/apps/audiobookshelf/` (data + bulk library + backup + probe) or `k3s/apps/actual/` (data + backup only). The source stays intact until Phase 5.

Commands and gotchas: `runbook.md` in this directory. Current topology: `docs/current-state.md`.

## Phases

0. **Start a task list** (TaskCreate), one task per phase below plus each "hand the user" step, so the user can follow along. Mark each task `in_progress` when its phase starts and `completed` when it ends.
1. **Inventory.** From the compose file and the live host, list each volume: path or driver, size, owner uid, what it holds. Note the DB engine, the Caddy route, env and secrets, and any rclone-plugin volumes. Then look things up before building anything by hand. Make this its own task and report the answers to the user before Phase 2:
   - From the app's docs or DeepWiki: is there an official Helm chart or manifests (and is any community chart one of those)? Does the app have its own backup/export?
   - `grep -ri <app> docs/` for plans that promise app-specific follow-ups (metrics, alerts).
   - `gh pr list` for open migration PRs: they edit the same Caddy and docs lines.
   - If the app needs a new secret, ask the user for it now (alphanumeric, 32 chars, so it survives a connection URL), so every manifest can apply in one pass.
2. **Place each volume.**
   - DB, config, small state → a `local-path` PVC. SQLite never goes on a network filesystem.
   - Postgres/MySQL → never back up or migrate by copying the live data directory. Migrate with a logical dump and restore. Back up with a nightly dump CronJob onto its own small PVC, and point the `ReplicationSource` at that PVC.
   - An app with a DB dump PVC and a media or config PVC gets one `ReplicationSource` and one restic ExternalSecret per PVC, each with its own `RESTIC_REPOSITORY` path (`.../backups/<app>-media`, `.../backups/<app>-dump`).
   - Bulk media → the `lab` drive, mounted at `/mnt/lab` on chimaera: a `local` PV (`nodeAffinity` to chimaera, `Retain`) on a subdirectory. Back it up through `media-backup/`, not VolSync.
3. **Write the manifests.** Namespace, PVCs, Deployment (`strategy: Recreate`, `replicas: 0` until data is restored, `enableServiceLinks: false`, requests and limits, image tag pinned to what the source runs; size memory from `docker stats --no-stream` on the source *before* stopping it, with extra headroom for apps that build assets at start), Service, Ingress (cert-manager annotation, host `<app>.$DOMAIN`), restic ExternalSecret and ReplicationSource copied from an existing app. Apply with `envsubst '$DOMAIN'`.
4. **Cut over.** Pre-seed bulk data while the source still serves. Record a baseline from the source's DB (item counts, one in-progress record). Stop the source app (leave its database running if you will dump it). Delta-copy and verify, export config, restore it into the PVC through a temporary pod, set `replicas: 1`. Verify with `curl --resolve` and compare against the baseline. Then hand the DNS change to the user.
5. **Gate, then decommission.**
   - **Gate:** every PVC has a manual VolSync backup that finished (`status.latestMoverStatus.result` is `Successful`), taken after the DB dump job ran once so the dump PVC holds a dump; the app answers on its public name with a Let's Encrypt cert whose serial matches the cluster Secret; and the user confirmed from a phone on cellular.
   - **After the gate:** the repo edits (Caddy route and network, compose directory, `docs/current-state.md`) go in a PR first (`git fetch` and merge `main` into the branch before opening it); the source host pulls from `main`, so merge before touching it. Then on the source host: pull, recreate Caddy, remove **every** container of the stack (app and database) and the network, by name. The manual backups at the gate are the safety net: the user may delete the source's data volumes once they pass, without waiting for a scheduled run.
6. **Make it observable.** Add a probe CronJob and a Healthchecks check, and a `media-backup` entry for any bulk library. Do it before the PR so it ships together. Then confirm in Prometheus that the VolSync sources and the probe CronJob report (commands in `runbook.md`), and tell the user what is and isn't alerted on.
7. **Hand off.** File a GitHub issue with the verification that can only happen later (the first scheduled backup run, as a follow-up check rather than a gate) and the exact commands to check it, including deleting the old volumes. A new session must not need this one's history.

## Hand the user these, then wait

The DNS change, any `sudo` on mrgutsy (it asks for a password), creating Bitwarden secrets, `rclone authorize`, and deleting a source's data. Give the exact command; check the result with read-only commands.

## Common mistakes

| Mistake | Fix |
|---|---|
| Leaving `spec.trigger.manual` on a `ReplicationSource` | It pauses the schedule. Trigger with a unique value, wait for `status.lastManualSync` to match, then patch `manual` to `null`. |
| rclone token without the app's client id/secret | Refreshes go through rclone's default app and fail after 4h. Copy the ExternalSecret from an existing app. |
| New Bitwarden secret, ExternalSecret stuck `SecretSyncedError` | Grant the external-secrets machine account read on that secret. |
| Copying a live Postgres data directory (migration or backup) | Not consistent. `pg_dump -Fc` and `pg_restore --no-owner --clean --if-exists`; compare counts with the baseline. |
| Stopping only the app container on the source | Its database keeps running. Stop and remove both at decommission. |
| Remote `docker stop`/`rm` denied in the session | Hand the user the exact command to run with `!`. Do not retry variations. |
| Triggering a PVC's first backup before its DB dump job has run | The dump PVC is empty and the backup still says `Successful`. Run `pg-dump` once, confirm the file exists, then back up. |
| Cert stays `Ready: False`, challenge says the self-check timed out | cert-manager runs on chimaera, which resolves via 1.1.1.1 and can't reach its own public address. Make the name resolve to chimaera inside the cluster (`runbook.md`, "Certificate won't issue"). |
| Declaring a long check done | Only the next scheduled run proves a token fix. Write it into the handoff issue. |
