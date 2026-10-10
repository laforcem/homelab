#!/usr/bin/env bash
set -eu

for v in PPLD_CARD_NUMBER PPLD_PIN CALDAV_USERNAME CALDAV_APP_PASSWORD \
         CALDAV_CALENDAR_URL HEALTHCHECK_URL SYNC_CRON; do
    : "${!v:?$v is required}"
done

# crond doesn't inherit the container environment. Write it to a root-only file
# (%q quotes safely) that each cron invocation sources.
install -m 600 /dev/null /run/ppld.env
for v in PPLD_CARD_NUMBER PPLD_PIN CALDAV_USERNAME CALDAV_APP_PASSWORD \
         CALDAV_CALENDAR_URL HEALTHCHECK_URL DRY_RUN TZ; do
    printf 'export %s=%q\n' "$v" "${!v-}" >> /run/ppld.env
done

RUN_CMD='. /run/ppld.env && cd /app && python3 -m ppld_calendar.main'

cat > /etc/crontabs/root << EOF
${SYNC_CRON} bash -c '${RUN_CMD}' >> /proc/1/fd/1 2>&1
EOF

echo "Cron schedule: ${SYNC_CRON}"
echo "Running initial sync..."
bash -c "${RUN_CMD}" || echo "Initial sync failed — will retry on next cron interval"

exec crond -f -l 2
