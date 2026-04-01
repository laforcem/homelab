# Internet Speed Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy speedtest-tracker + InfluxDB + Grafana on vm100 with 15-minute scheduled tests, a Grafana dashboard, and a Telegram alert if no data arrives within 30 minutes.

**Architecture:** speedtest-tracker runs Ookla tests on a cron schedule and pushes results to InfluxDB. Grafana reads from InfluxDB via Flux and is exposed over the LAN through the shared `caddy-internal` Docker network. Grafana's datasource, alert contact point, and alert rule are all provisioned from files in the repo so the setup is fully reproducible.

**Tech Stack:** Docker Compose, lscr.io/linuxserver/speedtest-tracker, InfluxDB 2, Grafana OSS, Caddy (existing vm100 instance)

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `speedtest/compose.yaml` | All three services, volumes, networks |
| Create | `speedtest/.env.example` | Template with all required variables |
| Create | `speedtest/grafana/provisioning/datasources/influxdb.yaml` | Wires Grafana to InfluxDB |
| Create | `speedtest/grafana/provisioning/alerting/contact-points.yaml` | Telegram contact point |
| Create | `speedtest/grafana/provisioning/alerting/rules.yaml` | No-data alert rule |
| Modify | `caddy/vm100/Caddyfile` | Add grafana + speedtest routes |

---

## Task 1: Core compose and environment

**Files:**
- Create: `speedtest/compose.yaml`
- Create: `speedtest/.env.example`

- [ ] **Step 1: Generate an APP_KEY value for speedtest-tracker**

Run locally (not on server — this is just to fill in .env):
```bash
echo "base64:$(openssl rand -base64 32)"
```
Copy the output — you'll need it in Step 3.

- [ ] **Step 2: Create `speedtest/compose.yaml`**

```yaml
name: speedtest

volumes:
  speedtest-influxdb:
  speedtest-tracker:
  speedtest-grafana:

networks:
  speedtest-internal:
  caddy-internal:
    name: caddy-internal
    external: true

services:
  speedtest-tracker:
    image: lscr.io/linuxserver/speedtest-tracker:latest
    container_name: speedtest-tracker
    restart: unless-stopped
    networks:
      - speedtest-internal
      - caddy-internal
    environment:
      - APP_KEY=${APP_KEY}
      - DB_CONNECTION=sqlite
      - INFLUXDB_URL=http://speedtest-influxdb:8086
      - INFLUXDB_TOKEN=${INFLUXDB_TOKEN}
      - INFLUXDB_BUCKET=speedtest
      - INFLUXDB_ORG=${INFLUXDB_ORG}
      - SPEEDTEST_SCHEDULE=*/15 * * * *
    depends_on:
      influxdb:
        condition: service_healthy
    volumes:
      - speedtest-tracker:/config

  influxdb:
    image: influxdb:2
    container_name: speedtest-influxdb
    restart: unless-stopped
    networks:
      - speedtest-internal
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=${INFLUXDB_USERNAME}
      - DOCKER_INFLUXDB_INIT_PASSWORD=${INFLUXDB_PASSWORD}
      - DOCKER_INFLUXDB_INIT_ORG=${INFLUXDB_ORG}
      - DOCKER_INFLUXDB_INIT_BUCKET=speedtest
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=${INFLUXDB_TOKEN}
      - DOCKER_INFLUXDB_INIT_RETENTION=${INFLUXDB_RETENTION}
    volumes:
      - speedtest-influxdb:/var/lib/influxdb2
    healthcheck:
      test: ["CMD", "influx", "ping"]
      interval: 10s
      start_period: 30s

  grafana:
    image: grafana/grafana:latest
    container_name: speedtest-grafana
    restart: unless-stopped
    networks:
      - speedtest-internal
      - caddy-internal
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_PATHS_PROVISIONING=/etc/grafana/provisioning
      - INFLUXDB_TOKEN=${INFLUXDB_TOKEN}
      - INFLUXDB_ORG=${INFLUXDB_ORG}
      - TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
      - TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
    volumes:
      - speedtest-grafana:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    depends_on:
      influxdb:
        condition: service_healthy
```

- [ ] **Step 3: Create `speedtest/.env.example`**

