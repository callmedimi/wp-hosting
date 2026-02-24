#!/bin/bash

# ==========================================
# GLOBAL OPTIMIZATION SCRIPT
# ==========================================
# Applies resource limits and OLS tuning to all existing sites.

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITES_DIR="/opt/wp-hosting/sites"

echo ">>> Starting Global Optimization on HLWP1..."

for site in "$SITES_DIR"/*; do
    if [ -d "$site" ] && [ -f "$site/docker-compose.yml" ]; then
        SITE_NAME=$(basename "$site")
        echo ">>> Optimizing site: $SITE_NAME"

        # 1. Add Resource Limits to docker-compose.yml if missing
        if ! grep -q "deploy:" "$site/docker-compose.yml"; then
            echo "    Adding resource limits to docker-compose.yml..."
            sed -i 's/restart: unless-stopped/deploy:\n      resources:\n        limits:\n          cpus: '"'"'1.0'"'"'\n          memory: 768M\n    restart: unless-stopped/' "$site/docker-compose.yml"
        fi

        # 2. Apply OLS Tuning inside container
        echo "    Tuning OpenLiteSpeed workers and proxy headers..."
        docker exec "${SITE_NAME}_wp" sed -i 's/PHP_LSAPI_CHILDREN=100/PHP_LSAPI_CHILDREN=200/g' /usr/local/lsws/conf/httpd_config.conf 2>/dev/null
        docker exec "${SITE_NAME}_wp" sed -i 's/maxConns                150/maxConns                200/g' /usr/local/lsws/conf/httpd_config.conf 2>/dev/null
        docker exec "${SITE_NAME}_wp" bash -c "grep -q 'useIpInProxyHeader' /usr/local/lsws/conf/httpd_config.conf || sed -i '/tuning  {/a \  useIpInProxyHeader      1' /usr/local/lsws/conf/httpd_config.conf" 2>/dev/null

        # 3. Handle MariaDB Upgrade
        echo "    Running MariaDB upgrade check..."
        # Extract DB root password from .env
        ROOT_PW=$(grep "DB_ROOT_PASSWORD" "$site/.env" | cut -d'=' -f2)
        if [ -n "$ROOT_PW" ]; then
            docker exec "${SITE_NAME}_db" mariadb-upgrade -u root -p"$ROOT_PW" 2>/dev/null
        fi

        # 4. Restart to apply Compose changes
        echo "    Restarting containers..."
        cd "$site" && docker compose up -d --force-recreate
    fi
done

echo ">>> Global optimization complete!"
