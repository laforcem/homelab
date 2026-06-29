#!/usr/bin/env bash
set -euo pipefail

BACKUP_NAME_PREFIX="${BACKUP_NAME_PREFIX:?BACKUP_NAME_PREFIX is required}"
BOOT_VOLUME_ID="${BOOT_VOLUME_ID:?BOOT_VOLUME_ID is required}"
export OCI_CLI_KEY_FILE="${OCI_CLI_KEY_FILE:-/run/oci_key.pem}"

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
NEW_NAME="${BACKUP_NAME_PREFIX}-${TIMESTAMP}"

echo "Checking for existing backup with prefix '${BACKUP_NAME_PREFIX}'..."
LIST_OUTPUT=$(oci bv boot-volume-backup list \
    --boot-volume-id "${BOOT_VOLUME_ID}" \
    --lifecycle-state AVAILABLE \
    --all \
    --output json \
    2>/dev/null) || LIST_OUTPUT='{"data":[]}'

EXISTING_ID=$(echo "$LIST_OUTPUT" \
    | jq -r --arg prefix "$BACKUP_NAME_PREFIX" \
        '.data[] | select(."display-name" | startswith($prefix)) | .id' \
    | head -1)

if [ -n "$EXISTING_ID" ]; then
    echo "Found existing backup: ${EXISTING_ID}"
else
    echo "No existing backup found — treating as first run"
fi

echo "Creating backup: ${NEW_NAME}"
CREATE_OUTPUT=$(oci bv boot-volume-backup create \
    --boot-volume-id "${BOOT_VOLUME_ID}" \
    --type FULL \
    --display-name "${NEW_NAME}" \
    --wait-for-state AVAILABLE \
    --output json \
    2>/dev/null) || CREATE_OUTPUT='{"data":{"id":""}}'

NEW_ID=$(echo "$CREATE_OUTPUT" | jq -r '.data.id // empty')

if [ -z "$NEW_ID" ]; then
    echo "ERROR: Backup creation failed or returned empty ID" >&2
    exit 1
fi

echo "New backup created: ${NEW_ID}"

if [ -n "$EXISTING_ID" ]; then
    echo "Deleting old backup: ${EXISTING_ID}"
    oci bv boot-volume-backup delete --force \
        --boot-volume-backup-id "${EXISTING_ID}" \
        --wait-for-state TERMINATED \
        2>/dev/null
    echo "Old backup deleted"
fi

echo "Backup complete"
