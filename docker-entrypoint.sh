#!/usr/bin/env sh
set -e

cd /var/www/html

# Ensure .env exists
[ -f .env ] || cp .env.example .env

# storage/ is a persisted named volume mounted over the image's directory, and this
# entrypoint runs as root. Create the runtime directories and hand them to the php-fpm
# user (www-data) so the workers can write logs/cache/sessions. Without this, files
# created here as root cause "permission denied" on storage/logs/laravel.log.
mkdir -p \
  storage/framework/cache \
  storage/framework/sessions \
  storage/framework/views \
  storage/logs \
  bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache

# Wait for DB (best-effort)
if [ -n "$DB_HOST" ]; then
  echo "Waiting for DB at ${DB_HOST}:${DB_PORT:-3306}..."
  i=0
  while : ; do
    if php -r "try { new PDO('mysql:host=${DB_HOST};port=${DB_PORT:-3306}', '${DB_USERNAME:-eventschedule}', '${DB_PASSWORD:-change_me}'); } catch (Exception \$e) { exit(1); }"; then
      break
    fi
    i=$((i+1))
    if [ "$i" -ge 60 ]; then
      echo "DB wait timeout after 60s, continuing..."
      break
    fi
    sleep 1
  done
fi

# Ensure APP_KEY. Skip when one is supplied via the environment (e.g. a fixed key in
# .env passed through env_file) so the app and scheduler stay consistent and survive
# container restarts. Only auto-generate an ephemeral key when none is configured.
if [ -z "${APP_KEY:-}" ] && { ! grep -q "^APP_KEY=base64:" .env || grep -q "^APP_KEY=[[:space:]]*$" .env; }; then
  php artisan key:generate --force || true
fi

# Idempotent migrations
php artisan migrate --force

# Re-assert ownership in case artisan (run as root) created files in the storage volume.
chown -R www-data:www-data storage bootstrap/cache

exec "$@"
