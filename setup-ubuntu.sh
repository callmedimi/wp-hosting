#!/bin/bash

# ==========================================
# SERVER SETUP SCRIPT (Ubuntu)
# ==========================================
# Usage: sudo ./setup-ubuntu.sh [role] 

ROLE=${1:-node}
HOSTNAME=$(hostname)

set -e

# Prompt for Admin Email if installing Manager
# This is needed for Let's Encrypt SSL
ADMIN_EMAIL="admin@example.com"
if [ "$ROLE" == "manager" ] || [ "$ROLE" == "node" ]; then
    if grep -q "admin@yourdomain.com" shared/docker-compose.yml; then
        echo -e "\033[1;33m>>> Important: SSL Configuration\033[0m"
        read -p "Enter your Email Address for SSL Certificates: " INPUT_EMAIL
        if [ ! -z "$INPUT_EMAIL" ]; then
            sed -i "s/admin@yourdomain.com/$INPUT_EMAIL/g" shared/docker-compose.yml
        fi
    fi
fi

echo ">>> Updating system..."
# Smart Mirror: Optimize for Iran if needed
COUNTRY=$(curl -s --connect-timeout 2 http://ip-api.com/line?fields=countryCode || echo "UNKNOWN")
if [ "$COUNTRY" == "IR" ]; then
    echo "    [DETECTED: IRAN] Optimizing Ubuntu repositories..."
    sed -i 's/archive.ubuntu.com/mirror.iranserver.com/g' /etc/apt/sources.list
    sed -i 's/security.ubuntu.com/mirror.iranserver.com/g' /etc/apt/sources.list
fi

apt-get update && apt-get upgrade -y
usermod -aG docker $USER || true

echo ">>> Installing Docker & Docker Compose..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    echo "Docker installed."
else
    echo "Docker is already installed."
fi

# Create shared network
echo ">>> Setting up Network..."
docker network create --driver bridge wp_shared_net 2>/dev/null || true

cd shared

echo ">>> Starting Base Infrastructure (Gateway + Agents + Mail Server)..."
# Set hostname for Netdata so it shows up correctly in dashboard
export HOSTNAME=$HOSTNAME
docker compose -f docker-compose.yml up -d

if [ "$ROLE" == "manager" ]; then
    echo ">>> Starting Central Dashboard Stack..."
    docker compose -f docker-compose-central.yml up -d
    
    echo "=================================================="
    echo "✅ MANAGER SERVER READY!"
    echo "   - Dashboard:    https://panel.yourdomain.com"
    echo "   - phpMyAdmin:   https://pma.yourdomain.com"
    echo "   - Mail Server:  https://mail.yourdomain.com"
    echo "=================================================="
else
    echo "=================================================="
    echo "✅ WORKER NODE READY!"
    echo "   - Control Port: 9001"
    echo "=================================================="
fi
