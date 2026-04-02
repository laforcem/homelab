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
        -o "ConnectTimeout=10" \
        -o "BatchMode=yes" \
        "${ROUTER_USER}@${ROUTER_HOST}" \
        'printf "CLIENTLIST\t%s\n" "$(nvram get custom_clientlist)";
         printf "STATICLIST\t%s\n" "$(nvram get dhcp_staticlist)";
         while IFS= read -r line; do printf "LEASE\t%s\n" "$line"; done \
             < /var/lib/misc/dnsmasq.leases'
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
