# Monitoring (cluster side)

Metrics and logs for chimaera. Grafana does **not** run here: the one Grafana
lives on warden (trusted VLAN) and queries the stores below. The DMZ never
initiates a connection to the trusted network, so nothing is pushed out of the
cluster. See `docs/superpowers/plans/2026-10-19-cluster-observability.md`.

Three Helm releases in the `monitoring` namespace:

- **kube-prometheus-stack** — Prometheus, node-exporter, kube-state-metrics,
  the `ServiceMonitor`/`PodMonitor` CRDs. Grafana and Alertmanager are off.
  Alerting is tracked in #109.
- **Loki** — single binary, filesystem storage, cluster logs only.
- **Alloy** — DaemonSet that ships every container's stdout to Loki.

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

## Adding an app

1. Metrics: ship a `ServiceMonitor` or `PodMonitor` next to the app's
   manifests. No label is needed.
2. Logs: nothing. Print to stdout.
3. Dashboards: a JSON file under `monitoring/grafana/dashboards/` in this
   repo, loaded by warden's Grafana.

## Dashboards

The chart's Kubernetes dashboards are extracted with `helm template`
(`grafana.enabled=false`, `grafana.forceDeployDashboards=true`). Re-extract
them after each chart upgrade.
