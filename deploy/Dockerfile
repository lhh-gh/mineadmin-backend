# syntax=docker/dockerfile:1
ARG HYPERF_IMAGE=hyperf/hyperf:8.4-alpine-v3.22-swoole-v6.2.2@sha256:72a2ba687ad95f8d5df2a8d17999b530774bc7c5b6098a86822251c062a00f7d

FROM ${HYPERF_IMAGE} AS runtime-base
WORKDIR /opt/www

ENV APP_ENV=prod \
    APP_DEBUG=false \
    SWAGGER_ENABLED=false \
    SWAGGER_AUTO_GENERATE=false \
    MINE_PLUGIN_UPLOAD_ENABLED=false

# Use the PHP image's configured scan directory instead of a version-specific path.
RUN php -r 'file_put_contents(PHP_CONFIG_FILE_SCAN_DIR . "/99-mineadmin-production.ini", "swoole.use_shortname=Off\nopcache.enable=1\nopcache.enable_cli=1\nopcache.memory_consumption=128\nopcache.interned_strings_buffer=16\nopcache.max_accelerated_files=20000\nopcache.validate_timestamps=0\nopcache.save_comments=1\nopcache.jit=off\nexpose_php=Off\nlog_errors=On\nerror_log=/proc/self/fd/2\n");' \
    && addgroup -g 1000 mineadmin \
    && adduser -D -u 1000 -G mineadmin mineadmin

FROM runtime-base AS dependencies
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_CACHE_DIR=/tmp/composer-cache

COPY composer.json composer.lock ./
RUN --mount=type=cache,target=/tmp/composer-cache \
    composer install --no-dev --no-scripts --no-autoloader \
    --prefer-dist --no-interaction --no-progress

COPY . .
# Keep the autoloader extensible for MineAdmin plugins and Hyperf-generated proxies.
RUN composer dump-autoload --no-dev --no-scripts --optimize --no-interaction \
    && composer check-platform-reqs --no-dev

FROM runtime-base AS production
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="MineAdmin backend" \
      org.opencontainers.image.source="https://github.com/lhh-gh/mineadmin-backend" \
      org.opencontainers.image.revision="${VCS_REF}"

COPY --from=dependencies --chown=1000:1000 /opt/www/ /opt/www/
RUN mkdir -p runtime/container runtime/logs storage/uploads \
    && chown -R 1000:1000 runtime storage/uploads \
    && chmod 0755 deploy/entrypoint.sh

ENV HOME=/home/mineadmin
USER 1000:1000
EXPOSE 9501
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=12s --start-period=60s --retries=3 \
    CMD ["php", "/opt/www/deploy/healthcheck.php"]

ENTRYPOINT ["sh", "/opt/www/deploy/entrypoint.sh"]
CMD ["php", "bin/hyperf.php", "start"]
