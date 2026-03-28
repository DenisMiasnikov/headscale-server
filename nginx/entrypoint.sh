#!/bin/sh
set -e

CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"
CERT_FILE="${CERT_DIR}/fullchain.pem"
KEY_FILE="${CERT_DIR}/privkey.pem"
RELOAD_FLAG="/var/www/certbot/reload"
HTTP_TEMPLATE="/etc/nginx/templates/http.conf.template"
HTTPS_TEMPLATE="/etc/nginx/templates/https.conf.template"
ACTIVE_CONFIG="/etc/nginx/conf.d/default.conf"

apk add --no-cache openssl >/dev/null 2>&1

render_config() {
  template="$1"
  envsubst '${DOMAIN}' < "$template" > "$ACTIVE_CONFIG"
}

use_https=false
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
  issuer=$(openssl x509 -noout -issuer -in "$CERT_FILE" || true)
  echo "$issuer" | grep -qi "Let's Encrypt" && use_https=true
fi

current_mode="http"
if [ "$use_https" = true ]; then
  current_mode="https"
  render_config "$HTTPS_TEMPLATE"
else
  render_config "$HTTP_TEMPLATE"
fi

nginx -g "daemon off;" &
NGINX_PID=$!

while true; do
  if [ -f "$RELOAD_FLAG" ]; then
    rm -f "$RELOAD_FLAG"
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
      issuer=$(openssl x509 -noout -issuer -in "$CERT_FILE" || true)
      echo "$issuer" | grep -qi "Let's Encrypt" && use_https=true
    fi

    if [ "$use_https" = true ] && [ "$current_mode" != "https" ]; then
      render_config "$HTTPS_TEMPLATE"
      current_mode="https"
      nginx -s reload || true
    fi
  fi

  sleep 5
done

wait "$NGINX_PID"
