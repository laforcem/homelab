# TeamSpeak

Runs an `amd64`-only TeamSpeak 3 image on `mrgutsy`, an ARM64 host, via QEMU user-mode emulation. The host's `qemu-user-binfmt` package registers the `qemu-x86_64` handler (static binary, `F` flag) through `systemd-binfmt` on every boot, before Docker starts, so `restart: unless-stopped` alone brings the container back after a reboot. One-time install on the host:

```
sudo apt-get install --no-install-recommends qemu-user-binfmt
```

Check it with `grep flags /proc/sys/fs/binfmt_misc/qemu-x86_64` (expect `F` among the flags).

Health is probed from outside: `k3s/infra/external-probes/teamspeak.cronjob.yaml` sends a TS3 handshake to `ts3.$DOMAIN:9987/udp` every 5 minutes and pings the "TeamSpeak Health (mrgutsy)" Healthchecks check.
