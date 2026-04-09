#!/bin/sh
set -e

# Directories and files
DATA_DIR="/var/lib/headscale"
CONFIG_FILE="$DATA_DIR/config.yaml"
NOISE_KEY="$DATA_DIR/noise_private.key"
API_KEY_FILE="$DATA_DIR/apikey.txt"
SOCKET_DIR="/var/run/headscale"
SOCKET_FILE="$SOCKET_DIR/headscale.sock"

mkdir -p "$DATA_DIR"
mkdir -p "$SOCKET_DIR"

# Generate noise key if missing
if [ ! -f "$NOISE_KEY" ]; then
    echo "Generating noise private key..."
    headscale generate-noise-key > "$NOISE_KEY"
    chmod 600 "$NOISE_KEY"
fi

# Generate config file from template
if [ -f "/etc/headscale/config.yaml" ]; then
    echo "Generating config.yaml from template..."
    export NOISE_PRIVATE_KEY_PATH="$NOISE_KEY"
    envsubst < /etc/headscale/config.yaml > "$CONFIG_FILE"
fi

DEFAULT_USER="${DEFAULT_USER:-default}"

# Start headscale in background
headscale serve --config "$CONFIG_FILE" &
HEADSCALE_PID=$!

# Wait for unix socket
for i in $(seq 1 30); do
    if [ -S "$SOCKET_FILE" ]; then
        break
    fi
    sleep 1
done

# Ensure default user exists
if ! headscale --config "$CONFIG_FILE" users list | grep -q "${DEFAULT_USER}"; then
    headscale --config "$CONFIG_FILE" users create "$DEFAULT_USER"
fi

# Ensure at least one API key exists
if ! headscale --config "$CONFIG_FILE" apikey list --output json 2>/dev/null | grep -q '"prefix"'; then
    echo "No API keys found in database. Creating a new one..."
    API_KEY=$(headscale --config "$CONFIG_FILE" apikeys create)
    printf "%s" "$API_KEY" > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"
elif [ ! -f "$API_KEY_FILE" ]; then
    API_KEY=$(headscale --config "$CONFIG_FILE" apikeys create)
    printf "%s" "$API_KEY" > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"
fi

wait "$HEADSCALE_PID"
