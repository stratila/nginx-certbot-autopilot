#!/bin/sh
set -eu

CONF_DIR="/etc/letsencrypt"

for domain in $(echo "$DOMAINS" | tr ',' ' '); do
  live_dir="${CONF_DIR}/live/${domain}"

  # certbot-managed cert (renewal config exists) — never touch it.
  if [ -f "${CONF_DIR}/renewal/${domain}.conf" ]; then
    echo "[bootstrap] ${domain} is certbot-managed — skipping."
    continue
  fi

  # Generate when missing, regenerate when the placeholder expires within a
  # day (it can outlive its plan if real issuance keeps failing).
  if [ ! -f "${live_dir}/fullchain.pem" ] || \
     ! openssl x509 -checkend 86400 -noout -in "${live_dir}/fullchain.pem" >/dev/null; then
    echo "[bootstrap] Generating self-signed placeholder for ${domain}."
    mkdir -p "$live_dir"
    openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
      -keyout "${live_dir}/privkey.pem" \
      -out    "${live_dir}/fullchain.pem" \
      -subj "/CN=${domain}"
  else
    echo "[bootstrap] Cert already present for ${domain} — skipping."
  fi
done

echo "[bootstrap] Done."
