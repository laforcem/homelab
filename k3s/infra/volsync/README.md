# VolSync

Flux installs it: `crds/` (Kustomization `volsync-crds`, never pruned) then
`helmrelease.yaml` (chart 0.16.0). The VolumeSnapshot CRDs are required even
for the `Direct` copy method; the chart doesn't ship them.

## Chart gaps patched in the HelmRelease

Both live in `spec.postRenderers`, so they apply on every upgrade.

- **Timezone.** The chart exposes no `env`/`extraVolumes`/`extraVolumeMounts`,
  so cron schedules (`ReplicationSource`/`ReplicationDestination`
  `spec.trigger.schedule`) would run in UTC. A patch sets `TZ=America/Denver`
  and mounts the node's `/usr/share/zoneinfo` (the image has no `tzdata`).
- **Duplicate ServiceMonitor.** When the ServiceMonitor CRD exists the chart
  creates its own `volsync` ServiceMonitor, which scrapes without the bearer
  token the endpoint requires (401, `TargetDown`). A patch deletes it;
  `metrics.servicemonitor.yaml` is the working one.

When rendering the chart by hand to compare against the cluster, pass
`--api-versions monitoring.coreos.com/v1/ServiceMonitor`, or the chart leaves
objects out that Flux's own render includes.
