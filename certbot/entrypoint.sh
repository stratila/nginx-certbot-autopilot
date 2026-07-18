#!/usr/bin/env sh
set -eu

CONF_DIR="/etc/letsencrypt"
RELOAD_FLAG="${CONF_DIR}/.reload-needed"
STAGING_FLAG=""
[ "${STAGING:-0}" = "1" ] && STAGING_FLAG="--staging"

# Wait until nginx is actually serving the challenge path before issuing.
# busybox wget exits 1 on any HTTP error, so look for an HTTP status line
# in the output instead (a 404 still means nginx answered).
nginx_up() {
  out=$(wget --spider "http://nginx/.well-known/acme-challenge/" 2>&1) && return 0
  case "$out" in *"HTTP/"*) return 0 ;; esac
  return 1
}
until nginx_up; do
  echo "[certbot] Waiting for nginx to be reachable..."
  sleep 3
done

issue_or_renew() {
  for domain in $(echo "$DOMAINS" | tr ',' ' '); do
    # Real issuance is gated on the renewal config, NOT the live/ files,
    # because a self-signed placeholder also sits in live/.
    if [ ! -f "${CONF_DIR}/renewal/${domain}.conf" ]; then
      echo "[certbot] First issuance for ${domain}."
      # Remove the self-signed placeholder so certbot owns the live/ dir
      rm -rf "${CONF_DIR}/live/${domain}" \
             "${CONF_DIR}/archive/${domain}"
      certbot certonly --webroot -w /var/www/certbot \
        -d "$domain" \
        --register-unsafely-without-email --agree-tos \
        $STAGING_FLAG --non-interactive \
        --deploy-hook "touch ${RELOAD_FLAG}"
    fi
  done

  # Renew everything already managed (no-op if nothing is due)
  certbot renew --webroot -w /var/www/certbot \
    --deploy-hook "touch ${RELOAD_FLAG}"
}

# Run once at startup, then every 12h
while true; do
  issue_or_renew
  sleep 12h
done