```dotenv
# speedtest-tracker — Laravel app key (generate with: echo "base64:$(openssl rand -base64 32)")
APP_KEY=base64:CHANGE_ME

# InfluxDB credentials (choose any values — used at first-time bucket init)
INFLUXDB_USERNAME=admin
INFLUXDB_PASSWORD=CHANGE_ME
INFLUXDB_TOKEN=CHANGE_ME
INFLUXDB_ORG=homelab

# Retention duration (e.g. 2160h = 90 days, 4380h = 6 months)
# Note: to change after first boot, use:
#   docker exec speedtest-influxdb influx bucket update --name speedtest --retention <new_value>
INFLUXDB_RETENTION=2160h

# Grafana
GRAFANA_ADMIN_PASSWORD=CHANGE_ME

# Telegram alerting — get BOT_TOKEN from @BotFather, CHAT_ID from @userinfobot
TELEGRAM_BOT_TOKEN=CHANGE_ME
TELEGRAM_CHAT_ID=CHANGE_ME
```

- [ ] **Step 4: Copy .env.example to .env and fill in real values**

```bash
cp speedtest/.env.example speedtest/.env
# Edit speedtest/.env — replace all CHANGE_ME values
```

- [ ] **Step 5: Validate compose syntax**

Run from the repo root:
```bash
docker compose -f speedtest/compose.yaml --env-file speedtest/.env config
```
Expected: YAML output with all `${VAR}` placeholders resolved. No errors.

- [ ] **Step 6: Commit**

```bash
git add speedtest/compose.yaml speedtest/.env.example
git commit -m "feat(speedtest): add compose and env template"
```

---

## Task 2: Grafana datasource provisioning

**Files:**
- Create: `speedtest/grafana/provisioning/datasources/influxdb.yaml`

- [ ] **Step 1: Create provisioning directory structure**

```bash
mkdir -p speedtest/grafana/provisioning/datasources
mkdir -p speedtest/grafana/provisioning/alerting
```

- [ ] **Step 2: Create `speedtest/grafana/provisioning/datasources/influxdb.yaml`**

```yaml
apiVersion: 1
datasources:
  - name: InfluxDB
    uid: speedtest-influxdb
    type: influxdb
    access: proxy
    url: http://speedtest-influxdb:8086
    isDefault: true
    jsonData:
      version: Flux
      organization: ${INFLUXDB_ORG}
      defaultBucket: speedtest
      tlsSkipVerify: true
    secureJsonData:
      token: ${INFLUXDB_TOKEN}
```

Note: `${INFLUXDB_ORG}` and `${INFLUXDB_TOKEN}` are substituted by Grafana at startup from the environment variables passed in `compose.yaml`.

- [ ] **Step 3: Bring up InfluxDB and Grafana to verify**

```bash
cd speedtest
docker compose up -d influxdb grafana
docker compose logs -f grafana
```
Wait for a log line like: `logger=provisioning.datasources msg="datasources provisioned"`. Then Ctrl-C.

- [ ] **Step 4: Verify datasource in Grafana UI**

Open `https://grafana.lan.<your-domain>` (Caddy not updated yet) OR test directly:
```bash
curl -s http://localhost:3000/api/datasources \
  -u admin:${GRAFANA_ADMIN_PASSWORD} | python3 -m json.tool
```
Expected: JSON array containing an entry with `"name": "InfluxDB"` and `"uid": "speedtest-influxdb"`.

If Grafana isn't on port 3000 yet (no port mapping in compose), check via Docker exec:
```bash
docker exec speedtest-grafana wget -qO- http://localhost:3000/api/health
```
Expected: `{"commit":"...","database":"ok","health":"ok",...}`

- [ ] **Step 5: Commit**

```bash
git add speedtest/grafana/provisioning/datasources/influxdb.yaml
git commit -m "feat(speedtest): provision InfluxDB datasource in Grafana"
```

---

## Task 3: Grafana alerting provisioning

**Files:**
- Create: `speedtest/grafana/provisioning/alerting/contact-points.yaml`
- Create: `speedtest/grafana/provisioning/alerting/rules.yaml`

