# AirConnect AirPlay Bridge for Google Home Devices

**Date:** 2026-05-30
**Status:** Approved design, pending implementation

## Goal

Let an iPhone on VLAN 10 (main LAN) play audio to the Google Home / Nest
Mini speakers on VLAN 20 (IoT), via AirPlay, from any iOS app that supports
AirPlay (Spotify, plus music apps that don't speak Google Cast).

Google Cast support is explicitly **out of scope**. The Google Home devices
are slated for replacement; this is a stopgap that prioritizes "works from
my iPhone" over protocol completeness. Some audio latency is acceptable.
Home Assistant is also out of scope.

## Background / Why Not Cast

Cross-VLAN Google Cast discovery from iOS was investigated and abandoned:

- The router (Asus RT-AX86U, Merlin) runs an avahi mDNS reflector
  (`/jffs/scripts/avahi-daemon.postconf`) bridging `br0` (VLAN 10) and
  `br52` (VLAN 20).
- The reflector correctly relays standard multicast (QM) mDNS queries, but
  **drops iOS-style QU (unicast-response-requested) queries** — proven
  empirically: a QM `_googlecast._tcp` query from VLAN 10 returns all three
  devices; the same query with the QU bit set returns nothing.
- iOS's `mDNSResponder` uses QU queries, so native Cast discovery fails on
  iPhone while it works on Android/Linux (which use QM).
- Fixing this would require a dual-homed mDNS repeater on a host with legs in
  both VLANs — added attack surface and complexity not justified given the
  devices are being replaced.

AirPlay sidesteps discovery entirely: the iPhone discovers AirConnect's
AirPlay targets natively because AirConnect runs on the **same subnet
(VLAN 10)** as the phone.

## Architecture

```
  iPhone (VLAN 10) ──AirPlay 2──> AirConnect @ vm100 (VLAN 10, .100)
                                       │
                                       │ Cast control (TCP 8009)  [allowed: br0->br52]
                                       ▼
                                  Google Home (VLAN 20)
                                       │
                                       │ HTTP audio pull (TCP, pinned port)
                                       ▼
                                  AirConnect @ vm100 (VLAN 10, .100)
                                  [NEW firewall rule: br52->vm100, MAC-scoped]
```

AirConnect (1activegeek/airconnect, already vendored in `airconnect/`) is a
Linux daemon — not an iOS Cast SDK — so it discovers the Google Homes via the
router's existing avahi reflector (QM queries, which work) and re-announces
them as AirPlay 2 speakers bound to vm100's VLAN 10 IP.

When the iPhone plays to one of these AirPlay targets:
1. iPhone streams audio to AirConnect on vm100 (same subnet, native).
2. AirConnect transcodes and tells the Google Home to fetch the stream from
   AirConnect's HTTP server.
3. The Google Home opens a **new** TCP connection from VLAN 20 to vm100 to
   pull the audio. This is the one flow that crosses IoT -> trusted and needs
   a firewall rule.

### Host placement: vm100

AirConnect runs on **vm100** (VLAN 10, 192.168.10.100) as a Docker Compose
service with `network_mode: host` (required for mDNS multicast). This was
proven working in the POC: devices appeared as AirPlay targets and audio
played once the firewall path was open.

vm100 already hosts AdGuard Home, Portainer, and router-sync; AirConnect is a
tiny addition (~40 MB RAM).

## The Firewall Rule (the only real tradeoff)

The audio pull (Google Home -> vm100) is blocked by the existing `IOT_FWD`
chain in `.network/iptables.sh`, which drops all IoT -> trusted new
connections. We add one narrowly-scoped rule.

**Scope by source MAC, not IP.** The Google Homes' IPs are DHCP-assigned and
could change or be inherited by another device later; their MACs are stable
and identify the specific devices. The devices are directly on `br52` (same
L2 segment as the router), so the source MAC is intact at the `IOT_FWD`
(FORWARD) chain. The `mac` match module is confirmed available on the router.

**Pin AirConnect's HTTP port.** AirConnect's `config.xml` currently uses
`<ports>0:0</ports>` (random high ports). We set a fixed port (e.g. 49200)
so the firewall rule can target a single TCP port instead of the whole range.

### Rule to add (in `IOT_FWD`, after the DNS rules, before the DROPs)

```sh
# Allow Google Home/Nest devices to pull AirPlay audio from AirConnect on vm100
GH_MACS="bc:df:58:02:0b:ee e4:f0:42:5e:1a:fd d4:f5:47:b6:64:b3"
for mac in $GH_MACS; do
    iptables -A IOT_FWD -m mac --mac-source $mac \
        -d 192.168.10.100 -p tcp --dport 49200 -j ACCEPT
done
```

Device MACs (from DHCP leases / client list, 2026-05-30):

| Device         | MAC                 | Current IP    |
|----------------|---------------------|---------------|
| Google Nest Mini   | `bc:df:58:02:0b:ee` | 192.168.20.163 |
| Google Home Mini   | `e4:f0:42:5e:1a:fd` | 192.168.20.106 |
| Bedroom speaker (Home Mini) | `d4:f5:47:b6:64:b3` | 192.168.20.142 |

Return traffic is already covered by the existing
`IOT_FWD -o br0 -m state --state ESTABLISHED,RELATED -j ACCEPT` rule.

### Security assessment

- **Exposure:** only the 3 named device MACs, only to vm100, only TCP on the
  single pinned port. Far narrower than the broad `-d 192.168.10.100 -j ACCEPT`
  used during the POC (which has since been removed from the router).
- **Residual risk:** a device spoofing one of these MACs from VLAN 20 could
  reach that one port on vm100. Low impact — the port serves only transcoded
  audio. AdGuard (53), SSH (22), 443, Portainer, and router-sync's SSH key
  remain unreachable from VLAN 20.
- **Lifecycle:** the rule references the Google Homes by MAC and disappears
  cleanly when they are decommissioned.

## Cleanup of POC Artifacts (must do)

Left on the router (malc@192.168.10.1) during investigation; all dormant, but
remove before considering this complete:

- `/jffs/mdns-repeater` (static aarch64 binary, not running)
- `/jffs/_avahi_baseline.conf`
- `/jffs/_avahi_baseline.sha`
- `/jffs/_avahi_baseline.pid`

The router's avahi reflector was restored to its original working state; no
persistent router changes were made beyond these stray files. (The broad POC
firewall rule was already removed.)

## Changes to the Repo

1. **`airconnect/compose.yaml`** — un-deprecate; deploy on vm100. Confirm
   `network_mode: host`, `AIRUPNP_VAR=kill` (Cast-only, no UPnP), and config
   volume at `/home/root/data/airconnect`. Add a `config.xml` pinning
   `<ports>` to the chosen audio port.
2. **`.network/iptables.sh`** — add the MAC-scoped `IOT_FWD` rules above.
3. Remove the stale K8s manifests in `airconnect/manifests/` (superseded by
   Compose) — optional tidy.

## Testing / Validation

1. Deploy AirConnect on vm100; confirm logs show all three Cast devices added
   as renderers.
2. Confirm the AirPlay targets appear in iOS Spotify's device picker.
3. Apply the firewall rule; play audio; confirm it comes through (POC showed
   no audio *without* the rule, audio *with* it).
4. Reboot the router; confirm `firewall-start` re-applies the rule and audio
   still works (the rules must survive reboot — that's the whole point of
   `.network/iptables.sh`).

## Open Items / Known Risks

- **Port pinning behavior:** verify AirConnect honors a fixed `<ports>` value
  for the HTTP audio server (not just the control port). If it still uses a
  range, widen the rule to that specific small range rather than all ports.
- **AirConnect stability:** it was previously disabled for an unknown reason.
  Watch for the issue that caused it to be turned off before; document if it
  recurs.