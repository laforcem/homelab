# VolSync

Install (VolumeSnapshot CRDs required even for `Direct` copyMethod — undocumented in the chart, see `crds/`):

```
kubectl apply -f crds/
helm repo add backube https://backube.github.io/helm-charts
helm install volsync backube/volsync \
  --kube-context starcliff -n volsync-system --create-namespace \
  --version 0.16.0 \
  --post-renderer ./postrender/render.sh
```

## Timezone (chart gap)

The chart exposes no `env`/`extraVolumes`/`extraVolumeMounts` field, so there's
no `values.yaml` way to set a timezone — cron schedules (`ReplicationSource`/
`ReplicationDestination` `spec.trigger.schedule`) are evaluated in whatever
timezone the controller pod runs in, UTC by default. `postrender/` patches
the rendered Deployment via Kustomize (`helm upgrade`/`install
--post-renderer ./postrender/render.sh`) to set `TZ=America/Denver` and mount
the node's `/usr/share/zoneinfo` (the image has no `tzdata` of its own).

Always use `--post-renderer` on every install/upgrade — a plain `helm
upgrade` without it drops this patch silently, since Helm has no record of
it.
