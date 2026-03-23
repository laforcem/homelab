#!/bin/sh

DMZ_BR="br53"
IOT_BR="br52"
GST_BR="br54"

logger -t "firewall-start" "Applying DMZ firewall rules"

# ============================================
# CLEANUP - remove all traces of previous runs
# ============================================

# Remove custom chain hooks
iptables -D FORWARD -i $DMZ_BR -j DMZ_FWD 2>/dev/null
iptables -D FORWARD -i br0 -o $DMZ_BR -j ACCEPT 2>/dev/null
iptables -D INPUT -i $DMZ_BR -j DMZ_INP 2>/dev/null

# Flush and delete custom chains
iptables -F DMZ_FWD 2>/dev/null
iptables -X DMZ_FWD 2>/dev/null
iptables -F DMZ_INP 2>/dev/null
iptables -X DMZ_INP 2>/dev/null

# Purge ALL legacy rules from old script versions (loop until none remain)
while iptables -D FORWARD -i $DMZ_BR -o br0 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; do :; done
while iptables -D FORWARD -i br0 -o $DMZ_BR -j ACCEPT 2>/dev/null; do :; done
while iptables -D FORWARD -i $DMZ_BR -o br0 -m state --state NEW -j DROP 2>/dev/null; do :; done
while iptables -D FORWARD -i $DMZ_BR -o $IOT_BR -j DROP 2>/dev/null; do :; done
while iptables -D FORWARD -i $DMZ_BR -o $GST_BR -j DROP 2>/dev/null; do :; done
while iptables -D FORWARD -i $DMZ_BR -o bt52 -j DROP 2>/dev/null; do :; done
while iptables -D INPUT -i $DMZ_BR -p tcp --dport 22 -j DROP 2>/dev/null; do :; done
while iptables -D INPUT -i $DMZ_BR -p tcp --dport 80 -j DROP 2>/dev/null; do :; done
while iptables -D INPUT -i $DMZ_BR -p tcp --dport 443 -j DROP 2>/dev/null; do :; done
while iptables -D INPUT -i $DMZ_BR -p tcp --dport 8443 -j DROP 2>/dev/null; do :; done
while iptables -D INPUT -i $DMZ_BR -p tcp --dport 8080 -j DROP 2>/dev/null; do :; done
while iptables -D INPUT -i $DMZ_BR -p tcp --dport 23 -j DROP 2>/dev/null; do :; done
while iptables -D INPUT -i $DMZ_BR -j DROP 2>/dev/null; do :; done
while iptables -D INPUT -i $DMZ_BR -p udp --dport 53 -j ACCEPT 2>/dev/null; do :; done
while iptables -D INPUT -i $DMZ_BR -p tcp --dport 53 -j ACCEPT 2>/dev/null; do :; done
while iptables -D INPUT -i $DMZ_BR -p udp --dport 67 -j ACCEPT 2>/dev/null; do :; done

# ============================================
# CREATE CUSTOM CHAINS
# ============================================

iptables -N DMZ_FWD
iptables -N DMZ_INP

# ============================================
# DMZ_FWD - controls what VLAN 40 can forward to
# ============================================

# Allow established/related return traffic to main LAN (for management SSH, etc.)
iptables -A DMZ_FWD -o br0 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Block all new connections to every other VLAN
iptables -A DMZ_FWD -o br0 -j DROP
iptables -A DMZ_FWD -o $IOT_BR -j DROP
iptables -A DMZ_FWD -o $GST_BR -j DROP

# Everything else (internet-bound) continues to normal processing
iptables -A DMZ_FWD -j RETURN

# ============================================
# DMZ_INP - controls what VLAN 40 can send to the router itself
# ============================================

# Drop EVERYTHING
iptables -A DMZ_INP -j DROP

# ============================================
# HOOK INTO MAIN CHAINS - insert at top so we're evaluated FIRST
# ============================================

iptables -I FORWARD -i $DMZ_BR -j DMZ_FWD
iptables -I FORWARD -i br0 -o $DMZ_BR -j ACCEPT
iptables -I INPUT -i $DMZ_BR -j DMZ_INP
