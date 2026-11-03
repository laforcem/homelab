# Monitoring (cluster side)

Metrics and logs for chimaera. Grafana does **not** run here: the one Grafana
lives on warden (trusted VLAN) and queries the stores below. The DMZ never
initiates a connection to the trusted network, so nothing is pushed out of the
cluster. See `docs/superpowers/plans/2026-10-19-cluster-observability.md`.

Four Helm releases in the `monitoring` namespace:

- **kube-prometheus-stack** — Prometheus, Alertmanager, node-exporter,
  kube-state-metrics, the `ServiceMonitor`/`PodMonitor` CRDs. Grafana is off.
- **Loki** — single binary, filesystem storage, cluster logs only.
- **Alloy** — DaemonSet that ships every container's stdout to Loki.
- **prometheus-blackbox-exporter** — probes the apps (`app-probes.probe.yaml`).

Prometheus (NodePort 30090) and Loki (NodePort 30100) are reachable from
warden only; the ufw rule is in `ansible/roles/k3s`.

## Install

Flux manages all of it (see `k3s/clusters/starcliff/README.md`). Two
Kustomizations: `monitoring` (`releases/`: namespace, the four HelmReleases and
their values files) and `monitoring-config` (this directory: rules, probes,
monitors, NodePorts, NetworkPolicy, ExternalSecret). The second waits for the
first because the CRDs it needs come from kube-prometheus-stack. Change a chart
version or a values file in a PR; never `helm upgrade`.

## Alerting

All alerts go to one Telegram chat through Alertmanager. The rules are in
`rules/alerts.prometheusrule.yaml`; the chart's default alerts are off.

- Add an alert: write a failing case in `rules/alerts.test.yaml`, add the rule,
  and run `bash rules/test.sh` (needs `promtool` and `yq`, both in brew:
  `brew install prometheus yq`). Then merge it; Flux applies the rule file.
- Test delivery: port-forward the Alertmanager Service on 9093 and POST a JSON
  alert to `/api/v2/alerts`.
- The Watchdog alert pings a Healthchecks check; see `docs/current-state.md`.

## Adding an app

1. Metrics: ship a `ServiceMonitor` or `PodMonitor` next to the app's
   manifests. No label is needed.
2. Logs: nothing. Print to stdout.
3. Dashboards: a JSON file under `compose/monitoring/grafana/dashboards/` in this
   repo, loaded by warden's Grafana.

## Dashboards

The chart's Kubernetes dashboards are extracted with `helm template`
(`grafana.enabled=false`, `grafana.forceDeployDashboards=true`). Re-extract
them after each chart upgrade.
