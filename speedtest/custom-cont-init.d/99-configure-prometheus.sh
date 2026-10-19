#!/bin/bash
# Configure speedtest-tracker's data integrations from environment variables.
# This runs at container startup via LSIO's custom-cont-init.d hook, before the
# main app services start. We run migrations first so the settings table exists.
#
# Prometheus export is on (scraped by the monitoring stack at /prometheus).
# The InfluxDB v2 export is switched off: it was replaced by Prometheus and its
# container is gone, so leaving it enabled would error after every test.

if [ "${PROMETHEUS_ENABLED}" != "true" ]; then
    echo "[integrations-init] PROMETHEUS_ENABLED not 'true', skipping."
    exit 0
fi

echo "[integrations-init] Running migrations..."
php /app/www/artisan migrate --force --no-ansi -q

echo "[integrations-init] Configuring data integrations..."
php -r "
require '/app/www/vendor/autoload.php';
\$app = require '/app/www/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();
\$settings = app(App\Settings\DataIntegrationSettings::class);
\$settings->prometheus_enabled  = true;
\$settings->influxdb_v2_enabled = false;
\$settings->save();
echo '[integrations-init] Done.' . PHP_EOL;
"
