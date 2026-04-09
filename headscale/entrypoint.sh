#!/bin/sh
set -e

CONFIG_TEMPLATE="/etc/headscale/config.yaml"
CONFIG_FILE="/etc/headscale/config.yaml"
DATA_DIR="/var/lib/headscale"
API_KEY_FILE="$DATA_DIR/apikey.txt"
SOCKET_DIR="/var/run/headscale"
SOCKET_FILE="$SOCKET_DIR/headscale.sock"

if [ -f "$CONFIG_TEMPLATE" ]; then
  echo "DEBUG: SERVER_URL=$SERVER_URL"
  export SERVER_URL BASE_DOMAIN POSTGRES_USER POSTGRES_PASSWORD DEFAULT_USER
  envsubst < "$CONFIG_TEMPLATE" > "$CONFIG_TEMPLATE"
  echo "=== Generated config start ==="
  cat "$CONFIG_TEMPLATE"
  echo "=== Generated config end ==="
fi

# Ensure necessary directories exist
mkdir -p "$DATA_DIR"
mkdir -p "$SOCKET_DIR"

DEFAULT_USER="${DEFAULT_USER:-default}"

# Start Headscale in background
headscale serve --config "$CONFIG_FILE" &
HEADSCALE_PID=$!

# Wait for unix socket to appear (if using it)
for i in $(seq 1 30); do
  if [ -S "$SOCKET_FILE" ]; then
    break
  fi
  sleep 1
done

# Create default user if it doesn't exist
if ! headscale --config "$CONFIG_FILE" users list | grep -q "${DEFAULT_USER}"; then
  headscale --config "$CONFIG_FILE" users create "$DEFAULT_USER"
fi

# Ensure at least one API key exists and save it to file
if ! headscale --config "$CONFIG_FILE" apikey list --output json 2>/dev/null | grep -q '"prefix"'; then
  echo "No API keys found in database. Creating a new one..."
  API_KEY=$(headscale --config "$CONFIG_FILE" apikeys create)
  printf "%s" "$API_KEY" > "$API_KEY_FILE"
  chmod 600 "$API_KEY_FILE"
elif [ ! -f "$API_KEY_FILE" ]; then
  # API keys exist in DB but file is missing
  API_KEY=$(headscale --config "$CONFIG_FILE" apikeys create)
  printf "%s" "$API_KEY" > "$API_KEY_FILE"
  chmod 600 "$API_KEY_FILE"
fi

# Wait for Headscale process
wait "$HEADSCALE_PID"
