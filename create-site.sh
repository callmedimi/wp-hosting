#!/bin/bash

# ==========================================
# CREATE SITE SCRIPT (Global-Ready)
# ==========================================
# Supports 'Primary Node' and 'Replica Mode' from start.
# Automatically detects location and uses mirrors if in Iran.

SITE_NAME=$1
DOMAIN_NAME=$2
DB_NAME=$3
DB_USER=$3
SFTP_USER=$3
SFTP_PASS=$4

# Paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_DIR="$BASE_DIR/sites/$SITE_NAME"

# Default Node ID (current hostname)
CURRENT_NODE=$(hostname) 
# Default Replica Mode (active)
REPLICA_MODE="active"

if [ -z "$SITE_NAME" ] || [ -z "$DOMAIN_NAME" ]; then
    echo "Usage: ./create-site.sh <site_name> <domain> <db/user> <password>"
    exit 1
fi

echo ">>> Creating site $SITE_NAME ($DOMAIN_NAME)..."

# 1. Location Detection (Smart Mirror)
echo ">>> Checking location for optimal mirrors..."
if [ "$FORCE_IR" == "true" ]; then
    COUNTRY="IR"
else
    # Try multiple services in case one is blocked
    COUNTRY=$(curl -s --connect-timeout 3 http://ip-api.com/line?fields=countryCode || \
              curl -s --connect-timeout 3 https://ipapi.co/country/ || \
              echo "UNKNOWN")
fi

BUILD_ARGS=""
if [ "$COUNTRY" == "IR" ] || [ "$COUNTRY" == "Iran" ] || [ "$COUNTRY" == "UNKNOWN" ]; then
    echo "    [DETECTED: IRAN/RESTRICTED] Setting up Iranian mirrors for build..."
    BUILD_ARGS="--build-arg MIRROR=mirror.arvancloud.ir"
else
    echo "    [DETECTED: GLOBAL] Using official repositories."
fi

# 2. Create directory and copy template
mkdir -p "$SITE_DIR"
cp -r "$BASE_DIR/site-template/"* "$SITE_DIR/" 2>/dev/null || true
cp "$BASE_DIR/site-template/Dockerfile" "$SITE_DIR/" 2>/dev/null || true

# 3. Generate Random Passwords
DB_PASS=$(openssl rand -base64 12)
WP_ADMIN_PASS=$(openssl rand -base64 12)
ROOT_DB_PASS=$(openssl rand -base64 16)

# Find next available port starting at 8081
APP_PORT=8081
SITES_DIR="$BASE_DIR/sites"
if [ -d "$SITES_DIR" ]; then
    while grep -r "APP_PORT=$APP_PORT" "$SITES_DIR" >/dev/null 2>&1; do
        APP_PORT=$((APP_PORT + 1))
    done
fi
echo "    Assigned Port: $APP_PORT"

# 4. Create .env file with Metadata
cat <<EOF > "$SITE_DIR/.env"
# Site Configuration
PROJECT_NAME=$SITE_NAME
APP_PORT=$APP_PORT
DOMAIN_NAME=$DOMAIN_NAME

# Replication Metadata
PRIMARY_NODE=$CURRENT_NODE
REPLICA_MODE=$REPLICA_MODE

# Database Credentials
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS
DB_ROOT_PASSWORD=$ROOT_DB_PASS

# System User (Isolation)
SYS_USER=$SFTP_USER
SYS_UID=1001 
SYS_GID=1001
SYS_PASSWORD=$SFTP_PASS

# WordPress Salts (Security)
AUTH_KEY='$(openssl rand -base64 48)'
SECURE_AUTH_KEY='$(openssl rand -base64 48)'
LOGGED_IN_KEY='$(openssl rand -base64 48)'
NONCE_KEY='$(openssl rand -base64 48)'
EOF

# 5. Create System User (for SFTP/FTP) & Set Permissions
echo ">>> Configuring system user $SFTP_USER..."
if ! id "$SFTP_USER" &>/dev/null; then
    useradd -d "$SITE_DIR" -M -s /usr/sbin/nologin "$SFTP_USER"
    echo "    Created user $SFTP_USER."
else
    usermod -d "$SITE_DIR" -s /usr/sbin/nologin "$SFTP_USER"
    echo "    Updated existing user $SFTP_USER."
fi

# Set password
echo "$SFTP_USER:$SFTP_PASS" | chpasswd

# Set Permissions (Host side)
chown -R "$SFTP_USER:$SFTP_USER" "$SITE_DIR"
chmod -R 775 "$SITE_DIR"

# 6. Register with Dashboard
HOMEPAGE_FILE="$BASE_DIR/shared/homepage/services.yaml"
if [ -f "$HOMEPAGE_FILE" ]; then
    if ! grep -q "$DOMAIN_NAME" "$HOMEPAGE_FILE"; then
        echo ">>> Registering with Dashboard..."
        if ! grep -q -- "- Sites:" "$HOMEPAGE_FILE"; then
            echo -e "\n- Sites:" >> "$HOMEPAGE_FILE"
        fi
        cat <<EOF >> "$HOMEPAGE_FILE"
    - $SITE_NAME:
        icon: wordpress.png
        href: "https://$DOMAIN_NAME"
        description: "$DOMAIN_NAME (Local)"
        widget:
            type: wordpress
            url: http://${SITE_NAME}_wp
EOF
    fi
fi

# 7. Launch Site
echo ">>> Launching containers for $SITE_NAME..."

# Detect Proxy Support (if using SSH Tunnel/VPN)
PROXY_ARGS=""
if [ -n "$all_proxy" ] || [ -n "$http_proxy" ]; then
    # Find Docker Host Gateway (to allow container to talk to 127.0.0.1 tunnel on host)
    HOST_GATEWAY=$(docker network inspect bridge --format='{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || echo "172.17.0.1")
    
    # Function to rewrite localhost to gateway
    fix_proxy() { echo "$1" | sed "s/127.0.0.1/$HOST_GATEWAY/g; s/localhost/$HOST_GATEWAY/g"; }
    
    [ -n "$http_proxy" ]  && PROXY_ARGS="$PROXY_ARGS --build-arg http_proxy=$(fix_proxy "$http_proxy")"
    [ -n "$https_proxy" ] && PROXY_ARGS="$PROXY_ARGS --build-arg https_proxy=$(fix_proxy "$https_proxy")"
    [ -n "$all_proxy" ]   && PROXY_ARGS="$PROXY_ARGS --build-arg all_proxy=$(fix_proxy "$all_proxy")"
fi

cd "$SITE_DIR"
if [ ! -z "$BUILD_ARGS" ] || [ ! -z "$PROXY_ARGS" ]; then
    docker compose build $BUILD_ARGS $PROXY_ARGS
fi
docker compose up -d

echo ""
echo -e "\033[0;32m✅ SUCCESS: Site Created & Started!\033[0m"
echo "    Site Name:    $SITE_NAME"
echo "    Domain:       $DOMAIN_NAME"
echo "    Primary Node: $CURRENT_NODE"
echo "    Replica Mode: $REPLICA_MODE"
echo ""
echo "Manage this site via: ./manage.sh -> Option 5"
