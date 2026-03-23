#!/bin/sh


DMZ_BR="br53" # VLAN 40
IOT_BR="br52" # VLAN 20
GST_BR="br54" # VLAN 30

logger -t "firewall-start" "Applying DMZ firewall rules"

# ============================================
# CLEANUP — remove custom chians from previous run
# ============================================

# Remove custom chain hooks
iptables -D FORWARD -i $DMZ_BR -j DMZ_FWD 2>/dev/null
iptables -D FORWARD -i br0 -o $DMZ_BR -j ACCEPT 2>/dev/null
iptables -D INPUT -i $DMZ_BR -j DMZ_INP 2>/dev/null

iptables -D FORWARD -i $IOT_BR -j IOT_FWD 2>/dev/null
iptables -D FORWARD -i br0 -o $IOT_BR -j ACCEPT 2>/dev/null

# Flush and delete custom chains
iptables -F DMZ_FWD 2>/dev/null
iptables -X DMZ_FWD 2>/dev/null
iptables -F DMZ_INP 2>/dev/null
iptables -X DMZ_INP 2>/dev/null
iptables -F IOT_FWD 2>/dev/null
iptables -X IOT_FWD 2>/dev/null

# ============================================
# DMZ_FWD (VLAN 40 / br53) — isolation
# ============================================

iptables -N DMZ_FWD

# --- DMZ_FWD: controls what VLAN 40 can forward to ---
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

iptables -N DMZ_INP

# Drop EVERYTHING
iptables -A DMZ_INP -j DROP

# --- Hook DMZ chains into main chains ---
iptables -I FORWARD -i $DMZ_BR -j DMZ_FWD
iptables -I FORWARD -i br0 -o $DMZ_BR -j ACCEPT
iptables -I INPUT -i $DMZ_BR -j DMZ_INP

# ============================================
# IoT (VLAN 20 / br52) — isolation
# ============================================

iptables -N IOT_FWD

# --- IOT_FWD: controls what VLAN 20 can forward to ---
iptables -A IOT_FWD -o br0 -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A IOT_FWD -o br0 -j DROP
iptables -A IOT_FWD -o $DMZ_BR -j DROP
iptables -A IOT_FWD -o $GST_BR -j DROP
iptables -A IOT_FWD -j RETURN

# --- Hook IoT chain into FORWARD ---
iptables -I FORWARD -i $IOT_BR -j IOT_FWD
iptables -I FORWARD -i br0 -o $IOT_BR -j ACCEPT
