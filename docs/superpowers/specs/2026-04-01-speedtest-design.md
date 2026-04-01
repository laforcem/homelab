# Internet Speed Monitor — Design Spec

**Date:** 2026-04-01  
**Status:** Approved

## Overview

A self-hosted internet speed monitoring stack running on vm100 (LAN). Runs Ookla speedtests on a 15-minute schedule, stores results as time-series data, and exposes a Grafana dashboard accessible over the LAN. Sends a Telegram alert if no test data arrives within 30 minutes.

Primary use case: accumulating evidence of speeds below the contracted ISP rate.

---

## Architecture

Three containers in a new `speedtest/` directory, following the existing per-service compose pattern:

| Service | Image | Role |
|---|---|---|
| speedtest-tracker | `alexjustesen/speedtest-tracker` | Runs tests, pushes to InfluxDB |
| InfluxDB 2 | `influxdb:2` | Time-series storage |
| Grafana | `grafana/grafana` | Dashboard and alerting |

### Networks

- `speedtest-internal` — shared by all three containers for service-to-service communication
- `speedtest-caddy` — shared between Grafana and the vm100 Caddy container, following the `miniflux-caddy` pattern
- speedtest-tracker also has access to the default network for outbound internet (to run tests)

### Caddy (vm100)

Two new entries in `caddy/vm100/Caddyfile`:

- `grafana.lan.{$DOMAIN}` → `grafana:3000`
- `speedtest.lan.{$DOMAIN}` → `speedtest-tracker:80` (speedtest-tracker's own UI)

---

## Data Flow

1. speedtest-tracker runs an Ookla test every 15 minutes (`*/15 * * * *`)
2. Results (download Mbps, upload Mbps, ping ms, jitter ms) are pushed to InfluxDB over `speedtest-internal`
3. InfluxDB stores results in a bucket named `speedtest` with a configurable retention period (default 90 days / `2160h`)
4. Grafana queries InfluxDB using Flux; a community dashboard template is imported on first setup
5. Caddy terminates TLS and proxies Grafana to `grafana.lan.{$DOMAIN}`

All service-to-service traffic stays inside Docker networks. Only the speedtest itself makes external requests.

---

## Configuration & Secrets

All secrets and tuneable values live in `speedtest/.env`. No values are hardcoded in `compose.yaml`.

| Variable | Purpose |
|---|---|
| `INFLUXDB_USERNAME` | InfluxDB admin username |
| `INFLUXDB_PASSWORD` | InfluxDB admin password |
| `INFLUXDB_TOKEN` | InfluxDB API token (used by speedtest-tracker and Grafana) |
| `INFLUXDB_ORG` | InfluxDB organisation name |
| `INFLUXDB_RETENTION` | Bucket retention duration (default: `2160h` = 90 days) |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token from BotFather |
| `TELEGRAM_CHAT_ID` | Telegram chat ID to receive alerts |

To change retention in future: update `INFLUXDB_RETENTION` in `.env` and recreate the InfluxDB container. The bucket retention is applied at init via `DOCKER_INFLUXDB_INIT_RETENTION`.

---

## Alerting

Grafana is provisioned with a Telegram contact point (bot token + chat ID from `.env`) and a single alert rule:

- **Condition:** no data points in the `speedtest` InfluxDB bucket in the last 30 minutes
- **Channel:** Telegram

This fires if the speedtest-tracker container stops, if tests fail consistently, or if InfluxDB becomes unreachable. Grafana provisioning files (contact point YAML, alert rule YAML) are stored in the repo under `speedtest/grafana/provisioning/` so the setup is reproducible without manual UI configuration.

---

## Persistence

| Volume | Contents |
|---|---|
| `speedtest-influxdb` | InfluxDB data |
| `speedtest-grafana` | Grafana state (dashboards, plugins, alert history) |

---

## Out of Scope

- Secrets management migration (SOPS / Bitwarden) — tracked in `TODO.md`
- Notifications via channels other than Telegram
- Public-facing (vm101) access to the dashboard
