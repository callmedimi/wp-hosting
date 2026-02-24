#!/bin/bash

# ==========================================
# REFRESH SITES SCRIPT
# ==========================================
# Updates all existing sites to the latest template standards:
# 1. Updates Dockerfile (Memcached, Curl-based downloads)
# 2. Updates docker-compose.yml (Adds Memcached service)
# 3. Rebuilds and restarts the sites.

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_DIR="$BASE_DIR/site-template"
SITES_DIR="$BASE_DIR/sites"

echo ">>> Starting Site Refresh..."

if [ ! -d "$SITES_DIR" ] || [ -z "$(ls -A "$SITES_DIR")" ]; then
    echo "    [INFO] No sites found in $SITES_DIR to refresh."
    exit 0
fi

for SITE_PATH in "$SITES_DIR"/*; do
    if [ -d "$SITE_PATH" ] && [ -f "$SITE_PATH/docker-compose.yml" ]; then
        SITE_NAME=$(basename "$SITE_PATH")
        echo ">>> Refreshing Site: $SITE_NAME"

        # 1. Update Dockerfile and entrypoint
        echo "    Updating Dockerfile..."
        cp "$TEMPLATE_DIR/Dockerfile" "$SITE_PATH/Dockerfile"
        cp "$TEMPLATE_DIR/wp-init.sh" "$SITE_PATH/wp-init.sh"
        sed -i 's/\r$//' "$SITE_PATH/wp-init.sh" 2>/dev/null

        # 2. Update docker-compose.yml (Resources, Entrypoint & Memcached)
        echo "    Optimizing docker-compose.yml..."
        
        if ! grep -q "deploy:" "$SITE_PATH/docker-compose.yml"; then
            echo "    Injecting Memory limits..."
            sed -i 's/restart: unless-stopped/deploy:\n      resources:\n        limits:\n          memory: 1024M\n    restart: unless-stopped/' "$SITE_PATH/docker-compose.yml"
        else
            # Strip CPU limits if they exist (they artificially bottleneck PageSpeed)
            sed -i '/cpus:.*/d' "$SITE_PATH/docker-compose.yml"
            sed -i 's/memory: 768M/memory: 1024M/g' "$SITE_PATH/docker-compose.yml"
        fi

        # Remove any old entrypoint/command lines if they exist to prevent duplicates
        if ! grep -q "entrypoint: \[\"/bin/bash\", \"/usr/local/bin/wp-init.sh\"\]" "$SITE_PATH/docker-compose.yml"; then
            sed -i '/    entrypoint:/d' "$SITE_PATH/docker-compose.yml"
            sed -i '/    command:/d' "$SITE_PATH/docker-compose.yml"
            
            # Insert after container_name which is a stable anchor
            sed -i '/container_name: .*_wp/a \    entrypoint: ["/bin/bash", "/usr/local/bin/wp-init.sh"]\n    command: ["apache2-foreground"]' "$SITE_PATH/docker-compose.yml"
        fi

        # Force the use of standard Dockerfile instead of Dockerfile.ols
        sed -i '/dockerfile:.*Dockerfile\.ols/d' "$SITE_PATH/docker-compose.yml"

        # 2. Update docker-compose.yml (Remove Memcached if exists)
        echo "    Removing Memcached service from docker-compose.yml..."
        sed -i '/memcached:/,/^  [a-z]/ { /^  memcached:/d; /^    /d; }' "$SITE_PATH/docker-compose.yml"
        sed -i '/- memcached/d' "$SITE_PATH/docker-compose.yml"


        # 3. Apply OLS Tuning inside container
        echo "    Tuning OpenLiteSpeed workers and proxy headers..."
        docker exec "${SITE_NAME}_wp" sed -i 's/PHP_LSAPI_CHILDREN=.*/PHP_LSAPI_CHILDREN=200/g' /usr/local/lsws/conf/httpd_config.conf 2>/dev/null
        docker exec "${SITE_NAME}_wp" sed -i 's/maxConns                150/maxConns                200/g' /usr/local/lsws/conf/httpd_config.conf 2>/dev/null
        docker exec "${SITE_NAME}_wp" bash -c "grep -q 'useIpInProxyHeader' /usr/local/lsws/conf/httpd_config.conf || sed -i '/tuning  {/a \  useIpInProxyHeader      1' /usr/local/lsws/conf/httpd_config.conf" 2>/dev/null

        # 4. Handle MariaDB Upgrade
        echo "    Running MariaDB upgrade check..."
        # Extract DB root password from .env
        ROOT_PW=$(grep "DB_ROOT_PASSWORD" "$SITE_PATH/.env" | cut -d'=' -f2 | tr -d '\r')
        if [ -n "$ROOT_PW" ]; then
            docker exec "${SITE_NAME}_db" mariadb-upgrade -u root -p"$ROOT_PW" 2>/dev/null
        fi

        # 5. Intelligent Rebuild and Restart
        echo "    Updating containers..."
        cd "$SITE_PATH"
        
        # Recreate to apply Compose changes and ALWAYS rebuild to include the latest wp-init.sh
        docker compose up -d --build --remove-orphans --force-recreate
        cd "$BASE_DIR"
        
        echo "    [DONE] $SITE_NAME is now updated."
    fi
done

echo ">>> All sites have been refreshed successfully!"