# media-backup

Backs up all four vm101 `/mnt/lab` sources (icloud, immich, movies, music) to Dropbox nightly.

Replaces the old separate icloud/immich cron jobs (see homelab#41) — running
all four sources sequentially in one script structurally prevents the
Dropbox API rate-limit collision that broke the old setup.

Deployed on vm101 via `~/homelab` (manual `git pull`, no CI yet). Cron entry:
`0 1 * * * /home/malc/homelab/media-backup/backup-media.sh`

Each source gets its own healthchecks.io ping (see script for UUIDs) so a
failure in one source is visible independently of the others.

`--backup-dir` keeps deleted/changed files in a dated folder per source
(`dropbox:Homelab/<source>-deleted/<date>`) instead of removing them outright;
the script prunes those folders after 30 days.
