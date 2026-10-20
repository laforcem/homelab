# Runbook: commands and gotchas

Reference for `SKILL.md`. Hosts and addresses: `docs/current-state.md`. Never write the real domain or mrgutsy's address into a tracked file.

## Inventory (Phase 1)

```bash
ssh <host> 'docker inspect <ctr> --format "{{range .Mounts}}{{.Destination}} {{.Source}}{{println}}{{end}}"; docker volume ls'
ssh <host> 'docker exec <ctr> id; docker exec <ctr> ls -ld <mountpoints>'
```

- A volume from the `rclone` driver is a Dropbox mount. Removing the Docker volume does not delete the remote data (rclone docker plugin docs).
- `docker cp` from a container that mounts an rclone-plugin volume fails with "volume is already mounted". Read named volumes from `/var/lib/docker/volumes/<vol>/_data` with `sudo`.

## Manifests (Phase 3)

```bash
DOMAIN=$(kubectl -n actual get ingress actual -o jsonpath='{.spec.rules[0].host}' | cut -d. -f2-)
for f in k3s/apps/<app>/*.yaml; do DOMAIN=$DOMAIN envsubst '$DOMAIN' < $f | kubectl apply -f -; done
```

- Create the namespace first; a `local-path` PVC stays `Pending` until a pod uses it (normal).
- Pin the image tag the source runs. Upgrade separately, after the move.
- Dropbox credentials for VolSync are the `volsync_dropbox_*` Bitwarden secrets. The restic ExternalSecret builds the rclone token from the refresh token with an already-expired `expiry`; copy it from `k3s/apps/audiobookshelf/restic.externalsecret.yaml`. Never print their values; redirect to a file and check structure.
- Static NFS PV: `storageClassName: ""`, `persistentVolumeReclaimPolicy: Retain`, `mountOptions: [nfsvers=4.2]`, and a PVC with `volumeName` set. The export on vm101 is hand-set (`/etc/exports`, `all_squash`, anonuid/anongid of the data owner, chimaera's address only). Prove the restriction: mount from `pve` and expect `access denied`.

## Cutover (Phase 4)

```bash
# bulk data, while the source still serves (run on vm101; backgrounded for big sets)
rclone copy dropbox:<src> /mnt/lab/<app> --transfers=4 --checkers=8 --log-file=<log>
rclone check dropbox:<src> /mnt/lab/<app> --one-way      # expect 0 differences

# baseline: copy the DB out of the volume path, query a COPY read-only
sudo cp /var/lib/docker/volumes/<vol>/_data/<db> <tmp>/ ; chown to yourself

# stop source, delta copy + re-check, export config
docker stop <ctr>
sudo tar -C /var/lib/docker/volumes -czf ~/<app>.tgz <cfgvol>/_data <metavol>/_data

# restore through a temp pod mounting the data PVC (busybox, sleep 3600)
kubectl -n <app> cp <app>.tgz <pod>:/tmp/x.tgz
kubectl -n <app> exec <pod> -- sh -c 'tar -xzf /tmp/x.tgz -C /tmp/x && cp -a /tmp/x/<vol>/_data/. /data/<subpath>/'
```

- Verify before the DNS change: `curl -k --resolve <host>:443:<chimaera ip> https://<host>/<healthpath>`, then compare counts with the baseline.
- After the user flips DNS, delete the stale CertificateRequest so cert-manager retries immediately (HTTP-01 fails while DNS is wrong, then backs off). Compare `openssl s_client` serial with the Secret's `tls.crt`.
- Add the host to the porkbun-ddns `SUBDOMAIN` Bitwarden secret so the record follows the home IP.

## Gate and decommission (Phase 5)

```bash
kubectl -n <app> patch replicationsource <app> --type merge -p '{"spec":{"trigger":{"manual":"first-1"}}}'
kubectl -n <app> wait replicationsource/<app> --for=jsonpath='{.status.lastManualSync}'=first-1 --timeout=300s
kubectl -n <app> patch replicationsource <app> --type merge -p '{"spec":{"trigger":{"manual":null}}}'
kubectl -n <app> get replicationsource <app> -o jsonpath='{.status.latestMoverStatus.result}'
```

- Stuck in a retry loop with `Error` pods: read a failed pod's log, fix the cause, then `kubectl -n <app> delete job volsync-src-<app>` to skip the backoff.
- Remove by name (`docker rm`, `docker volume rm ...`), not `compose down -v`.
- Caddy on mrgutsy: pull the repo, `docker compose config -q`, `docker compose up -d` in `caddy/mrgutsy`, then `docker network rm <app>-caddy`. Confirm the other routes still answer.
- Move a Dropbox library folder server-side (`rclone moveto`) instead of re-uploading.

## Observability (Phase 6)

- Probe: copy `k3s/apps/audiobookshelf/health-probe.cronjob.yaml`. Create its check through the Healthchecks MCP (needs a read-write key): `timeout` = 2x the cron period, `grace` = same, same integration as the other checks. The `/fail` branch is untested by design (it alerts for real).
- VolSync metrics are already scraped; no per-app work.

## Session mechanics

- A long `sleep` is blocked; wait with `timeout N bash -c 'until <check>; do sleep 5; done'`.
- Check a long-running command's output file before launching a second copy of it.
- Redirect anything that could touch a secret to a file and inspect it structurally.
