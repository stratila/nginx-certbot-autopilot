#!/bin/sh
set -eu

CONF_DIR="/etc/letsencrypt"

for domain in $(echo "$DOMAINS" | tr ',' ' '); do
  live_dir="${CONF_DIR}/live/${domain}"
  if [ ! -f "${live_dir}/fullchain.pem" ]; then
    echo "[bootstrap] No cert for ${domain} — generating self-signed placeholder."
    mkdir -p "$live_dir"
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
      -keyout "${live_dir}/privkey.pem" \
      -out    "${live_dir}/fullchain.pem" \
      -subj "/CN=${domain}"
  else
    echo "[bootstrap] Cert already present for ${domain} — skipping."
  fi
done

echo "[bootstrap] Done."
