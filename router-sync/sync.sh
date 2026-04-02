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

# ── Main (skipped in test mode) ───────────────────────────────────────────────

[[ "${TEST_MODE:-0}" == "1" ]] && return 0

main() {
    log "router-sync starting"
}

main "$@"
