# Karakeep Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate from Raindrop.io to self-hosted Karakeep on vm101 with local Ollama AI tagging, starting from a clean Raindrop export.

**Architecture:** Raindrop is reorganized to match the new list structure before export. Karakeep + Meilisearch + Chrome (headless) run as a Docker Compose stack on vm101, proxied through the existing Caddy instance. A standalone Ollama container runs qwen3:4b on a shared Docker network, reachable by Karakeep and any future services.

**Tech Stack:** Karakeep (`ghcr.io/karakeep-app/karakeep:release`), Ollama (`ollama/ollama`), Meilisearch (`getmeili/meilisearch:v1.41.0`), Alpine Chrome (`gcr.io/zenika-hub/alpine-chrome:124`), Caddy, Docker Compose

---

## Executor notes

- **Phase 1** (Tasks 1–6): Claude executes via Raindrop MCP tools.
- **Phase 2** (Tasks 7–11): Claude writes files in the worktree; user commits and deploys to vm101.
- **Phase 3** (Tasks 12–13): User runs on vm101.
- **Phase 4** (Task 14): User configures in Karakeep web UI.
- **Phase 5** (Tasks 15–17): User exports/imports; Claude assists with re-tag review if needed.
- **Phase 6** (Tasks 18–21): User performs on desktop, vm101, and mobile.

---

## Reference: Raindrop Collection IDs

| ID | Current Name | Action |
|---|---|---|
| 51769395 | Open Source Repos | Rename → Software |
| 66870400 | Favorite Articles | Rename → Articles |
| 59333046 | YouTube | Rename → Videos |
| 56150101 | Product Research | Rename → Reference |
| 56993558 | Theology Resources | Dissolve → Personal |
| 54977274 | Fitness | Dissolve → Personal |
| 54518339 | Pokemon Emerald Legacy | Dissolve → Personal |
| 53741163 | Games | Delete (empty after child dissolved) |
| 60593795 | Self-hosting | Dissolve → Software |
| 69223999 | AI projects | Dissolve → Software |
| -1 | Unsorted | File all 63 items |

---

## Phase 1: Raindrop Cleanup

### Task 1: Create new collections

- [ ] Create collection named "Personal"
- [ ] Create collection named "Tools & Services"
- [ ] Verify both appear via `find_collections` — note their new IDs for use in Tasks 3 and 5

### Task 2: Rename existing collections

- [ ] Rename collection 51769395 → "Software"
- [ ] Rename collection 66870400 → "Articles"
- [ ] Rename collection 59333046 → "Videos"
- [ ] Rename collection 56150101 → "Reference"
- [ ] Verify via `find_collections`: Software, Articles, Videos, Reference all present

### Task 3: Move bookmarks out of collections being dissolved

For each group below, use `update_bookmarks` with the bookmark IDs, setting the new `collection_id` and **adding** tags (do not replace existing tags — fetch current tags first and merge).

**Theology Resources (56993558) → Personal + tag: theology**
- Both bookmarks in this collection; move to Personal collection ID, add tag `theology`

**Fitness (54977274) → Personal + tag: fitness**
- Both bookmarks in this collection; move to Personal collection ID, add tag `fitness`

**Pokemon Emerald Legacy (54518339) → Personal + tag: gaming**
- Both bookmarks in this collection; move to Personal collection ID, add tag `gaming`

**Self-hosting (60593795) → Software + tag: self-hosting**
- 1 bookmark; move to Software collection ID, add tag `self-hosting`

**AI projects (69223999) → Software + tag: ai**
- 2 bookmarks; move to Software collection ID, add tag `ai`

- [ ] Verify each source collection now shows 0 bookmarks via `find_collections`

### Task 4: Delete empty dissolved collections

- [ ] Delete collection 54518339 (Pokemon Emerald Legacy) — child first
- [ ] Delete collection 53741163 (Games) — parent now empty
- [ ] Delete collection 56993558 (Theology Resources)
- [ ] Delete collection 54977274 (Fitness)
- [ ] Delete collection 60593795 (Self-hosting)
- [ ] Delete collection 69223999 (AI projects)
- [ ] Verify via `find_collections`: only Software, Tools & Services, Articles, Videos, Reference, Personal remain (plus Unsorted and Trash)

