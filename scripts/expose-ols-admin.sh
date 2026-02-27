#!/bin/bash

# ==========================================
# OPENLITESPEED ADMIN RETROFITTER
# ==========================================
# Injects dynamic OLS WebAdmin access (Port 7080) to existing sites.

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}    OPENLITESPEED ADMIN PORT TOOL         ${NC}"
echo -e "${BLUE}==========================================${NC}"

# Get list of sites
SITES_DIR="$BASE_DIR/sites"
if [ ! -d "$SITES_DIR" ]; then
    echo -e "${RED}[ERROR] No sites directory found at $SITES_DIR${NC}"
    exit 1
fi

if [ -n "$1" ]; then
    # Non-interactive mode
    SITE_NAME="$1"
    if [ ! -d "$SITES_DIR/$SITE_NAME" ]; then
        echo -e "${RED}[ERROR] Site $SITE_NAME does not exist.${NC}"
        exit 1
    fi
else
    # Interactive mode
    sites=( $(ls "$SITES_DIR") )
    if [ ${#sites[@]} -eq 0 ]; then
        echo "No sites available."
        exit 1
    fi

    echo "Available Sites:"
    for i in "${!sites[@]}"; do
        echo "  $((i+1)). ${sites[$i]}"
    done

    read -p "Select site to expose Admin Panel (number): " site_index
    if ! [[ "$site_index" =~ ^[0-9]+$ ]] || [ "$site_index" -lt 1 ] || [ "$site_index" -gt "${#sites[@]}" ]; then
        echo -e "${RED}Invalid selection.${NC}"
        exit 1
    fi

    SITE_NAME="${sites[$((site_index-1))]}"
fi
SITE_DIR="$SITES_DIR/$SITE_NAME"

# Check if already exposed
if grep -q "OLS_ADMIN_PORT" "$SITE_DIR/.env"; then
    PORT=$(grep "OLS_ADMIN_PORT=" "$SITE_DIR/.env" | cut -d'=' -f2)
    PASS=$(grep "OLS_ADMIN_PASS=" "$SITE_DIR/.env" | cut -d'=' -f2)
    echo -e "${GREEN}>>> OLS Admin is already exposed for $SITE_NAME!${NC}"
    echo "URL     : http://<server-ip>:$PORT"
    echo "User    : admin"
    echo "Pass    : $PASS"
    exit 0
fi

echo ">>> Generating OLS Credentials for $SITE_NAME..."
OLS_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)

# Find next available port
OLS_ADMIN_PORT=7080
while grep -qr "OLS_ADMIN_PORT=$OLS_ADMIN_PORT" "$SITES_DIR" 2>/dev/null; do
    OLS_ADMIN_PORT=$((OLS_ADMIN_PORT + 1))
done

echo "    Assigned Port: $OLS_ADMIN_PORT"

# Append to .env
echo "" >> "$SITE_DIR/.env"
echo "# OpenLiteSpeed WebAdmin" >> "$SITE_DIR/.env"
echo "OLS_ADMIN_PORT=$OLS_ADMIN_PORT" >> "$SITE_DIR/.env"
echo "OLS_ADMIN_PASS=$OLS_PASS" >> "$SITE_DIR/.env"

# Inject into docker-compose.yml if not present
if ! grep -q "OLS_ADMIN_PORT" "$SITE_DIR/docker-compose.yml"; then
    echo "    Updating docker-compose.yml ports map..."
    # We use sed to insert the port mapping and the environment variable
    sed -i '/- "${APP_PORT}:80"/a \      - "${OLS_ADMIN_PORT}:7080"' "$SITE_DIR/docker-compose.yml"
    sed -i '/WORDPRESS_DB_NAME: ${DB_NAME}/a \      OLS_ADMIN_PASS: ${OLS_ADMIN_PASS:-}' "$SITE_DIR/docker-compose.yml"
fi

echo ">>> Applying changes (recreating container)..."
cd "$SITE_DIR"
docker compose up -d --force-recreate

# Wait for container to process wp-init.sh (which sets the password)
echo "    Waiting for OpenLiteSpeed to restart with new password..."
sleep 5

echo -e "${GREEN}✅ OLS Admin exposed successfully!${NC}"
echo -e "${BLUE}------------------------------------------${NC}"
echo "URL     : http://<server-ip>:$OLS_ADMIN_PORT"
echo "User    : admin"
echo "Pass    : $OLS_PASS"
echo -e "${BLUE}------------------------------------------${NC}"
echo ""