**Prerequisites:** You need a Telegram bot token and chat ID before this task.
- Bot token: message @BotFather on Telegram → `/newbot` → copy the token
- Chat ID: message @userinfobot on Telegram → copy the `id` value → put it in `.env`

- [ ] **Step 1: Create `speedtest/grafana/provisioning/alerting/contact-points.yaml`**

```yaml
apiVersion: 1
contactPoints:
  - orgId: 1
    name: Telegram
    receivers:
      - uid: telegram-speedtest
        type: telegram
        settings:
          bottoken: ${TELEGRAM_BOT_TOKEN}
          chatid: ${TELEGRAM_CHAT_ID}
          message: |
            ⚠️ No speedtest data received in the last 30 minutes.
            Check the speedtest-tracker container on vm100.
        disableResolveMessage: false
```

- [ ] **Step 2: Create `speedtest/grafana/provisioning/alerting/rules.yaml`**

```yaml
apiVersion: 1
groups:
  - orgId: 1
    name: Speedtest
    folder: Speedtest
    interval: 10m
    rules:
      - uid: speedtest-no-data
        title: No speedtest data received
        condition: C
        data:
          - refId: A
            relativeTimeRange:
              from: 1800
              to: 0
            datasourceUid: speedtest-influxdb
            model:
              query: |
                from(bucket: "speedtest")
                  |> range(start: -30m)
                  |> filter(fn: (r) => r._measurement == "speedtest" and r._field == "download")
                  |> count()
              refId: A
              queryType: ''
              hide: false
          - refId: B
            relativeTimeRange:
              from: 1800
              to: 0
            datasourceUid: __expr__
            model:
              type: reduce
              expression: A
              reducer: last
              settings:
                mode: replaceWithValue
                replaceWithValue: 0
              refId: B
              hide: false
          - refId: C
            relativeTimeRange:
              from: 1800
              to: 0
            datasourceUid: __expr__
            model:
              type: threshold
              expression: B
              conditions:
                - evaluator:
                    params:
                      - 1
                    type: lt
              refId: C
              hide: false
        noDataState: Alerting
        execErrState: Alerting
        for: 5m
        annotations:
          summary: No speedtest data received in the last 30 minutes
          description: speedtest-tracker may have stopped or tests are consistently failing
        isPaused: false
```

**Alert logic:** A counts download records in the last 30 min. B reduces to the last count (defaulting to 0 if A has no data). C fires if B < 1. `noDataState: Alerting` fires immediately if InfluxDB returns no results at all.

- [ ] **Step 3: Set default notification policy to route to Telegram**

Create `speedtest/grafana/provisioning/alerting/notification-policies.yaml`:

```yaml
apiVersion: 1
policies:
  - orgId: 1
    receiver: Telegram
    group_by:
      - grafana_folder
      - alertname
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 12h
```

- [ ] **Step 4: Restart Grafana and verify**

```bash
cd speedtest
docker compose restart grafana
docker compose logs -f grafana
```
Look for lines mentioning `alerting` provisioning loading without errors. Ctrl-C when done.

- [ ] **Step 5: Verify in Grafana UI**

Open Grafana → Alerting → Contact points: `Telegram` should appear.
Open Grafana → Alerting → Alert rules: `No speedtest data received` should appear in folder `Speedtest`.

If you can't access Grafana in the browser yet (Caddy not configured), add a temporary port mapping to compose.yaml for testing:
```yaml
    ports:
      - "3000:3000"
```
Remove it after Task 4 is done.

- [ ] **Step 6: Commit**

```bash
git add speedtest/grafana/provisioning/alerting/
git commit -m "feat(speedtest): provision Telegram alerting in Grafana"
```

---

## Task 4: Update Caddy vm100

**Files:**
- Modify: `caddy/vm100/Caddyfile`

- [ ] **Step 1: Add speedtest and Grafana routes to `caddy/vm100/Caddyfile`**

Insert the two new `handle` blocks before the catch-all `handle { abort }` block:

