# TeamSpeak Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a minimal, password-protected TeamSpeak 3 Docker service to the mrgutsy deployment.

**Architecture:** Single container using the official `teamspeak:3.13.7` image with SQLite storage, port `9987/UDP` exposed directly on the host. No Caddy integration — TeamSpeak voice is UDP and cannot be proxied. `ts3.<DOMAIN>` is a DNS A record pointing at the mrgutsy VPS IP, configured outside this repo.

**Tech Stack:** Docker Compose, official `teamspeak:3.13.7` image, SQLite (bundled).

---

### Task 1: Create `.env.example`

**Files:**
- Create: `teamspeak/.env.example`

- [ ] **Step 1: Create the file**

```bash
# teamspeak/.env.example

# Server display name shown in the TS3 client
TS3_SERVER_NAME=My TeamSpeak Server

# Password required to join the server
TS3_SERVER_PASSWORD=changeme

# Maximum concurrent users (free license max: 32)
TS3_SLOTS=10

# Message shown to users on connect (optional, leave blank to disable)
TS3_WELCOME_MESSAGE=
```

- [ ] **Step 2: Commit**

```bash
git add teamspeak/.env.example
git commit -m "feat(teamspeak): add .env.example"
```

---

### Task 2: Create `compose.yaml`

**Files:**
- Create: `teamspeak/compose.yaml`

- [ ] **Step 1: Create the file**

```yaml
name: teamspeak

volumes:
  data:

services:
  teamspeak:
    image: teamspeak:3.13.7
    container_name: teamspeak
    restart: unless-stopped
    ports:
      - "9987:9987/udp"
    environment:
      - TS3SERVER_LICENSE=accept
      - TS3SERVER_DB_PLUGIN=ts3db_sqlite3
      - TS3SERVER_DB_SQLCREATEPATH=create_sqlite
      - TS3SERVER_SERVER_NAME=${TS3_SERVER_NAME}
      - TS3SERVER_SERVER_PASSWORD=${TS3_SERVER_PASSWORD}
      - TS3SERVER_MAXCLIENTS=${TS3_SLOTS}
      - TS3SERVER_WELCOME_MESSAGE=${TS3_WELCOME_MESSAGE}
    volumes:
      - data:/var/ts3server
    healthcheck:
      test: ["CMD-SHELL", "nc -zu localhost 9987 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

- [ ] **Step 2: Validate compose syntax**

```bash
docker compose -f teamspeak/compose.yaml config --quiet
```

Expected: no output, exit code 0. If it errors, fix the YAML syntax before continuing.

- [ ] **Step 3: Commit**

```bash
git add teamspeak/compose.yaml
git commit -m "feat(teamspeak): add Docker Compose service"
```

---

### Task 3: Deploy to mrgutsy

These steps run on the mrgutsy VPS, not locally.

- [ ] **Step 1: Copy `.env.example` to `.env` and fill in real values**

```bash
cp teamspeak/.env.example teamspeak/.env
```

Edit `teamspeak/.env`:
- Set `TS3_SERVER_NAME` to your desired server name
- Set `TS3_SERVER_PASSWORD` to a strong password
- Set `TS3_SLOTS=10` (or adjust)
- Optionally set `TS3_WELCOME_MESSAGE`

- [ ] **Step 2: Pull the repo on mrgutsy and start the container**

```bash
git pull
cd teamspeak
docker compose up -d
```

Expected: Docker pulls `teamspeak:3.13.7`, starts the container, prints "Started".

- [ ] **Step 3: Verify the container is healthy**

```bash
docker compose ps
```

Expected: `teamspeak` shows `healthy` status (may take up to 30s for `start_period` to elapse).

- [ ] **Step 4: Check logs for the admin token**

On first boot, TeamSpeak prints a `serveradmin` token to the logs. Save it somewhere secure — you'll need it if you ever want to claim server admin in the TS3 client.

```bash
docker compose logs teamspeak | grep -i token
```

Expected: a line like:
```
ServerAdmin privilege key created, please use the line below
token=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

- [ ] **Step 5: Connect with the TS3 client**

Open the TeamSpeak 3 client and connect to `ts3.<DOMAIN>` (or the mrgutsy IP directly if DNS isn't set up yet). Enter the server password when prompted. Verify the server name and slot count match what you configured.

---

### DNS note (out of scope for this repo)

Add an A record in your DNS provider:

| Name | Type | Value |
|------|------|-------|
| `ts3` | A | `<mrgutsy public IP>` |

The TS3 client connects to `ts3.<DOMAIN>:9987` by default (standard port, no port suffix needed in the client address field).
