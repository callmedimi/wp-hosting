#!/bin/bash
# ==========================================
# MULTI-SITE SSL REGISTRATION TOOL
# ==========================================
# Use this to register manual SSL certs for Traefik.

DOMAIN=$1
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LE_DIR="$BASE_DIR/shared/letsencrypt"
TLS_CONF="$BASE_DIR/shared/traefik-dynamic/tls.yml"

if [ -z "$DOMAIN" ]; then
    echo "Usage: ./manage-ssl.sh <domain.com>"
    exit 1
fi

echo ">>> Registering SSL for $DOMAIN..."

# 1. Create directory structure
mkdir -p "$LE_DIR/$DOMAIN"

# 2. Check for files
if [ ! -f "$LE_DIR/$DOMAIN/fullchain.pem" ]; then
    echo -e "\033[0;33m[NOTICE] Place your certificate files in:\033[0m"
    echo "         $LE_DIR/$DOMAIN/fullchain.pem"
    echo "         $LE_DIR/$DOMAIN/privkey.pem"
    echo "         Then run this script again."
    exit 0
fi

# 3. Initialize tls.yml if missing
if [ ! -f "$TLS_CONF" ]; then
    echo "tls:" > "$TLS_CONF"
    echo "  certificates:" >> "$TLS_CONF"
fi

# 4. Check if already registered
if grep -q "/letsencrypt/$DOMAIN/" "$TLS_CONF"; then
    echo ">>> $DOMAIN is already registered in tls.yml."
    echo ">>> Refreshing certificate reload..."
else
    echo ">>> Adding $DOMAIN to Traefik dynamic config..."
    cat <<EOF >> "$TLS_CONF"
    - certFile: /letsencrypt/$DOMAIN/fullchain.pem
      keyFile: /letsencrypt/$DOMAIN/privkey.pem
EOF
    echo ">>> Added $DOMAIN to Traefik dynamic config."
fi

# 5. Force Traefik to reload the certificates
echo ">>> Touching Traefik dynamic config to trigger reload..."
touch "$TLS_CONF"

# 6. Gracefully reload Traefik container if active
if command -v docker &> /dev/null && docker ps --format '{{.Names}}' | grep -q "^shared_gateway$"; then
    echo ">>> Sending SIGHUP to Traefik (shared_gateway) for immediate certificate hot-reload..."
    docker exec shared_gateway kill -s SIGHUP 1 2>/dev/null || true
    echo ">>> Hot-reload triggered successfully."
else
    echo ">>> Traefik container 'shared_gateway' is not running locally. Reload will happen once it starts."
fi

