#!/bin/sh
# Runs from /docker-entrypoint.d/ before the stock entrypoint launches nginx.
# certbot touches the reload flag after issuing/renewing a cert; this watcher
# reloads nginx so the new cert is picked up without a container restart.
set -eu

RELOAD_FLAG="/etc/letsencrypt/.reload-needed"

# Background the loop and return immediately — the stock entrypoint runs each
# /docker-entrypoint.d/*.sh synchronously, so blocking here would stop nginx
# from ever starting.
(
  while true; do
    if [ -f "$RELOAD_FLAG" ]; then
      echo "[nginx] Reload flag detected — reloading."
      nginx -s reload && rm -f "$RELOAD_FLAG"
    fi
    sleep 30
  done
) &
