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
    parse_staticlist "<BC:24:11:C4:7A:9A>192.168.10.100>>vm100"
    [ "${mac_to_ip[bc:24:11:c4:7a:9a]}" = "192.168.10.100" ]
}

@test "parse_staticlist: handles multiple entries with leading <" {
    declare -gA mac_to_ip=()
    parse_staticlist "<BC:24:11:C4:7A:9A>192.168.10.100>>vm100<BC:24:11:B6:2D:2E>192.168.10.101>>vm101"
    [ "${mac_to_ip[bc:24:11:c4:7a:9a]}" = "192.168.10.100" ]
    [ "${mac_to_ip[bc:24:11:b6:2d:2e]}" = "192.168.10.101" ]
}

@test "parse_staticlist: empty input produces empty map" {
    declare -gA mac_to_ip=()
    parse_staticlist ""
    [ "${#mac_to_ip[@]}" -eq 0 ]
}

# ── parse_arp ─────────────────────────────────────────────────────────────────

@test "parse_arp: extracts IP and normalises MAC to lowercase for complete entries" {
    declare -gA mac_to_ip=()
    parse_arp "192.168.10.100   0x1         0x2         BC:24:11:C4:7A:9A     *        br0"
    [ "${mac_to_ip[bc:24:11:c4:7a:9a]}" = "192.168.10.100" ]
}

@test "parse_arp: skips incomplete entries (flags != 0x2)" {
    declare -gA mac_to_ip=()
    parse_arp "192.168.10.14    0x1         0x0         00:00:00:00:00:00     *        br0"
    [ "${#mac_to_ip[@]}" -eq 0 ]
}

@test "parse_arp: skips zero MAC addresses" {
    declare -gA mac_to_ip=()
    parse_arp "192.168.10.14    0x1         0x2         00:00:00:00:00:00     *        br0"
    [ "${#mac_to_ip[@]}" -eq 0 ]
}

@test "parse_arp: does not overwrite entries already set by parse_staticlist" {
    declare -gA mac_to_ip=([bc:24:11:c4:7a:9a]="192.168.10.100")
    parse_arp "192.168.10.99    0x1         0x2         bc:24:11:c4:7a:9a     *        br0"
    [ "${mac_to_ip[bc:24:11:c4:7a:9a]}" = "192.168.10.100" ]
}

@test "parse_arp: handles multiple entries across different VLANs" {
    declare -gA mac_to_ip=()
    parse_arp "$(printf '192.168.20.163   0x1         0x2         BC:DF:58:02:0B:EE     *        br52\n192.168.40.101   0x1         0x2         BC:24:11:B6:2D:2E     *        br53')"
    [ "${mac_to_ip[bc:df:58:02:0b:ee]}" = "192.168.20.163" ]
    [ "${mac_to_ip[bc:24:11:b6:2d:2e]}" = "192.168.40.101" ]
}

@test "parse_arp: empty input produces empty map" {
    declare -gA mac_to_ip=()
    parse_arp ""
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

# ── parse_lease_hostnames ─────────────────────────────────────────────────────

@test "parse_lease_hostnames: adds DHCP hostname to mac_to_name for unnamed device" {
    declare -gA mac_to_name=()
    parse_lease_hostnames "86199 04:ed:33:12:a0:48 192.168.10.7 p1g2 01:04:ed:33:12:a0:48"
    [ "${mac_to_name[04:ed:33:12:a0:48]}" = "p1g2" ]
}

@test "parse_lease_hostnames: does not overwrite custom_clientlist name" {
    declare -gA mac_to_name=([04:ed:33:12:a0:48]="My PC")
    parse_lease_hostnames "86199 04:ed:33:12:a0:48 192.168.10.7 p1g2 01:04:ed:33:12:a0:48"
    [ "${mac_to_name[04:ed:33:12:a0:48]}" = "My PC" ]
}

@test "parse_lease_hostnames: skips entries with asterisk hostname" {
    declare -gA mac_to_name=()
    parse_lease_hostnames "86199 aa:bb:cc:dd:ee:ff 192.168.10.7 * 01:aa:bb:cc:dd:ee:ff"
    [ "${#mac_to_name[@]}" -eq 0 ]
}

@test "parse_lease_hostnames: handles multiple leases, sets all unnamed" {
    declare -gA mac_to_name=()
    parse_lease_hostnames "$(printf \
        '86199 04:ed:33:12:a0:48 192.168.10.7 p1g2 *\n86382 14:f6:d8:72:07:5e 192.168.10.32 x1y4 *')"
    [ "${mac_to_name[04:ed:33:12:a0:48]}" = "p1g2" ]
    [ "${mac_to_name[14:f6:d8:72:07:5e]}" = "x1y4" ]
}

@test "parse_lease_hostnames: normalises MAC to lowercase" {
    declare -gA mac_to_name=()
    parse_lease_hostnames "86199 04:ED:33:12:A0:48 192.168.10.7 p1g2 *"
    [ "${mac_to_name[04:ed:33:12:a0:48]}" = "p1g2" ]
}

@test "parse_lease_hostnames: empty input produces empty map" {
    declare -gA mac_to_name=()
    parse_lease_hostnames ""
    [ "${#mac_to_name[@]}" -eq 0 ]
}
