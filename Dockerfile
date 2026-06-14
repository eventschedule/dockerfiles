# =========================
# Stage: app (php-fpm + code)
# =========================
FROM php:8.3-fpm-alpine AS app

# System deps
RUN apk add --no-cache \
    bash git curl ca-certificates busybox-extras \
    libpng-dev libjpeg-turbo-dev freetype-dev zlib-dev \
    oniguruma-dev libxml2-dev icu-dev \
    libzip-dev zip unzip \
    nodejs npm

# PHP extensions (incl. gd w/ jpeg + freetype)
RUN docker-php-ext-configure gd --with-jpeg --with-freetype \
 && docker-php-ext-install \
    pdo pdo_mysql mbstring exif pcntl bcmath intl opcache zip gd

# Raise PHP upload limits to accommodate large files
RUN { \
      echo 'upload_max_filesize=500M'; \
      echo 'post_max_size=500M'; \
    } > /usr/local/etc/php/conf.d/uploads.ini

# Composer
ENV COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_MEMORY_LIMIT=-1
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# App source
ARG APP_REF=main
WORKDIR /var/www/html
RUN git clone --depth 1 --branch "${APP_REF}" https://github.com/eventschedule/eventschedule.git /var/www/html

# Fix "dubious ownership"
RUN git config --global --add safe.directory /var/www/html

# Ensure .env exists BEFORE composer (artisan post-scripts expect it)
RUN [ -f .env ] || cp .env.example .env

# During image build we do not have a database available. Swap to a
# temporary SQLite configuration so that artisan commands executed as part
# of composer scripts do not attempt to connect to MySQL. The original
# configuration is restored immediately after composer install completes.
RUN cp .env .env.dockerbuild \
 && php -r '$path=".env"; $env=file_get_contents($path); $env=preg_replace("/^DB_CONNECTION=.*/m", "DB_CONNECTION=sqlite", $env, 1, $c1); if(!$c1){$env.="\nDB_CONNECTION=sqlite";} $env=preg_replace("/^DB_DATABASE=.*/m", "DB_DATABASE=database/database.sqlite", $env, 1, $c2); if(!$c2){$env.="\nDB_DATABASE=database/database.sqlite";} file_put_contents($path, $env);' \
 && mkdir -p database \
 && touch database/database.sqlite

# PHP deps
RUN composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader \
 && mv .env.dockerbuild .env

# Frontend build -- must produce the Vite manifest, or @vite throws at runtime and every
# page (including the setup wizard) 500s. public/build is gitignored upstream, so the image
# depends entirely on this build; assert the manifest exists rather than failing silently.
RUN if [ -f package-lock.json ]; then npm ci; fi
RUN if [ -f package.json ]; then npm run build; fi
RUN test -f public/build/manifest.json

# Laravel perms + storage symlink
RUN mkdir -p storage bootstrap/cache \
 && chown -R www-data:www-data storage bootstrap public \
 && php artisan storage:link || true

# Entrypoint
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Default command
CMD ["php-fpm", "-F"]


# =========================
# Stage: web (nginx)
# =========================
FROM nginx:1.27-alpine AS web
COPY --from=app /var/www/html /var/www/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
RUN test -d /var/www/html/public
