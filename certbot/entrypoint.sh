#!/usr/bin/env sh
set -eu

CONF_DIR="/etc/letsencrypt"
RELOAD_FLAG="${CONF_DIR}/.reload-needed"
STAGING_FLAG=""
[ "${STAGING:-0}" = "1" ] && STAGING_FLAG="--staging"

# sh runs as PID 1 here, and PID 1 ignores signals it has no handler for —
# without this trap `podman stop` would hang for the kill timeout and end in
# SIGKILL. A foreground sleep would also defer the trap until it finishes, so
# snooze backgrounds the sleep and waits on it; the signal interrupts the wait.
trap 'echo "[certbot] Stop signal received — exiting."; kill "${sleep_pid:-}" 2>/dev/null; exit 0' TERM INT

snooze() {
  sleep "$1" &
  sleep_pid=$!
  wait "$sleep_pid" || true
  sleep_pid=""
}

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
  snooze 3
done

issue() {
  domain=$1; shift
  certbot certonly --webroot -w /var/www/certbot \
    -d "$domain" \
    --register-unsafely-without-email --agree-tos \
    $STAGING_FLAG --non-interactive \
    --deploy-hook "touch ${RELOAD_FLAG}" \
    "$@"
}

# certbot must own live/<domain>, so move the self-signed placeholder aside
# first — and restore it on failure, otherwise a failed issuance would leave
# nginx pointing at cert files that no longer exist.
first_issue() {
  domain=$1
  backup="${CONF_DIR}/.placeholder/${domain}"
  rm -rf "$backup" "${CONF_DIR}/archive/${domain}"
  mkdir -p "${CONF_DIR}/.placeholder"
  [ ! -d "${CONF_DIR}/live/${domain}" ] || mv "${CONF_DIR}/live/${domain}" "$backup"
  if issue "$domain"; then
    rm -rf "$backup"
  else
    echo "[certbot] Issuance failed for ${domain} — restoring placeholder; will retry."
    if [ ! -d "${CONF_DIR}/live/${domain}" ] && [ -d "$backup" ]; then
      mv "$backup" "${CONF_DIR}/live/${domain}"
    fi
  fi
}

# The ACME server URL is pinned into renewal/<domain>.conf at first issuance,
# so flipping STAGING later must force a reissue — `certbot renew` alone would
# keep renewing against the stored (now wrong) server forever.
env_mismatch() {
  conf="${CONF_DIR}/renewal/${1}.conf"
  if [ -n "$STAGING_FLAG" ]; then
    ! grep -q "acme-staging" "$conf"
  else
    grep -q "acme-staging" "$conf"
  fi
}

issue_or_renew() {
  for domain in $(echo "$DOMAINS" | tr ',' ' '); do
    # Real issuance is gated on the renewal config, NOT the live/ files,
    # because a self-signed placeholder also sits in live/.
    if [ ! -f "${CONF_DIR}/renewal/${domain}.conf" ]; then
      echo "[certbot] First issuance for ${domain}."
      first_issue "$domain"
    elif env_mismatch "$domain"; then
      echo "[certbot] ACME environment changed for ${domain} — forcing reissue."
      issue "$domain" --force-renewal \
        || echo "[certbot] Reissue failed for ${domain} — will retry."
    fi
  done

  # Renew everything already managed (no-op if nothing is due). Guarded so a
  # transient failure retries on the 12h cadence instead of killing the loop.
  certbot renew --webroot -w /var/www/certbot \
    --deploy-hook "touch ${RELOAD_FLAG}" \
    || echo "[certbot] Renew failed — will retry in 12h."
}

# Run once at startup, then every 12h
while true; do
  issue_or_renew
  snooze 12h
done
