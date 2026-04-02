# router-sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Docker Compose service that syncs custom client names from an Asuswrt-Merlin router into AdGuard Home persistent clients on a configurable schedule.

**Architecture:** An Alpine container runs `sync.sh` via `crond`. The script SSHs to the router once per run to fetch `custom_clientlist`, `dhcp_staticlist`, and `dnsmasq.leases`, joins them on MAC to produce an IP→Name map, then reconciles that map against AGH's persistent client list using the AGH REST API. Clients created by the script are tagged `router_sync` so they can be distinguished from manually created clients.

**Tech Stack:** bash 5, Alpine crond, openssh-client, curl, jq, bats-core (tests only)

---

## File Map

| File | Purpose |
|---|---|
| `router-sync/Dockerfile` | Builds the Alpine image with required packages |
| `router-sync/entrypoint.sh` | Writes crontab from `SYNC_INTERVAL_MINUTES`, runs sync once at startup, starts crond in foreground |
| `router-sync/sync.sh` | All sync logic: fetch, parse, join, reconcile |
| `router-sync/compose.yaml` | Docker Compose service definition |
| `router-sync/.env.example` | Documents required environment variables |
| `router-sync/known_hosts` | Router SSH host key (committed, not secret) |
| `router-sync/tests/test_parse.bats` | Unit tests for parsing functions |
| `router-sync/tests/test_join.bats` | Unit tests for merge/join logic |

---

## Pre-flight: Verify dhcp_staticlist format

Before starting, SSH to the router and run:

```bash
nvram get dhcp_staticlist
```

The spec assumes the format is `MAC>IP<MAC>IP<...` (same `<`/`>` conventions as `custom_clientlist`). Confirm the output matches this. If the format differs, update the `parse_staticlist` function in Task 3 accordingly. A typical result looks like:

```
BC:24:11:C4:7A:9A>192.168.10.100<BC:24:11:B6:2D:2E>192.168.10.101
```

---

## Task 1: Scaffold — Dockerfile and .env.example

**Files:**
- Create: `router-sync/Dockerfile`
- Create: `router-sync/.env.example`

- [ ] **Step 1: Create the Dockerfile**

```dockerfile
FROM alpine:3.21

RUN apk add --no-cache bash openssh-client curl jq

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY sync.sh /usr/local/bin/sync.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/sync.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

- [ ] **Step 2: Create .env.example**

```bash
ROUTER_HOST=192.168.10.1
ROUTER_USER=admin
AGH_URL=http://adguard-home
AGH_USER=admin
AGH_PASSWORD=changeme
SYNC_INTERVAL_MINUTES=10
```

- [ ] **Step 3: Add secrets and key to .gitignore**

Append to `/home/malc/homelab/.gitignore` (create it if it does not exist):

```
router-sync/.env
router-sync/id_ed25519
```

- [ ] **Step 4: Commit**

```bash
git add router-sync/Dockerfile router-sync/.env.example .gitignore
git commit -m "feat(router-sync): scaffold Dockerfile and env example"
```

---

## Task 2: Install bats-core for local testing

**Files:** none committed

bats-core is used only during development to run unit tests locally. It does not go inside the container.

- [ ] **Step 1: Install bats-core**

```bash
sudo apt-get install -y bats
```

If not available via apt:

```bash
git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
sudo /tmp/bats-core/install.sh /usr/local
```

Verify:

```bash
bats --version
```

Expected output: `Bats 1.x.x`

---

## Task 3: Parsing functions and tests

**Files:**
- Create: `router-sync/sync.sh` (parsing functions only; main() stubbed)
- Create: `router-sync/tests/test_parse.bats`

The three `parse_*` functions each accept a raw string and populate global bash associative arrays. `parse_clientlist` fills `mac_to_name`; `parse_staticlist` and `parse_leases` both fill `mac_to_ip`. All MACs are normalised to lowercase on write.

- [ ] **Step 1: Write the failing tests**

Create `router-sync/tests/test_parse.bats`:

```bash
#!/usr/bin/env bats

setup() {
    # Source sync.sh without running main()
    TEST_MODE=1 source "${BATS_TEST_DIRNAME}/../sync.sh"
}

# ── parse_clientlist ──────────────────────────────────────────────────────────

