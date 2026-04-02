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
    local entry name mac entries
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
#   Format: <MAC>IP>>hostname<MAC>IP>>hostname
#   Static entries represent DHCP reservations and persist even when the
#   device is offline.
parse_staticlist() {
    local raw="$1"
    [[ -z "$raw" ]] && return
    local entry mac ip entries
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
        if [[ -n "$mac" && -n "$ip" && -z "${mac_to_ip[$mac]+set}" ]]; then
            mac_to_ip["$mac"]="$ip"
        fi
    done <<< "$raw"
}

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
        -o "StrictHostKeyChecking=yes" \
        -o "ConnectTimeout=10" \
        -o "BatchMode=yes" \
        "${ROUTER_USER}@${ROUTER_HOST}" \
        'printf "CLIENTLIST\t%s\n" "$(nvram get custom_clientlist)";
         printf "STATICLIST\t%s\n" "$(nvram get dhcp_staticlist)";
         while IFS= read -r line; do printf "LEASE\t%s\n" "$line"; done \
             < /var/lib/misc/dnsmasq.leases'
}

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

# ── Main (skipped in test mode) ───────────────────────────────────────────────

[[ "${TEST_MODE:-0}" == "1" ]] && return 0

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

main "$@"
