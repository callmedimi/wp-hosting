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

        # 2. Update docker-compose.yml (Resources)
        echo "    Optimizing docker-compose.yml..."
        
        # Ensure memory limits exist but CPU limits are STRIPPED
        sed -i '/cpus:.*/d' "$SITE_PATH/docker-compose.yml"
        if ! grep -q "memory:" "$SITE_PATH/docker-compose.yml"; then
            sed -i 's/restart: unless-stopped/deploy:\n      resources:\n        limits:\n          memory: 1024M\n    restart: unless-stopped/' "$SITE_PATH/docker-compose.yml"
        else
            sed -i 's/memory: 768M/memory: 1024M/g' "$SITE_PATH/docker-compose.yml"
        fi

        # Remove hardcoded entrypoints/commands in compose (rely on Dockerfile)
        sed -i '/    entrypoint:/d' "$SITE_PATH/docker-compose.yml"
        sed -i '/    command:/d' "$SITE_PATH/docker-compose.yml"
        
        # Force the use of standard Dockerfile
        sed -i '/dockerfile:/d' "$SITE_PATH/docker-compose.yml"

        # 3. Handle MariaDB Upgrade
        echo "    Running MariaDB upgrade check..."
        ROOT_PW=$(grep "DB_ROOT_PASSWORD" "$SITE_PATH/.env" | cut -d'=' -f2 | tr -d '\r')
        if [ -n "$ROOT_PW" ]; then
            docker exec "${SITE_NAME}_db" mariadb-upgrade -u root -p"$ROOT_PW" 2>/dev/null
        fi

        # 4. Fix DB_HOST DNS Collision (use unique container name)
        echo "    Fixing DB_HOST to use unique container name..."
        if ! grep -q "WORDPRESS_DB_HOST" "$SITE_PATH/.env"; then
            echo "WORDPRESS_DB_HOST=${SITE_NAME}_db" >> "$SITE_PATH/.env"
        else
            sed -i "s/WORDPRESS_DB_HOST=.*/WORDPRESS_DB_HOST=${SITE_NAME}_db/" "$SITE_PATH/.env"
        fi

        # 5. Intelligent Rebuild and Restart
        echo "    Updating containers..."
        cd "$SITE_PATH"
        
        # Recreate to apply Compose changes and ALWAYS rebuild to include the latest wp-init.sh
        docker compose up -d --build --remove-orphans --force-recreate

        # 6. Fix wp-config.php DB_HOST inside the running container
        echo "    Patching wp-config.php DB_HOST..."
        sleep 5
        docker exec "${SITE_NAME}_wp" sed -i "s/define( 'DB_HOST', '.*' );/define( 'DB_HOST', '${SITE_NAME}_db' );/" /var/www/vhosts/localhost/html/wp-config.php 2>/dev/null

        cd "$BASE_DIR"
        
        echo "    [DONE] $SITE_NAME is now updated."
    fi
done

echo ">>> All sites have been refreshed successfully!"