@test "parse_clientlist: extracts name and normalises MAC to lowercase" {
    declare -gA mac_to_name=()
    parse_clientlist "MyDevice>AA:BB:CC:DD:EE:FF>0>0>>>>>"
    [ "${mac_to_name[aa:bb:cc:dd:ee:ff]}" = "MyDevice" ]
}

@test "parse_clientlist: handles multiple entries separated by <" {
    declare -gA mac_to_name=()
    parse_clientlist "Device1>AA:BB:CC:DD:EE:FF>0>0>>>>><Device2>11:22:33:44:55:66>0>0>>>>>"
    [ "${mac_to_name[aa:bb:cc:dd:ee:ff]}" = "Device1" ]
    [ "${mac_to_name[11:22:33:44:55:66]}" = "Device2" ]
}

@test "parse_clientlist: skips empty entries" {
    declare -gA mac_to_name=()
    parse_clientlist "<Device1>AA:BB:CC:DD:EE:FF>0>0>>>>><"
    [ "${#mac_to_name[@]}" -eq 1 ]
}

@test "parse_clientlist: preserves names with spaces and apostrophes" {
    declare -gA mac_to_name=()
    parse_clientlist "Grace's iPhone>EA:E9:D6:45:DB:24>0>10>>>>>"
    [ "${mac_to_name[ea:e9:d6:45:db:24]}" = "Grace's iPhone" ]
}

# ── parse_staticlist ──────────────────────────────────────────────────────────

@test "parse_staticlist: extracts MAC and IP, normalises MAC to lowercase" {
    declare -gA mac_to_ip=()
    parse_staticlist "BC:24:11:C4:7A:9A>192.168.10.100"
    [ "${mac_to_ip[bc:24:11:c4:7a:9a]}" = "192.168.10.100" ]
}

@test "parse_staticlist: handles multiple entries" {
    declare -gA mac_to_ip=()
    parse_staticlist "BC:24:11:C4:7A:9A>192.168.10.100<BC:24:11:B6:2D:2E>192.168.10.101"
    [ "${mac_to_ip[bc:24:11:c4:7a:9a]}" = "192.168.10.100" ]
    [ "${mac_to_ip[bc:24:11:b6:2d:2e]}" = "192.168.10.101" ]
}

@test "parse_staticlist: empty input produces empty map" {
    declare -gA mac_to_ip=()
    parse_staticlist ""
    [ "${#mac_to_ip[@]}" -eq 0 ]
}

# ── parse_leases ──────────────────────────────────────────────────────────────

@test "parse_leases: extracts MAC and IP from lease line" {
    declare -gA mac_to_ip=()
    parse_leases "86274 bc:24:11:c4:7a:9a 192.168.10.100 vm100 ff:bc:24:11:c4:7a:9a"
    [ "${mac_to_ip[bc:24:11:c4:7a:9a]}" = "192.168.10.100" ]
}

@test "parse_leases: does not overwrite existing static entries" {
    declare -gA mac_to_ip=([bc:24:11:c4:7a:9a]="192.168.10.100")
    parse_leases "86274 bc:24:11:c4:7a:9a 10.0.0.99 vm100 *"
    [ "${mac_to_ip[bc:24:11:c4:7a:9a]}" = "192.168.10.100" ]
}

@test "parse_leases: handles multiple lines" {
    declare -gA mac_to_ip=()
    parse_leases "$(printf '86274 aa:bb:cc:dd:ee:ff 192.168.10.1 host1 *\n86274 11:22:33:44:55:66 192.168.10.2 host2 *')"
    [ "${mac_to_ip[aa:bb:cc:dd:ee:ff]}" = "192.168.10.1" ]
    [ "${mac_to_ip[11:22:33:44:55:66]}" = "192.168.10.2" ]
}

