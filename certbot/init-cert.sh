#!/bin/sh
set -e

DOMAIN="$1"
EMAIL="$2"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "Usage: init-cert.sh <domain> <email>"
  exit 1
fi

if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  echo "Certificate already exists for $DOMAIN"
  exit 0
fi

certbot certonly \
  --webroot -w /var/www/certbot \
  --email "$EMAIL" \
  --agree-tos \
  --no-eff-email \
  -d "$DOMAIN"
