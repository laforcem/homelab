# Monitoring (warden side)

The one Grafana, plus warden's own Prometheus and exporters. Deployed by
Doco-CD (`monitoring` entry in `doco-cd/compose.yaml`). The cluster half is in
`k3s/infra/monitoring/`.

Every connection starts on warden: this stack queries the cluster's Prometheus
(`192.168.40.10:30090`) and Loki (`:30100`), and nothing on the DMZ side can
reach warden.

| Container | Role |
|---|---|
| `monitoring-prometheus` | Warden's metrics, 15d retention |
| `monitoring-node-exporter` | Host metrics, plus Tailscale metrics via the textfile collector |
| `monitoring-cadvisor` | Per-container metrics |
| `monitoring-adguard-exporter` | AdGuard Home stats, via its own `adguard-exporter` AGH account |
| `monitoring-grafana` | `grafana.lan.$DOMAIN` |

speedtest-tracker publishes its own metrics at `/prometheus`; Prometheus scrapes
it directly. Its init script (`speedtest/custom-cont-init.d/`) turns the export
on and the old InfluxDB export off.

## Tailscale metrics

`tailscale metrics write` runs every minute from a systemd timer
(`ansible/roles/utility-services`) and writes
`/var/lib/node-exporter/textfile/tailscaled.prom`, which node-exporter mounts.
The timer is Ansible-managed, not Doco-CD-managed.

## Datasources

Provisioned from `grafana/provisioning/datasources/`: `Prometheus (warden)`
(default), `Prometheus (cluster)`, `Loki (cluster)`.

## Dashboards

Files under `grafana/dashboards/` are loaded by Grafana's file provider; the
folder names become Grafana folders. UI edits are not saved (`allowUiUpdates:
false`) — change the JSON in git.

- `kubernetes/`, `node/` — extracted from kube-prometheus-stack 92.10.1
  (`helm template` with `grafana.enabled=false`,
  `grafana.forceDeployDashboards=true`; the ConfigMap JSON written out as
  files). Re-extract after each chart upgrade. The `kubernetes/` ones only offer
  `Prometheus (cluster)` in their datasource dropdown; the `node/` ones offer
  both (warden's job is named `node-exporter` so the same dashboards work).
- `warden/adguard.json` — from `henrywhitaker3/adguard-exporter` @ `9d49a56`.
- `warden/speedtest.json` — from `CrazyWolf13/Speedtest-Tracker-Prometheus`
  @ `5f36e5f`. Both had `${DS_PROMETHEUS}` rewritten to `prometheus-warden`.

## Leftovers

Compose does not delete removed volumes. After this deploys, the old
`speedtest_speedtest-influxdb` and `speedtest_speedtest-grafana` volumes remain
on warden until removed by hand.