### Task 5: File Unsorted bookmarks

Move all 63 unsorted bookmarks (collection_id: -1) to their homes. When updating, fetch current tags first and merge new tags in; do not overwrite.

**→ Reference, tags: copyright + legal** (18 items tagged "8/23/2025")
IDs: 1310355968, 1310355967, 1310355966, 1310355963, 1310355964, 1310355965,
     1310355961, 1310355962, 1310355958, 1310355960, 1310355959, 1310355957,
     1310355956, 1310355955, 1310355954, 1310355953, 1310355952, 1310355951

**→ Personal, tags: bookbinding** (7 items tagged "9/25/2025")
IDs: 1358557373, 1358557370, 1358557371, 1358557372, 1358557368, 1358557369, 1358557367

**→ Personal, tags: gaming** (retrogaming resources tagged "retrogames")
IDs: 1011372191, 988824040, 970938890, 970914037, 970904080, 967570010, 966533104, 964575418, 964575233

**→ Personal, tags: gaming** (Pokemon Emerald Legacy docs, untagged)
IDs: 1017257528, 1017257471

**→ Personal, tags: theology** (tagged "theology")
ID: 985358479

**→ Personal, tags: music**
IDs: 1680200077 (VGMdb), 1680192102 (Sitting on Clouds), 1279039381 (Hype Machine)

**→ Personal, tags: gaming** (DoesItPlay)
ID: 1629063287

**→ Personal, tags: fitness** (Hybrid Calisthenics)
ID: 1552890128

**→ Reference, tags: wiki** (Consumer Rights Wiki)
ID: 1668713346

**→ Tools & Services, tags: tool**
IDs: 1685371785 (CamelCamelCamel), 1573760574 (SimplePDF), 1308491729 (imginn)

**→ Personal** (miscellaneous: photography site, creative writing, health resources)
IDs: 1536516135 (Images of RMNP), 1546894929 (HAVE TAKEN UP FARMING),
     1600577802 (NORM.org), 1600431248 (CIRP.org)

**→ Remaining items (13 not fetched in initial survey)**
- [ ] Run `find_bookmarks` with `collection_ids: [-1]` and `page: 2` to retrieve the remaining items
- [ ] For each: determine the correct list and tags using the same criteria as above, then update

- [ ] Verify Unsorted collection shows 0 bookmarks

### Task 6: Replace date tags with semantic tags

The "8/23/2025" and "9/25/2025" tags were retired in Task 5 (new semantic tags added). Now clean up the stale date tags.

- [ ] Delete tag "8/23/2025" via `delete_tags` — removes it from all bookmarks
- [ ] Delete tag "9/25/2025" via `delete_tags` — removes it from all bookmarks
- [ ] Delete tag "retrogames" via `delete_tags` — replaced by `gaming`
- [ ] Verify via `find_tags`: only semantic tags remain (gaming, theology, fitness, music, self-hosting, ai, bookbinding, copyright, legal, tool, wiki)
- [ ] Commit: `git commit -m "chore: document Raindrop cleanup complete"` (update spec status to note cleanup done)

---

## Phase 2: Infrastructure Files

### Task 7: Create ollama/compose.yaml

**File:** `ollama/compose.yaml`

- [ ] Create the file with this content:

```yaml
name: ollama

networks:
  ollama:
    name: ollama

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    volumes:
      - data:/root/.ollama
    networks:
      - ollama
    environment:
      - OLLAMA_KEEP_ALIVE=5m

volumes:
  data:
    name: ollama_data
```

- [ ] Commit: `git add ollama/compose.yaml && git commit -m "feat: add ollama compose"`

### Task 8: Create karakeep/compose.yaml and karakeep/.env.example

**File:** `karakeep/compose.yaml`

- [ ] Create the file with this content:

