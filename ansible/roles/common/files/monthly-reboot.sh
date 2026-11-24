#!/bin/sh
# Reboot if an update asked for it, or if the host has been up 90+ days.
# The uptime limit makes sure k3s restarts within its 120-day certificate
# renewal window even in a month with no kernel update.
max_uptime=$((90 * 24 * 3600))
uptime_s=$(cut -d. -f1 /proc/uptime)
if [ -f /var/run/reboot-required ] || [ "$uptime_s" -ge "$max_uptime" ]; then
  logger -t monthly-reboot "rebooting (reboot-required or uptime ${uptime_s}s)"
  systemctl reboot
fi
