#!/bin/bash
# Configure speedtest-tracker's InfluxDB v2 integration from environment variables.
# This runs at container startup via LSIO's custom-cont-init.d hook, before the
# main app services start. We run migrations first so the settings table exists.

if [ -z "${INFLUXDB_URL}" ]; then
    echo "[influxdb-init] INFLUXDB_URL not set, skipping InfluxDB configuration."
    exit 0
fi

echo "[influxdb-init] Running migrations..."
php /app/www/artisan migrate --force --no-ansi -q

echo "[influxdb-init] Configuring InfluxDB v2 settings from environment..."
php -r "
require '/app/www/vendor/autoload.php';
\$app = require '/app/www/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();
\$settings = app(App\Settings\DataIntegrationSettings::class);
\$settings->influxdb_v2_enabled = true;
\$settings->influxdb_v2_url     = getenv('INFLUXDB_URL');
\$settings->influxdb_v2_bucket  = getenv('INFLUXDB_BUCKET') ?: 'speedtest';
\$settings->influxdb_v2_org     = getenv('INFLUXDB_ORG')    ?: null;
\$settings->influxdb_v2_token   = getenv('INFLUXDB_TOKEN')  ?: null;
\$settings->influxdb_v2_verify_ssl = false;
\$settings->save();
echo '[influxdb-init] Done.' . PHP_EOL;
"
