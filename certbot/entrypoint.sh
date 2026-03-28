#!/bin/sh
set -e

DOMAIN_DIR="/etc/letsencrypt/live/${DOMAIN}"
RENEWAL_CONF="/etc/letsencrypt/renewal/${DOMAIN}.conf"
RELOAD_FLAG="/var/www/certbot/reload"

echo "[certbot] domain=${DOMAIN} email=${LETSENCRYPT_EMAIL}"
echo "[certbot] live dir contents before:"
ls -la /etc/letsencrypt/live || true

need_issue=false

if [ -f "${DOMAIN_DIR}/fullchain.pem" ]; then
  if [ ! -f "$RENEWAL_CONF" ]; then
    echo "[certbot] renewal config missing, clearing certs"
    need_issue=true
  else
    issuer=$(openssl x509 -noout -issuer -in "${DOMAIN_DIR}/fullchain.pem" || true)
    echo "[certbot] current issuer: ${issuer}"
    echo "$issuer" | grep -qi "Let's Encrypt" || need_issue=true
  fi
else
  need_issue=true
fi

if [ "$need_issue" = true ]; then
  echo "[certbot] clearing existing cert paths"
  rm -rf "/etc/letsencrypt/live/${DOMAIN}" \
    "/etc/letsencrypt/archive/${DOMAIN}" \
    "/etc/letsencrypt/renewal/${DOMAIN}.conf"
  echo "[certbot] requesting new certificate"
  certbot certonly \
    --webroot -w /var/www/certbot \
    --email "$LETSENCRYPT_EMAIL" \
    --agree-tos \
    --no-eff-email \
    --force-renewal \
    --cert-name "$DOMAIN" \
    --non-interactive \
    -d "$DOMAIN"
  touch "$RELOAD_FLAG"
fi

while :; do
  certbot renew --webroot -w /var/www/certbot --quiet && touch "$RELOAD_FLAG"
  sleep 12h
done
