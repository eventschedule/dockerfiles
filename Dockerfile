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

# During image build we do not have a database available. Swap to a
# temporary SQLite configuration so that artisan commands executed as part
# of composer scripts do not attempt to connect to MySQL. The original
# configuration is restored immediately after composer install completes.
RUN cp .env .env.dockerbuild \
 && php -r '$path=".env"; $env=file_get_contents($path); $env=preg_replace("/^DB_CONNECTION=.*/m", "DB_CONNECTION=sqlite", $env, 1, $c1); if(!$c1){$env.="\nDB_CONNECTION=sqlite";} $env=preg_replace("/^DB_DATABASE=.*/m", "DB_DATABASE=database/database.sqlite", $env, 1, $c2); if(!$c2){$env.="\nDB_DATABASE=database/database.sqlite";} file_put_contents($path, $env);' \
 && mkdir -p database \
 && touch database/database.sqlite

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

# Skip settings bootstrap when no DB is available (eg. during image build)
RUN php -r 'eval(base64_decode("JGRpciA9IF9fRElSX18gLiAnL2FwcC9Qcm92aWRlcnMnOwppZiAoIWlzX2RpcigkZGlyKSkgewogICAgZXhpdDsKfQoKJGl0ZXJhdG9yID0gbmV3IFJlY3Vyc2l2ZUl0ZXJhdG9ySXRlcmF0b3IoCiAgICBuZXcgUmVjdXJzaXZlRGlyZWN0b3J5SXRlcmF0b3IoJGRpciwgRmlsZXN5c3RlbUl0ZXJhdG9yOjpTS0lQX0RPVFMpCik7CgokcGF0dGVybiA9ICcvKF5bIFx0XSopaWZccypcKFxzKlNjaGVtYTo6aGFzVGFibGVcKCcnc2V0dGluZ3MnJ1wpXHMqKD88YmxvY2s+XHsoPzpbXnt9XSt8KD8mYmxvY2spKSpcfSkvbSc7Cgpmb3JlYWNoICgkaXRlcmF0b3IgYXMgJGZpbGUpIHsKICAgIGlmICghJGZpbGUtPmlzRmlsZSgpIHx8ICRmaWxlLT5nZXRFeHRlbnNpb24oKSAhPT0gJ3BocCcpIHsKICAgICAgICBjb250aW51ZTsKICAgIH0KCiAgICAkcGF0aCA9ICRmaWxlLT5nZXRQYXRobmFtZSgpOwogICAgJGNvZGUgPSBmaWxlX2dldF9jb250ZW50cygkcGF0aCk7CgogICAgaWYgKHN0cnBvcygkY29kZSwgIlNjaGVtYTo6aGFzVGFibGUoJ3NldHRpbmdzJykiKSA9PT0gZmFsc2UpIHsKICAgICAgICBjb250aW51ZTsKICAgIH0KCiAgICBpZiAoc3RycG9zKCRjb2RlLCAnJHRoaXMtPmFwcC0+cnVubmluZ0luQ29uc29sZSgpJykgIT09IGZhbHNlKSB7CiAgICAgICAgY29udGludWU7CiAgICB9CgogICAgJG5ld0NvZGUgPSBwcmVnX3JlcGxhY2VfY2FsbGJhY2soJHBhdHRlcm4sIGZ1bmN0aW9uIChhcnJheSAkbWF0Y2hlcykgewogICAgICAgICRpbmRlbnQgPSAkbWF0Y2hlc1sxXTsKICAgICAgICAkYmxvY2sgPSAkbWF0Y2hlc1swXTsKCiAgICAgICAgJGluZGVudFBhdHRlcm4gPSAnL14nIC4gcHJlZ19xdW90ZSgkaW5kZW50LCAnLycpIC4gJy9tJzsKICAgICAgICAkYmxvY2tJbmRlbnRlZCA9IHByZWdfcmVwbGFjZSgkaW5kZW50UGF0dGVybiwgJGluZGVudCAuICcgICAgJywgJGJsb2NrKTsKCiAgICAgICAgcmV0dXJuICRpbmRlbnQgLiAiaWYgKCR0aGlzLT5hcHAtPnJ1bm5pbmdJbkNvbnNvbGUoKSkge1xuIgogICAgICAgICAgICAuICRpbmRlbnQgLiAiICAgIHJldHVybjtcbiIKICAgICAgICAgICAgLiAkaW5kZW50IC4gIn1cblxuIgogICAgICAgICAgICAuICRpbmRlbnQgLiAidHJ5IHtcbiIKICAgICAgICAgICAgLiAkYmxvY2tJbmRlbnRlZCAuICJcbiIKICAgICAgICAgICAgLiAkaW5kZW50IC4gIn0gY2F0Y2ggKFxcVGhyb3dhYmxlICRlKSB7XG4iCiAgICAgICAgICAgIC4gJGluZGVudCAuICIgICAgcmV0dXJuO1xuIgogICAgICAgICAgICAuICRpbmRlbnQgLiAifVxuIjsKICAgIH0sICRjb2RlLCAxLCAkcmVwbGFjZW1lbnRzKTsKCiAgICBpZiAoJHJlcGxhY2VtZW50cykgewogICAgICAgIGlmICgkbmV3Q29kZSAhPT0gJycgJiYgc3Vic3RyKCRuZXdDb2RlLCAtMSkgIT09ICJcbiIpIHsKICAgICAgICAgICAgJG5ld0NvZGUgLj0gIlxuIjsKICAgICAgICB9CgogICAgICAgIGZpbGVfcHV0X2NvbnRlbnRzKCRwYXRoLCAkbmV3Q29kZSk7CiAgICB9Cn0K"));'

# PHP deps
RUN composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader \
 && mv .env.dockerbuild .env

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

