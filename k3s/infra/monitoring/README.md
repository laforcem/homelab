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

```
kubectl apply -f namespace.yaml

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 92.10.1 --kube-context starcliff -n monitoring \
  -f kube-prometheus-stack.values.yaml

kubectl apply -f traefik.podmonitor.yaml -f cert-manager.servicemonitor.yaml
```

Loki and Alloy are added in a later step (see the plan).

The Alertmanager bot token and chat ID come from `alertmanager-telegram.externalsecret.yaml`;
apply it before the Helm upgrade. The blackbox exporter's values contain `$DOMAIN`:

```
kubectl apply -f alertmanager-telegram.externalsecret.yaml -f rules/alerts.prometheusrule.yaml
helm install prometheus-blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
  --version 11.20.2 --kube-context starcliff -n monitoring \
  -f <(DOMAIN=... envsubst '$DOMAIN' < blackbox-exporter.values.yaml)
kubectl apply -f app-probes.probe.yaml -f kubeconfig-cert-watch.cronjob.yaml
```

## Alerting

All alerts go to one Telegram chat through Alertmanager. The rules are in
`rules/alerts.prometheusrule.yaml`; the chart's default alerts are off.

- Add an alert: write a failing case in `rules/alerts.test.yaml`, add the rule,
  and run `bash rules/test.sh` (needs `promtool` and `yq`, both in brew:
  `brew install prometheus yq`). Then `kubectl apply` the rule file.
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
