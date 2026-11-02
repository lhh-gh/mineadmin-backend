#!/bin/sh
set -eu

cd /opt/www
umask 0022

# Container-local DI caches must be generated with the actual runtime environment.
mkdir -p runtime/container runtime/logs storage/uploads
for writable_path in runtime/container runtime/logs storage/uploads; do
    if [ ! -w "$writable_path" ]; then
        printf 'Directory is not writable by UID 1000: %s\n' "$writable_path" >&2
        exit 1
    fi
done

if [ "$#" -eq 0 ]; then
    set -- php bin/hyperf.php start
fi

exec "$@"
