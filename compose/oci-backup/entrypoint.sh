#!/usr/bin/env bash
set -eu

: "${OCI_CLI_KEY_CONTENT:?OCI_CLI_KEY_CONTENT is required}"
: "${BACKUP_INTERVAL_CRON:?BACKUP_INTERVAL_CRON is required}"

# Write private key to fixed path. OCI_CLI_KEY_FILE env var in the crontab
# points here so crond-spawned processes can find it without inheriting shell env.
install -m 600 /dev/null /run/oci_key.pem
printf '%s\n' "${OCI_CLI_KEY_CONTENT}" > /run/oci_key.pem

# Write crontab. Set OCI_CLI_KEY_FILE as a crontab variable so crond passes it
# to each invocation of backup.sh.
cat > /etc/crontabs/root << EOF
OCI_CLI_KEY_FILE=/run/oci_key.pem
OCI_CLI_USER=${OCI_CLI_USER}
OCI_CLI_FINGERPRINT=${OCI_CLI_FINGERPRINT}
OCI_CLI_TENANCY=${OCI_CLI_TENANCY}
OCI_CLI_REGION=${OCI_CLI_REGION}
COMPARTMENT_ID=${COMPARTMENT_ID:-${OCI_CLI_TENANCY}}
BOOT_VOLUME_ID=${BOOT_VOLUME_ID}
BACKUP_NAME_PREFIX=${BACKUP_NAME_PREFIX}
${BACKUP_INTERVAL_CRON} /usr/local/bin/backup.sh >> /proc/1/fd/1 2>&1
EOF

echo "Cron schedule: ${BACKUP_INTERVAL_CRON}"
echo "Running initial backup..."
OCI_CLI_KEY_FILE=/run/oci_key.pem /usr/local/bin/backup.sh \
    || echo "Initial backup failed — will retry on next cron interval"

exec crond -f -l 2