@test "parse_leases: normalises MAC to lowercase" {
    declare -gA mac_to_ip=()
    parse_leases "86274 AA:BB:CC:DD:EE:FF 192.168.10.1 host1 *"
    [ "${mac_to_ip[aa:bb:cc:dd:ee:ff]}" = "192.168.10.1" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/malc/homelab/router-sync
bats tests/test_parse.bats
```

Expected: all tests fail with `sync.sh: No such file or directory` or similar — confirming the tests are wired correctly.

- [ ] **Step 3: Create sync.sh with the parse functions**

Create `router-sync/sync.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ── Logging ───────────────────────────────────────────────────────────────────

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

# ── Parsing ───────────────────────────────────────────────────────────────────

# parse_clientlist RAW
#   Populates global mac_to_name[MAC]=Name from custom_clientlist nvram value.
#   Format: NAME>MAC>...<NAME>MAC>...
parse_clientlist() {
    local raw="$1"
    local entry name mac
    IFS='<' read -ra entries <<< "$raw"
    for entry in "${entries[@]}"; do
        [[ -z "$entry" ]] && continue
        name=$(printf '%s' "$entry" | cut -d'>' -f1)
        mac=$(printf '%s' "$entry" | cut -d'>' -f2 | tr '[:upper:]' '[:lower:]')
        [[ -n "$name" && -n "$mac" ]] && mac_to_name["$mac"]="$name"
    done
}

# parse_staticlist RAW
#   Populates global mac_to_ip[MAC]=IP from dhcp_staticlist nvram value.
#   Format: MAC>IP<MAC>IP
#   Static entries represent DHCP reservations and persist even when the
#   device is offline.
parse_staticlist() {
    local raw="$1"
    [[ -z "$raw" ]] && return
    local entry mac ip
    IFS='<' read -ra entries <<< "$raw"
    for entry in "${entries[@]}"; do
        [[ -z "$entry" ]] && continue
        mac=$(printf '%s' "$entry" | cut -d'>' -f1 | tr '[:upper:]' '[:lower:]')
        ip=$(printf '%s' "$entry" | cut -d'>' -f2)
        [[ -n "$mac" && -n "$ip" ]] && mac_to_ip["$mac"]="$ip"
    done
}

# parse_leases RAW
#   Populates global mac_to_ip[MAC]=IP from dnsmasq.leases content.
#   Format per line: TIMESTAMP MAC IP HOSTNAME CLIENT_ID
#   Does NOT overwrite entries already set by parse_staticlist.
parse_leases() {
    local raw="$1"
    local line mac ip
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        mac=$(awk '{print $2}' <<< "$line" | tr '[:upper:]' '[:lower:]')
        ip=$(awk '{print $3}' <<< "$line")
        [[ -n "$mac" && -n "$ip" && -z "${mac_to_ip[$mac]+set}" ]] && mac_to_ip["$mac"]="$ip"
    done <<< "$raw"
}

# ── Main (skipped in test mode) ───────────────────────────────────────────────

[[ "${TEST_MODE:-0}" == "1" ]] && return 0

main() {
    log "router-sync starting"
}

main "$@"
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /home/malc/homelab/router-sync
bats tests/test_parse.bats
```

Expected: all 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add router-sync/sync.sh router-sync/tests/test_parse.bats
git commit -m "feat(router-sync): add parsing functions with tests"
```

---

## Task 4: Join logic and tests

**Files:**
- Modify: `router-sync/sync.sh` (add `build_ip_name_map`)
- Create: `router-sync/tests/test_join.bats`

- [ ] **Step 1: Write the failing tests**

Create `router-sync/tests/test_join.bats`:

```bash
#!/usr/bin/env bats

setup() {
    TEST_MODE=1 source "${BATS_TEST_DIRNAME}/../sync.sh"
}

@test "build_ip_name_map: joins mac_to_name and mac_to_ip on MAC" {
    declare -gA mac_to_name=([aa:bb:cc:dd:ee:ff]="MyDevice")
    declare -gA mac_to_ip=([aa:bb:cc:dd:ee:ff]="192.168.10.10")
    declare -gA ip_to_name=()
    build_ip_name_map
    [ "${ip_to_name[192.168.10.10]}" = "MyDevice" ]
}

@test "build_ip_name_map: skips entries with no IP match" {
    declare -gA mac_to_name=([aa:bb:cc:dd:ee:ff]="Offline")
    declare -gA mac_to_ip=()
    declare -gA ip_to_name=()
    build_ip_name_map
    [ "${#ip_to_name[@]}" -eq 0 ]
}

@test "build_ip_name_map: maps multiple devices" {
    declare -gA mac_to_name=(
        [aa:bb:cc:dd:ee:ff]="Device1"
        [11:22:33:44:55:66]="Device2"
    )
    declare -gA mac_to_ip=(
        [aa:bb:cc:dd:ee:ff]="192.168.10.10"
        [11:22:33:44:55:66]="192.168.10.11"
    )
    declare -gA ip_to_name=()
    build_ip_name_map
    [ "${ip_to_name[192.168.10.10]}" = "Device1" ]
    [ "${ip_to_name[192.168.10.11]}" = "Device2" ]
}

@test "build_ip_name_map: static IP takes precedence when MAC appears in both maps" {
    # mac_to_ip is already merged (static wins) by the time build_ip_name_map runs.
    # Confirm the correct IP is used in the join.
    declare -gA mac_to_name=([bc:24:11:c4:7a:9a]="vm100")
    declare -gA mac_to_ip=([bc:24:11:c4:7a:9a]="192.168.10.100")
    declare -gA ip_to_name=()
    build_ip_name_map
    [ "${ip_to_name[192.168.10.100]}" = "vm100" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/malc/homelab/router-sync
bats tests/test_join.bats
```

Expected: all tests fail with `build_ip_name_map: command not found`.

- [ ] **Step 3: Add build_ip_name_map to sync.sh**

Insert after the `parse_leases` function, before the `# ── Main` comment:

```bash
# ── Join ──────────────────────────────────────────────────────────────────────

# build_ip_name_map
#   Reads global mac_to_name and mac_to_ip; populates global ip_to_name[IP]=Name.
#   Skips any MAC in mac_to_name that has no entry in mac_to_ip.
build_ip_name_map() {
    local mac name ip
    for mac in "${!mac_to_name[@]}"; do
        name="${mac_to_name[$mac]}"
        ip="${mac_to_ip[$mac]+${mac_to_ip[$mac]}}"
        [[ -z "$ip" ]] && continue
        ip_to_name["$ip"]="$name"
    done
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /home/malc/homelab/router-sync
bats tests/test_join.bats
```

Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add router-sync/sync.sh router-sync/tests/test_join.bats
git commit -m "feat(router-sync): add join logic with tests"
```

---

## Task 5: SSH fetch function

**Files:**
- Modify: `router-sync/sync.sh` (add `fetch_router_data`)

This function opens one SSH connection and emits prefixed lines so the caller can split output by source without running SSH three times.

- [ ] **Step 1: Add fetch_router_data to sync.sh**

Insert after the `# ── Join` block, before `# ── Main`:

```bash
# ── Router fetch ──────────────────────────────────────────────────────────────

# fetch_router_data
#   Opens one SSH connection to the router and emits tab-prefixed lines:
#     CLIENTLIST\t<nvram custom_clientlist value>
#     STATICLIST\t<nvram dhcp_staticlist value>
#     LEASE\t<one dnsmasq.leases line per LEASE-prefixed line>
#
#   Callers extract each section with awk:
#     clientlist=$(awk -F'\t' '$1=="CLIENTLIST"{print $2}' <<< "$data")
fetch_router_data() {
    ssh \
        -i "${SSH_KEY}" \
        -o "UserKnownHostsFile=${KNOWN_HOSTS}" \
        -o "ConnectTimeout=10" \
        -o "BatchMode=yes" \
        "${ROUTER_USER}@${ROUTER_HOST}" \
        'printf "CLIENTLIST\t%s\n" "$(nvram get custom_clientlist)";
         printf "STATICLIST\t%s\n" "$(nvram get dhcp_staticlist)";
         while IFS= read -r line; do printf "LEASE\t%s\n" "$line"; done \
             < /var/lib/misc/dnsmasq.leases'
}
```

- [ ] **Step 2: Add configuration validation to the top of the main() stub**

Replace the existing stub `main()`:

```bash
main() {
    # ── Configuration ─────────────────────────────────────────────────────────
    : "${ROUTER_HOST:?ROUTER_HOST is required}"
    : "${ROUTER_USER:?ROUTER_USER is required}"
    : "${AGH_URL:?AGH_URL is required}"
    : "${AGH_USER:?AGH_USER is required}"
    : "${AGH_PASSWORD:?AGH_PASSWORD is required}"
    SSH_KEY="${SSH_KEY:-/root/.ssh/id_ed25519}"
    KNOWN_HOSTS="${KNOWN_HOSTS:-/root/.ssh/known_hosts}"

    log "router-sync starting"
}
```

Placing config inside `main()` means sourcing the file in tests (with `TEST_MODE=1`) never hits the required-variable checks. Functions that use `SSH_KEY`, `KNOWN_HOSTS`, etc. access them as globals set by `main()` at runtime.

- [ ] **Step 3: Manually verify the fetch function against the live router**

With a `.env` file present at `router-sync/.env`, run:

```bash
cd /home/malc/homelab/router-sync
set -a; source .env; set +a
SSH_KEY=~/.ssh/router_sync_id \
KNOWN_HOSTS=./known_hosts \
bash -c 'source sync.sh; fetch_router_data' 2>/dev/null | head -5
```

Expected: lines beginning with `CLIENTLIST`, `STATICLIST`, and `LEASE` prefixes.

- [ ] **Step 4: Commit**

```bash
git add router-sync/sync.sh
git commit -m "feat(router-sync): add SSH fetch function"
```

---

## Task 6: AGH API functions

**Files:**
- Modify: `router-sync/sync.sh` (add `get_agh_synced_clients`, `add_agh_client`, `update_agh_client`, `delete_agh_client`)

All four functions use HTTP Basic Auth. `get_agh_synced_clients` returns a JSON array. The other three return 0 on success, 1 on failure, and always log the outcome.

- [ ] **Step 1: Add AGH API functions to sync.sh**

Insert after the `# ── Router fetch` block, before `# ── Main`:

```bash
# ── AGH API ───────────────────────────────────────────────────────────────────

# get_agh_synced_clients
#   Fetches all AGH persistent clients tagged router_sync.
#   Outputs a JSON array (may be empty: []).
get_agh_synced_clients() {
    curl -sf \
        -u "${AGH_USER}:${AGH_PASSWORD}" \
        "${AGH_URL}/control/clients" \
    | jq '[.clients[] | select(.tags != null and (.tags | contains(["router_sync"])))]'
}

# _agh_client_body NAME IP
#   Emits the JSON object used for add and update payloads.
_agh_client_body() {
    jq -n \
        --arg name "$1" \
        --arg ip   "$2" \
        '{"name":$name,"ids":[$ip],"tags":["router_sync"],
          "use_global_settings":true,"filtering_enabled":false,
          "parental_enabled":false,"safebrowsing_enabled":false,
          "upstreams":[]}'
}

# add_agh_client NAME IP
add_agh_client() {
    local name="$1" ip="$2"
    local http_code
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        -X POST \
        -u "${AGH_USER}:${AGH_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "$(_agh_client_body "$name" "$ip")" \
        "${AGH_URL}/control/clients/add") || http_code="000"
    if [[ "$http_code" == "200" ]]; then
        log "  + added: $name ($ip)"
    else
        log "  ERROR: failed to add $name ($ip) — HTTP $http_code"
        return 1
    fi
}

# update_agh_client OLD_NAME NEW_NAME IP
update_agh_client() {
    local old_name="$1" new_name="$2" ip="$3"
    local body http_code
    body=$(jq -n \
        --arg old_name "$old_name" \
        --argjson data "$(_agh_client_body "$new_name" "$ip")" \
        '{"name":$old_name,"data":$data}')
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        -X POST \
        -u "${AGH_USER}:${AGH_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "${AGH_URL}/control/clients/update") || http_code="000"
    if [[ "$http_code" == "200" ]]; then
        log "  ~ updated: $old_name → $new_name ($ip)"
    else
        log "  ERROR: failed to update $old_name → $new_name ($ip) — HTTP $http_code"
        return 1
    fi
}

# delete_agh_client NAME
delete_agh_client() {
    local name="$1"
    local http_code
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        -X POST \
        -u "${AGH_USER}:${AGH_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg name "$name" '{"name":$name}')" \
        "${AGH_URL}/control/clients/delete") || http_code="000"
    if [[ "$http_code" == "200" ]]; then
        log "  - removed: $name"
    else
        log "  ERROR: failed to remove $name — HTTP $http_code"
        return 1
    fi
}
```

- [ ] **Step 2: Manually verify get_agh_synced_clients against live AGH**

```bash
cd /home/malc/homelab/router-sync
set -a; source .env; set +a
bash -c 'source sync.sh; get_agh_synced_clients'
```

Expected: a JSON array (empty `[]` on first run, since no clients are tagged yet).

- [ ] **Step 3: Commit**

```bash
git add router-sync/sync.sh
git commit -m "feat(router-sync): add AGH API functions"
```

---

## Task 7: Main reconciliation logic

**Files:**
- Modify: `router-sync/sync.sh` (replace stub `main()`)

- [ ] **Step 1: Replace the stub main() in sync.sh**

Replace the existing `main()` function (the three-line stub) with:

```bash
main() {
    # ── Configuration ─────────────────────────────────────────────────────────
    : "${ROUTER_HOST:?ROUTER_HOST is required}"
    : "${ROUTER_USER:?ROUTER_USER is required}"
    : "${AGH_URL:?AGH_URL is required}"
    : "${AGH_USER:?AGH_USER is required}"
    : "${AGH_PASSWORD:?AGH_PASSWORD is required}"
    SSH_KEY="${SSH_KEY:-/root/.ssh/id_ed25519}"
    KNOWN_HOSTS="${KNOWN_HOSTS:-/root/.ssh/known_hosts}"

    declare -gA mac_to_name=()
    declare -gA mac_to_ip=()
    declare -gA ip_to_name=()

    # ── Fetch ────────────────────────────────────────────────────────────────
    log "Fetching router data..."
    local router_data
    router_data=$(fetch_router_data)

    local clientlist staticlist leases
    clientlist=$(awk -F'\t' '$1=="CLIENTLIST"{print $2}' <<< "$router_data")
    staticlist=$(awk -F'\t' '$1=="STATICLIST"{print $2}' <<< "$router_data")
    leases=$(awk -F'\t' '$1=="LEASE"{print $2}' <<< "$router_data")

    # ── Parse + join ─────────────────────────────────────────────────────────
    parse_clientlist "$clientlist"
    parse_staticlist "$staticlist"
    parse_leases     "$leases"
    build_ip_name_map

    local client_count="${#ip_to_name[@]}"
    log "Router clients resolved: $client_count"

    # ── Reconcile ────────────────────────────────────────────────────────────
    local synced_clients added=0 updated=0 removed=0 errors=0
    synced_clients=$(get_agh_synced_clients)

    # Add or update
    local ip name existing_name
    for ip in "${!ip_to_name[@]}"; do
        name="${ip_to_name[$ip]}"
        existing_name=$(jq -r --arg ip "$ip" \
            '.[] | select(.ids | contains([$ip])) | .name' \
            <<< "$synced_clients")

        if [[ -z "$existing_name" ]]; then
            add_agh_client "$name" "$ip" && (( added++ )) || (( errors++ ))
        elif [[ "$existing_name" != "$name" ]]; then
            update_agh_client "$existing_name" "$name" "$ip" \
                && (( updated++ )) || (( errors++ ))
        fi
    done

    # Remove stale router-synced clients
    local client_json client_name client_ip still_present
    while IFS= read -r client_json; do
        client_name=$(jq -r '.name' <<< "$client_json")
        client_ip=$(jq -r '.ids[0]' <<< "$client_json")
        still_present=false
        [[ -n "${ip_to_name[$client_ip]+set}" ]] && still_present=true
        if [[ "$still_present" == false ]]; then
            delete_agh_client "$client_name" && (( removed++ )) || (( errors++ ))
        fi
    done < <(jq -c '.[]' <<< "$synced_clients")

    log "sync complete: $client_count clients resolved, $added added, $updated updated, $removed removed, $errors errors"
    [[ "$errors" -eq 0 ]]
}
```

- [ ] **Step 2: Run a full end-to-end test against live systems**

```bash
cd /home/malc/homelab/router-sync
set -a; source .env; set +a
SSH_KEY=~/.ssh/router_sync_id \
KNOWN_HOSTS=./known_hosts \
bash sync.sh
```

Expected output (values will differ):

```
[2026-04-01T10:00:00Z] Fetching router data...
[2026-04-01T10:00:01Z] Router clients resolved: 18
[2026-04-01T10:00:01Z]   + added: vm100 (192.168.10.100)
[2026-04-01T10:00:02Z]   + added: pi (192.168.10.x)
...
[2026-04-01T10:00:05Z] sync complete: 18 clients resolved, 18 added, 0 updated, 0 removed, 0 errors
```

Verify in the AGH UI that new persistent clients appear with the `router_sync` tag.

- [ ] **Step 3: Run sync a second time to verify idempotency**

```bash
SSH_KEY=~/.ssh/router_sync_id \
KNOWN_HOSTS=./known_hosts \
bash sync.sh
```

Expected: `0 added, 0 updated, 0 removed, 0 errors` — nothing changes on repeat runs.

- [ ] **Step 4: Commit**

```bash
git add router-sync/sync.sh
git commit -m "feat(router-sync): add main reconciliation logic"
```

---

## Task 8: Entrypoint and cron

**Files:**
- Create: `router-sync/entrypoint.sh`

- [ ] **Step 1: Create entrypoint.sh**

```bash
#!/usr/bin/env sh
set -eu

SYNC_INTERVAL_MINUTES="${SYNC_INTERVAL_MINUTES:-10}"

# Validate interval is a positive integer
case "$SYNC_INTERVAL_MINUTES" in
    ''|*[!0-9]*) echo "ERROR: SYNC_INTERVAL_MINUTES must be a positive integer" >&2; exit 1 ;;
esac

# Write crontab — redirect to container stdout/stderr so logs appear in docker logs
echo "*/${SYNC_INTERVAL_MINUTES} * * * * /usr/local/bin/sync.sh >> /proc/1/fd/1 2>&1" \
    > /etc/crontabs/root

echo "Cron schedule: every ${SYNC_INTERVAL_MINUTES} minute(s)"

# Run once immediately at container start so there is no wait on first deploy
echo "Running initial sync..."
/usr/local/bin/sync.sh || echo "Initial sync failed — will retry on next cron interval"

# Start crond in foreground as PID 1
exec crond -f -l 2
```

- [ ] **Step 2: Make entrypoint.sh executable in the repo**

```bash
chmod +x router-sync/entrypoint.sh
```

- [ ] **Step 3: Commit**

```bash
git add router-sync/entrypoint.sh
git commit -m "feat(router-sync): add entrypoint with cron scheduling"
```

---

## Task 9: compose.yaml

**Files:**
- Create: `router-sync/compose.yaml`

- [ ] **Step 1: Create compose.yaml**

```yaml
networks:
  caddy-internal:
    name: caddy-internal
    external: true

services:
  router-sync:
    container_name: router-sync
    build: .
    restart: always
    networks:
      - caddy-internal
    env_file: .env
    volumes:
      - ~/.ssh/router_sync_id:/root/.ssh/id_ed25519:ro
      - ./known_hosts:/root/.ssh/known_hosts:ro
```

- [ ] **Step 2: Commit**

```bash
git add router-sync/compose.yaml
git commit -m "feat(router-sync): add compose.yaml"
```

---

## Task 10: SSH known_hosts and one-time key setup

**Files:**
- Create: `router-sync/known_hosts` (committed)

This task is performed once on the homelab host, not inside the container.

- [ ] **Step 1: Generate the dedicated SSH keypair**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/router_sync_id -C "router-sync" -N ""
```

- [ ] **Step 2: Add the public key to the router**

```bash
ssh admin@192.168.10.1 "cat >> /jffs/.ssh/authorized_keys" < ~/.ssh/router_sync_id.pub
```

Verify:

```bash
ssh -i ~/.ssh/router_sync_id admin@192.168.10.1 "echo ok"
```

Expected output: `ok`

- [ ] **Step 3: Capture the router's host key**

```bash
ssh-keyscan 192.168.10.1 > /home/malc/homelab/router-sync/known_hosts
```

- [ ] **Step 4: Commit known_hosts**

```bash
git add router-sync/known_hosts
git commit -m "feat(router-sync): add router SSH known_hosts"
```

---

## Task 11: Build and deploy

- [ ] **Step 1: Build the image**

```bash
cd /home/malc/homelab/router-sync
docker compose build
```

Expected: image builds without errors.

- [ ] **Step 2: Start the service**

```bash
docker compose up -d
```

- [ ] **Step 3: Verify startup logs**

```bash
docker logs router-sync
```

Expected: initial sync log lines ending with `sync complete: ... 0 errors`.

- [ ] **Step 4: Verify AGH clients in the UI**

Open AdGuard Home and navigate to **Settings → Client Settings**. Confirm router-synced clients appear with the `router_sync` tag and correct names.

- [ ] **Step 5: Wait one interval and verify cron fires**

```bash
docker logs --follow router-sync
```

After `SYNC_INTERVAL_MINUTES` minutes, a second sync run should appear in the logs.

- [ ] **Step 6: Final commit — add service to README**

Add `router-sync` to the Private services table in `/home/malc/homelab/README.md`:

```markdown
- [router-sync](/router-sync/) (April 2026)
```

```bash
git add README.md
git commit -m "docs: add router-sync to README"
```
