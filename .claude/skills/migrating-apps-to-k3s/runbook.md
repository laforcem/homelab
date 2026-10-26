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
- The Deployment file says `replicas: 0`. Re-applying it after `kubectl scale` resets the app to 0. Once the data is restored, set `replicas: 1` in the file, then apply.
- A pod `OOMKilled` (exit 137) during start means the limit is too low; compare with `docker stats --no-stream <ctr>` on the source.
- If the app validates the Host header (Django `ALLOWED_HOSTS`), readiness and health probes send `httpHeaders: [{name: Host, value: <app>.$DOMAIN}]`; the pod IP is rejected with 400.
- Two PVCs, two repos: copy `restic.externalsecret.yaml` once per PVC, rename the secret (`restic-config-media`, `restic-config-dump`), change the `RESTIC_REPOSITORY` suffix, and point each `ReplicationSource` at its own secret.
- Dropbox credentials for VolSync are the `volsync_dropbox_*` Bitwarden secrets. The restic ExternalSecret builds the rclone token from the refresh token with an already-expired `expiry`; copy it from `k3s/apps/audiobookshelf/restic.externalsecret.yaml`. Never print their values; redirect to a file and check structure.
- Bulk-data PV: a `local` PV (`local.path: /mnt/lab/<dir>`, `nodeAffinity` on `kubernetes.io/hostname: chimaera`, `storageClassName: ""`, `persistentVolumeReclaimPolicy: Retain`) and a PVC with `volumeName` set. Copy `k3s/apps/audiobookshelf/library.pv.yaml`. Read-only is set on the PVC and the volumeMount, not the PV. Files are `1000:1000`. A PV's source can't be edited in place: delete the PVC and PV (data stays, `Retain`) and re-apply. To let another host write the directory, export it from chimaera in `ansible/roles/k3s` (per-client, `all_squash`, anonuid/anongid of the data owner, ufw allow-list) and prove the restriction from a host not on the list.

## Postgres apps

Reference: `k3s/apps/miniflux/` (Postgres Deployment, `pg-dump` CronJob, dump PVC, ReplicationSource on the dump PVC).

- Set `PGDATA` to a subdirectory of the mount so `initdb` doesn't trip on the volume root.
- Start the empty Postgres first (`replicas: 1`), keep the app at `replicas: 0` so it can't run migrations on an empty database.
- Source and target share a major version; pin to the exact source version (`SELECT version()`).
- Move the data (the dump holds password hashes: keep it in the job tmp dir and delete it after):
  ```bash
  ssh <host> 'docker stop <app> && docker exec <db> pg_dump -U <user> -Fc <db>' > app.dump
  kubectl -n <app> cp app.dump <pg-pod>:/tmp/app.dump
  kubectl -n <app> exec <pg-pod> -- pg_restore -U <user> -d <db> --no-owner --clean --if-exists /tmp/app.dump
  ```
  A restore with no output and exit 0 is clean. Compare the baseline counts, then scale the app up.
- A source "collation version mismatch" warning goes away with a logical restore.
- Test the backup job once: `kubectl -n <app> create job --from=cronjob/pg-dump pg-dump-manual-1`, wait, delete the job.

## Cutover (Phase 4)

```bash
# bulk data, while the source still serves (run on chimaera; backgrounded for big sets)
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
- DNS: a host that is a CNAME to the home A record needs no DDNS change. Add a host to the porkbun-ddns `SUBDOMAIN` Bitwarden secret only if it has its own A record. Check with `dig +short <host>`.

## Certificate won't issue

Symptom: the Certificate stays `Ready: False` and the Challenge reason is `failed to perform self check GET request ... context deadline exceeded`.

- cert-manager runs on chimaera. chimaera resolves DNS through 1.1.1.1, not AdGuard, so AdGuard rewrites never reach the cluster. The DMZ has no hairpin NAT: a pod or the host calling the home's public address on port 80 times out, while the same URL answers from the LAN.
- Look before asking the user to change DNS. From a throwaway pod run `nslookup <host>` and `wget -T 8 http://<host>/.well-known/acme-challenge/x`. A name that resolves to the WAN address or to the old host fails here.
- Fix in the cluster: add the host to `k3s/infra/coredns-custom/coredns-custom.configmap.yaml` (a `*.server` key, one server block, `hosts { 192.168.40.10 <host> }`), apply with `envsubst '$DOMAIN'`, `kubectl -n kube-system rollout restart deploy/coredns`, and re-run the pod test. A `*.override` key containing `hosts` crash-loops CoreDNS: the main block already uses `hosts`, which is allowed once per block.
- Then `kubectl -n <app> delete challenge --all` and `delete certificaterequest --all` so cert-manager retries now.
- Read readiness by type: `kubectl get certificate -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'`. `conditions[0]` is `Issuing`, which reads `True` while the cert is still pending.
- Every host chimaera serves belongs in `coredns-custom`; add a new app's host there at migration time, or its first renewal fails the same way.

## Gate and decommission (Phase 5)