```yaml
name: karakeep

networks:
  karakeep-caddy:
    name: karakeep-caddy
  ollama:
    external: true

services:
  web:
    image: ghcr.io/karakeep-app/karakeep:${KARAKEEP_VERSION:-release}
    container_name: karakeep
    restart: unless-stopped
    volumes:
      - data:/data
    networks:
      - karakeep-caddy
      - ollama
      - default
    env_file:
      - .env
    environment:
      MEILI_ADDR: http://meilisearch:7700
      BROWSER_WEB_URL: http://chrome:9222
      DATA_DIR: /data
    depends_on:
      - chrome
      - meilisearch

  chrome:
    image: gcr.io/zenika-hub/alpine-chrome:124
    container_name: karakeep-chrome
    restart: unless-stopped
    command:
      - --no-sandbox
      - --disable-gpu
      - --disable-dev-shm-usage
      - --remote-debugging-address=0.0.0.0
      - --remote-debugging-port=9222
      - --hide-scrollbars

  meilisearch:
    image: getmeili/meilisearch:v1.41.0
    container_name: karakeep-meilisearch
    restart: unless-stopped
    env_file:
      - .env
    environment:
      MEILI_NO_ANALYTICS: "true"
    volumes:
      - meilisearch:/meili_data

volumes:
  data:
    name: karakeep_data
  meilisearch:
    name: karakeep_meilisearch
```

**File:** `karakeep/.env.example`

- [ ] Create the file with this content:

```bash
KARAKEEP_VERSION=release

# Generate both with: openssl rand -base64 36
NEXTAUTH_SECRET=
# MEILI_MASTER_KEY is read by Meilisearch; MEILISEARCH_MASTER_KEY is read by Karakeep — set both to the same value
MEILI_MASTER_KEY=
MEILISEARCH_MASTER_KEY=

# Your actual domain
NEXTAUTH_URL=https://bookmarks.yourdomain.com

# Ollama — container name resolves via shared 'ollama' Docker network
OLLAMA_BASE_URL=http://ollama:11434
INFERENCE_TEXT_MODEL=qwen3:4b
INFERENCE_FETCH_TIMEOUT_SEC=120

# Archiving disabled until 6TB RAID is operational
# To enable: set all four to true
CRAWLER_STORE_SCREENSHOT=false
CRAWLER_FULL_PAGE_SCREENSHOT=false
CRAWLER_STORE_PDF=false
CRAWLER_FULL_PAGE_ARCHIVE=false

# Security
DISABLE_SIGNUPS=true
```

- [ ] Copy `.env.example` to `.env` on vm101 (not committed — contains secrets)
- [ ] Commit: `git add karakeep/ && git commit -m "feat: add karakeep compose and env example"`

### Task 9: Update caddy/vm101/Caddyfile

Add the Karakeep route inside the `*.{$DOMAIN}` block, after the `@immich` block.

- [ ] Add to `caddy/vm101/Caddyfile`:

```caddy
    @karakeep host bookmarks.{$DOMAIN}
    handle @karakeep {
        reverse_proxy karakeep:3000
    }
```

- [ ] Verify the block sits before the catch-all `handle { abort }` at the bottom

### Task 10: Update caddy/vm101/compose.yaml

Add `karakeep-caddy` as an external network so Caddy can reach the Karakeep container.

- [ ] Add to the `networks:` section of `caddy/vm101/compose.yaml`:

```yaml
  karakeep-caddy:
    external: true
```

- [ ] Add `- karakeep-caddy` to the `networks:` list under the `caddy` service

### Task 11: Commit Caddy changes

- [ ] `git add caddy/vm101/Caddyfile caddy/vm101/compose.yaml && git commit -m "feat: add karakeep caddy route"`

---

## Phase 3: Deployment (run on vm101)

### Task 12: Deploy Ollama and pull model

```bash
cd ~/homelab/ollama   # or wherever the repo is synced on vm101
docker compose up -d
docker exec ollama ollama pull qwen3:4b
```

- [ ] Verify: `docker exec ollama ollama list` shows `qwen3:4b`
- [ ] Verify: `curl http://localhost:11434` returns `Ollama is running`

### Task 13: Deploy Karakeep

