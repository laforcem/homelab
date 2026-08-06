# TeamSpeak

Runs an `amd64`-only TeamSpeak 3 image on `mrgutsy`, an ARM64 host, via QEMU user-mode emulation (`tonistiigi/binfmt`). The `binfmt` service in `compose.yaml` registers the emulation handler; `teamspeak` depends on it completing first.

That registration lives in the kernel's `binfmt_misc`, not on disk — it does not survive a reboot on its own. `teamspeak-boot.service` re-runs `docker compose up -d` on every boot so the registration and the container both come back automatically. One-time install on the host:

```
sudo cp teamspeak-boot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now teamspeak-boot.service
```