Dump first, then back up every PVC by hand. A DB app's dump PVC is empty until the dump job has run once:

```bash
kubectl -n <app> create job --from=cronjob/pg-dump pg-dump-manual-1
kubectl -n <app> wait job/pg-dump-manual-1 --for=condition=complete --timeout=120s
kubectl -n <app> delete job pg-dump-manual-1
# then one manual trigger per ReplicationSource, as below
```

```bash
kubectl -n <app> patch replicationsource <app> --type merge -p '{"spec":{"trigger":{"manual":"first-1"}}}'
kubectl -n <app> wait replicationsource/<app> --for=jsonpath='{.status.lastManualSync}'=first-1 --timeout=300s
kubectl -n <app> patch replicationsource <app> --type merge -p '{"spec":{"trigger":{"manual":null}}}'
kubectl -n <app> get replicationsource <app> -o jsonpath='{.status.latestMoverStatus.result}'
```

- Stuck in a retry loop with `Error` pods: read a failed pod's log, fix the cause, then `kubectl -n <app> delete job volsync-src-<app>` to skip the backoff.
- Remove by name (`docker rm`, `docker volume rm ...`), not `compose down -v`.
- Caddy on mrgutsy: pull the repo, `docker compose config -q`, `docker compose up -d` in `compose/caddy/mrgutsy`, then `docker network rm <app>-caddy`. Confirm the other routes still answer.
- Move a Dropbox library folder server-side (`rclone moveto`) instead of re-uploading.

## Observability (Phase 6)

- Probe: copy `k3s/apps/audiobookshelf/health-probe.cronjob.yaml`. Create its check through the Healthchecks MCP (needs a read-write key): `timeout` = 2x the cron period, `grace` = same, same integration as the other checks. The `/fail` branch is untested by design (it alerts for real).
- VolSync metrics are already scraped; no per-app work. Confirm the new app shows up (Prometheus' NodePort is unreachable from WSL and its image has no `wget`; use the API server proxy):
  ```bash
  q(){ kubectl get --raw "/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$1")"; }
  q 'volsync_volume_out_of_sync{obj_namespace="<app>"}'          # one series per ReplicationSource, value 0
  q 'kube_cronjob_status_last_successful_time{namespace="<app>"}' # health-probe, plus pg-dump for Postgres apps
  ```
- Nothing alerts on VolSync or CronJob failure yet (#109); say so to the user rather than implying coverage.
- Healthchecks MCP: `get_check` takes `check` (the UUID). `create_check` takes `tags` and `channels` as arrays. Read the channel id from an existing probe's `get_check`.
- Probe from the template: `sed` the namespace, URL and ping UUID in `k3s/apps/audiobookshelf/health-probe.cronjob.yaml`, apply, run `kubectl create job --from=cronjob/health-probe probe-test-1`, then confirm `n_pings: 1` on the check.

## Git and PR mechanics

- Branch from `main` for the migration; the skill or other work may sit on a branch that isn't merged.
- Another migration PR open or just merged edits the same `compose/caddy/mrgutsy/` and `docs/current-state.md` lines. Before opening the PR (and again if GitHub reports conflicts), `git fetch` and `git merge origin/main`, resolve, and push. Take both apps' rows in the chimaera table and neither in the mrgutsy table.
- A hook checks `gh pr/issue create`. Write the body to a file with the Write tool first (absolute path; `$VARS` aren't expanded), end it with the attribution block, and pass `--body-file`. Run it as its own command, not chained with `git commit`.
- A hook wants the `Co-Authored-By:` trailer inline: `git commit -m "$(cat <<'EOF' ... EOF)"`, not `-F`.
- Stage with `git add <dirs>` for paths that exist; `git add` on a path already removed with `git rm` errors and aborts the chain. Check `git show --stat HEAD` after committing.
- `git commit --amend` may be denied. Make a second commit and squash on merge.
- After the merge, on the source host: `git pull --ff-only` in the repo checkout, `docker compose config -q`, `docker compose up -d` for Caddy, then remove the containers and network by name. Check one other route still answers.

## Session mechanics

- Use `ssh -n` for any `ssh` inside a `while read` loop; without it `ssh` swallows the loop's stdin and only the first item runs.
- Secrets already in the source host's `.env`: copy each into the `homelab` Bitwarden project by pipe, never printing it. Read the value into a shell variable with `ssh -n <host> "grep -m1 '^KEY=' <path>/.env | cut -d= -f2-"`, run `bws secret create <name> "$v" <project-id>` with output redirected to a file, and verify by value length. Take the new ids from the output file and write them into the ExternalSecrets. The external-secrets machine account needs read access on each new secret before the ExternalSecret syncs; ask the user to grant it.
- A long `sleep` is blocked; wait with `timeout N bash -c 'until <check>; do sleep 5; done'`.
- Check a long-running command's output file before launching a second copy of it.
- Redirect anything that could touch a secret to a file and inspect it structurally.
- After a rejected or interrupted command, read the cluster state (`kubectl get`) before saying what was or wasn't applied. The command may have run before the interruption.
