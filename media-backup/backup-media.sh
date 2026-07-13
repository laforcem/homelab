#!/usr/bin/env bash
set -uo pipefail

LOG_DIR="$HOME/backup-logs"
DATE_TAG=$(date +%Y-%m-%d)
RETENTION_DAYS=30

declare -A SOURCES=(
  [icloud]="/mnt/lab/icloud"
  [immich]="/mnt/lab/immich"
  [movies]="/mnt/lab/movies"
  [music]="/mnt/lab/music"
)

declare -A EXTRA_EXCLUDES=(
  [immich]='--exclude encoded-video/** --exclude thumbs/**'
)

declare -A HC_UUIDS=(
  [icloud]="36ef3811-6cf7-4b2e-835f-b8bb49f21540"
  [immich]="f6e1e429-237c-4736-a55d-fdf08c750d28"
  [movies]="3875b203-362b-445d-bbac-8530a4843f57"
  [music]="6f9bbd04-0ce0-419a-ab29-c65b814e9ed9"
)

mkdir -p "$LOG_DIR"

for name in icloud immich movies music; do
  src="${SOURCES[$name]}"
  dest="dropbox:Homelab/${name}"
  backup_dir="dropbox:Homelab/${name}-deleted/${DATE_TAG}"
  log_file="${LOG_DIR}/rclone-${name}.log"
  uuid="${HC_UUIDS[$name]}"
  excludes="${EXTRA_EXCLUDES[$name]:-}"

  echo "=== ${name} ==="
  # shellcheck disable=SC2086
  if rclone copy "$src" "$dest" \
      --backup-dir "$backup_dir" \
      --transfers=4 --checkers=8 --checksum \
      $excludes \
      --log-file "$log_file"; then
    curl -fsS --retry 3 "https://hc-ping.com/${uuid}" > /dev/null
  else
    curl -fsS --retry 3 "https://hc-ping.com/${uuid}/fail" > /dev/null
  fi
done

RETENTION_CUTOFF=$(date -d "-${RETENTION_DAYS} days" +%Y-%m-%d)
for name in icloud immich movies music; do
  prefix="Homelab/${name}-deleted"
  rclone lsf "dropbox:${prefix}" --dirs-only 2>/dev/null | sed 's#/$##' | while read -r folder; do
    if [[ "$folder" < "$RETENTION_CUTOFF" ]]; then
      echo "Pruning dropbox:${prefix}/${folder} (older than ${RETENTION_DAYS}d)"
      rclone purge "dropbox:${prefix}/${folder}"
    fi
  done
done
