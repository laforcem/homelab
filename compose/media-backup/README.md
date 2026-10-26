# media-backup

Backs up the five `lab` drive libraries (icloud, immich, movies, music, audiobooks) to Dropbox nightly at 01:00 America/Denver.

Runs as a CronJob on chimaera: `k3s/apps/media-backup/`. Replaces the old script on vm101's crontab, which in turn replaced the separate icloud/immich cron jobs (see homelab#41). All five sources run sequentially in one job, which structurally prevents the Dropbox API rate-limit collision that broke the old setup.

Each source has its own Healthchecks check ("<Name> Backup (chimaera)"), so a failure in one is visible independently of the others.

`--backup-dir` keeps deleted/changed files in a dated folder per source (`dropbox:Homelab/<source>-deleted/<date>`) instead of removing them outright; the job prunes those folders after 30 days. It uses `rclone copy`, never `sync`.

Run it by hand: `kubectl -n media-backup create job --from=cronjob/media-backup mb-manual-1`.
