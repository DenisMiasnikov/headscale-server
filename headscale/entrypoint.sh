#!/bin/sh
set -e

CONFIG_TEMPLATE="/etc/headscale/config.template.yaml"
CONFIG_FILE="/etc/headscale/config.yaml"
DATA_DIR="/var/lib/headscale"
API_KEY_FILE="$DATA_DIR/apikey.txt"
SOCKET_DIR="/var/run/headscale"
SOCKET_FILE="$SOCKET_DIR/headscale.sock"

if [ -f "$CONFIG_TEMPLATE" ]; then
  envsubst < "$CONFIG_TEMPLATE" > "$CONFIG_FILE"
fi

mkdir -p "$DATA_DIR"
mkdir -p "$SOCKET_DIR"

DEFAULT_USER="${DEFAULT_USER:-default}"

headscale serve --config "$CONFIG_FILE" &
HEADSCALE_PID=$!

for i in $(seq 1 30); do
  if [ -S "$SOCKET_FILE" ]; then
    break
  fi
  sleep 1
done

if ! headscale --config "$CONFIG_FILE" users list | grep -q "${DEFAULT_USER}"; then
  headscale --config "$CONFIG_FILE" users create "$DEFAULT_USER"
fi

# Ensure at least one API key exists and is saved to the file
# Check if any API keys exist in the database by looking for "prefix" in JSON output
if ! headscale --config "$CONFIG_FILE" apikey list --output json 2>/dev/null | grep -q '"prefix"'; then
  echo "No API keys found in database. Creating a new one..."
  API_KEY=$(headscale --config "$CONFIG_FILE" apikeys create)
  printf "%s" "$API_KEY" > "$API_KEY_FILE"
  chmod 600 "$API_KEY_FILE"
elif [ ! -f "$API_KEY_FILE" ]; then
  # API keys exist in DB but no file (shouldn't happen), create a new one anyway
  API_KEY=$(headscale --config "$CONFIG_FILE" apikeys create)
  printf "%s" "$API_KEY" > "$API_KEY_FILE"
  chmod 600 "$API_KEY_FILE"
fi

wait "$HEADSCALE_PID"
