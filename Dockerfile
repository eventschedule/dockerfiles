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

# Composer
ENV COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_MEMORY_LIMIT=-1
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# App source
ARG APP_REF=main
WORKDIR /var/www/html
RUN git clone --depth 1 --branch "${APP_REF}" https://github.com/eventschedule/eventschedule.git /var/www/html

# Fix "dubious ownership"
RUN git config --global --add safe.directory /var/www/html

# Gate any forceScheme('https') behind FORCE_HTTPS
RUN grep -q "forceScheme('https')" app/Providers/AppServiceProvider.php \
  && sed -i "s/URL::forceScheme('https');/if (env('FORCE_HTTPS', false)) { URL::forceScheme('https'); }/" app/Providers/AppServiceProvider.php \
  || true

# Ensure .env exists BEFORE composer (artisan post-scripts expect it)
RUN [ -f .env ] || cp .env.example .env

# Enable public registration in common stacks (no route edits here)
RUN if [ -f config/fortify.php ]; then \
  php -r '$f=\"config/fortify.php\";$s=file_get_contents($f);if(strpos($s,\"Features::registration()\")===false){$s=preg_replace(\"/(\\'features\\'\\s*=>\\s*\\[)/\",\"$1\\n        Laravel\\\\Fortify\\\\Features::registration(),\",$s,1);} file_put_contents($f,$s);'; \
fi
RUN if [ -f config/jetstream.php ]; then \
  php -r '$f=\"config/jetstream.php\";$s=file_get_contents($f);if(strpos($s,\"Features::registration()\")===false){$s=preg_replace(\"/(\\'features\\'\\s*=>\\s*\\[)/\",\"$1\\n        Laravel\\\\Jetstream\\\\Features::registration(),\",$s,1);} file_put_contents($f,$s);'; \
fi
RUN if [ -f routes/web.php ]; then \
  php -r '$f="routes/web.php"; $s=file_get_contents($f); $s=preg_replace("/Auth::routes\\(([^;]*'"'"'register'"'"'\\s*=>\\s*)false/", "Auth::routes($1true", $s, -1, $c); if ($c) file_put_contents($f, $s);'; \
fi

# --- SIGN-UP OVERRIDE: copy file and require it at end of routes/web.php ---
COPY routes/_sign_up_override.php /var/www/html/routes/_sign_up_override.php
RUN printf "\n// Allow public sign up without redirecting to /login\nrequire __DIR__.'/_sign_up_override.php';\n" >> routes/web.php

# PHP deps
RUN composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader

# Frontend build (tolerant)
RUN [ -f package-lock.json ] && npm ci || true
RUN [ -f package.json ] && npm run build || true

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