```caddyfile
*.lan.{$DOMAIN} {
    tls {
        dns porkbun {
            api_key {$API_KEY}
            api_secret_key {$SECRET_KEY}
        }
    }
    @adguard host adguard.lan.{$DOMAIN}
    handle @adguard {
        reverse_proxy adguard-home:80
    }
    @portainer host portainer.lan.{$DOMAIN}
    handle @portainer {
        reverse_proxy portainer:9443 {
            transport http {
                tls
                tls_insecure_skip_verify
            }
        }
    }
    @grafana host grafana.lan.{$DOMAIN}
    handle @grafana {
        reverse_proxy speedtest-grafana:3000
    }
    @speedtest host speedtest.lan.{$DOMAIN}
    handle @speedtest {
        reverse_proxy speedtest-tracker:80
    }
    
    handle {
        abort
    }
}
```

- [ ] **Step 2: Reload Caddy**

```bash
cd caddy/vm100
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```
Expected output: no errors. Caddy reloads config without restarting.

- [ ] **Step 3: Verify both URLs resolve**

From a machine on the LAN:
```bash
curl -sk https://grafana.lan.<your-domain>/api/health
```
Expected: `{"commit":"...","database":"ok","health":"ok",...}`

```bash
curl -skI https://speedtest.lan.<your-domain>
```
Expected: HTTP 200 or 302 response.

- [ ] **Step 4: Remove any temporary port mapping from compose.yaml**

If you added `ports: - "3000:3000"` to Grafana in Task 3 Step 5, remove it now and restart:
```bash
cd speedtest
docker compose up -d grafana
```

- [ ] **Step 5: Commit**

```bash
git add caddy/vm100/Caddyfile
git commit -m "feat(speedtest): expose Grafana and speedtest-tracker via Caddy on vm100"
```

---

## Task 5: Bring up the full stack and verify end-to-end

- [ ] **Step 1: Start all three services**

```bash
cd speedtest
docker compose up -d
docker compose ps
```
Expected: all three containers showing `Up` or `healthy`.

- [ ] **Step 2: Verify InfluxDB bucket exists with correct retention**

```bash
docker exec speedtest-influxdb influx bucket list
```
Expected: a row showing `speedtest` bucket with retention matching your `INFLUXDB_RETENTION` value (e.g. `2160h0m0s`).

- [ ] **Step 3: Verify speedtest-tracker is running and InfluxDB connection is OK**

```bash
docker compose logs speedtest-tracker | grep -i influx
```
Expected: lines indicating a successful InfluxDB connection (no auth errors).

- [ ] **Step 4: Trigger a manual test and verify data in InfluxDB**

Open `https://speedtest.lan.<your-domain>` → log in (default: admin / password) → trigger a manual test from the UI.

Then verify the data arrived in InfluxDB:
```bash
docker exec speedtest-influxdb influx query \
  'from(bucket: "speedtest") |> range(start: -1h) |> filter(fn: (r) => r._field == "download") |> last()'
```
Expected: a result row with a `_value` (the download speed in bits/s).

- [ ] **Step 5: Import community dashboard into Grafana**

Open `https://grafana.lan.<your-domain>` → log in → Dashboards → Import.

Enter dashboard ID **`20860`** (speedtest-tracker community dashboard for InfluxDB v2 / Flux) and click Load.

When prompted for a data source, select **InfluxDB** (the one provisioned in Task 2).

Click Import. You should see download, upload, ping, and jitter panels populate with data from Step 4.

> If dashboard 20860 doesn't match your data, search `https://grafana.com/grafana/dashboards/` for "speedtest tracker influxdb flux" and try another. Popular alternatives: 13665, 16974.

- [ ] **Step 6: Verify alerting works**

Temporarily stop speedtest-tracker:
```bash
docker compose stop speedtest-tracker
```
Wait 35 minutes (30 min data window + 5 min `for:` period). You should receive a Telegram message.

Re-start speedtest-tracker:
```bash
docker compose start speedtest-tracker
```
After the next successful test (~15 min), Telegram should send a resolve notification.

- [ ] **Step 7: Final commit**

```bash
git add speedtest/
git commit -m "feat(speedtest): complete speedtest monitoring stack"
```

---

## Out of Scope

- Secrets management (SOPS / Bitwarden) — tracked in `TODO.md`
- Additional Telegram alert channels
- Public access via vm101