```bash
cd ~/homelab/karakeep
cp .env.example .env
# Edit .env: fill in NEXTAUTH_SECRET, MEILI_MASTER_KEY, MEILISEARCH_MASTER_KEY, NEXTAUTH_URL
openssl rand -base64 36   # run twice, paste results into .env
docker compose up -d
```

- [ ] Verify: `docker compose ps` shows web, chrome, meilisearch all healthy
- [ ] Verify: `https://bookmarks.<yourdomain>` loads the Karakeep login page

Restart Caddy to pick up the new network and route:

```bash
cd ~/homelab/caddy/vm101
docker compose down && docker compose up -d
```

---

## Phase 4: Karakeep Configuration (web UI)

### Task 14: Configure AI settings

- [ ] Log in to `https://bookmarks.<yourdomain>` and create your account
- [ ] Go to **Settings → AI**
- [ ] Set **Ollama Base URL**: `http://ollama:11434`
- [ ] Set **Model**: `qwen3:4b`
- [ ] Set **Custom Prompt** — prepend `/no_think` to whatever default is shown:

  ```
  /no_think
  Given the following bookmark, suggest between 2 and 5 lowercase tags that describe its topic. Return only a JSON array of strings, no explanation.
  ```

  *(If Karakeep already has a default prompt, prepend `/no_think ` to the start of it.)*

- [ ] Confirm archiving is disabled: **Settings → Crawler** — verify screenshot, PDF, and full-page archive are all off
- [ ] Test AI tagging: save one bookmark manually and confirm tags are generated within ~30 seconds

---

## Phase 5: Migration

### Task 15: Export from Raindrop

- [ ] In Raindrop web app: **Settings → Import & Export → Export**
- [ ] Choose **HTML format** (Netscape bookmark file)
- [ ] Download the file

### Task 16: Import into Karakeep

- [ ] In Karakeep: **Settings → Import**
- [ ] Select the Raindrop HTML export file
- [ ] Confirm import count matches expected (~350 bookmarks across all collections)

### Task 17: Trigger bulk re-tagging and review

Karakeep automatically queues bookmarks for AI tagging when they are added (including on import). Wait for the crawler queue to drain — progress is visible in **Settings → Admin**.

- [ ] Monitor **Settings → Admin** until the crawler queue shows 0 pending jobs
- [ ] Browse each list and spot-check tag quality — look for:
  - Tags that are too generic (e.g., `website`) → delete
  - Near-duplicates (e.g., `self-host` alongside `self-hosting`) → merge by editing bookmarks
  - Missed items that still have no tags → tag manually or re-run AI

---

## Phase 6: Post-Migration Setup

### Task 18: Install Karakeep browser extension

- [ ] Install the Karakeep browser extension on all desktop browsers (see Karakeep docs → Browser Extension)
- [ ] Configure it with your server URL and API key (generated in Karakeep → Settings → API Keys)
- [ ] Test: save a new bookmark from the browser and confirm it appears in Karakeep with tags

### Task 19: Configure SingleFile for on-demand HTML archiving

- [ ] Install [SingleFile extension](https://github.com/gildas-lormeau/SingleFile) in desktop browser
- [ ] In SingleFile settings → **Destinations** → **Upload to REST Form API**:
  - URL: `https://bookmarks.<yourdomain>/api/v1/bookmarks/singlefile`
  - Authorization token: your Karakeep API key
  - Data field name: `file`
  - URL field name: `url`
- [ ] Test: open a webpage, click SingleFile, confirm it appears in Karakeep

### Task 20: Trim vm101 RAM allocation in Proxmox

- [ ] In Proxmox web UI: **VM 101 → Hardware → Memory**
- [ ] Change allocation from **11520 MB** to **8192 MB**
- [ ] Shut down and restart vm101 for the change to take effect
- [ ] Verify: `free -h` inside vm101 shows ~8GB total; all services still running

### Task 21: Install Karakeep mobile apps

- [ ] **iPhone 14**: install Karakeep from the App Store, log in with server URL
- [ ] **Pixel 4a**: install Karakeep from Google Play or F-Droid, log in with server URL
- [ ] Test: use the iOS/Android share sheet to save a URL from the mobile browser
