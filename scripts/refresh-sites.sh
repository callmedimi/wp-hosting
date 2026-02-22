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

        # 2. Update docker-compose.yml (Entrypoint & Memcached)
        echo "    Updating WordPress service in docker-compose.yml..."
        
        # Force entrypoint and command to ensure it runs every time
        if ! grep -q "entrypoint: \[\"/bin/bash\", \"/usr/local/bin/wp-init.sh\"\]" "$SITE_PATH/docker-compose.yml"; then
            # Remove any old entrypoint/command lines if they exist to prevent duplicates
            sed -i '/    entrypoint:/d' "$SITE_PATH/docker-compose.yml"
            sed -i '/    command:/d' "$SITE_PATH/docker-compose.yml"
            
            # Insert after container_name which is a stable anchor
            sed -i '/container_name: .*_wp/a \    entrypoint: ["/bin/bash", "/usr/local/bin/wp-init.sh"]\n    command: ["apache2-foreground"]' "$SITE_PATH/docker-compose.yml"
        fi

        # 2. Update docker-compose.yml (Remove Memcached if exists)
        echo "    Removing Memcached service from docker-compose.yml..."
        sed -i '/memcached:/,/^  [a-z]/ { /^  memcached:/d; /^    /d; }' "$SITE_PATH/docker-compose.yml"
        sed -i '/- memcached/d' "$SITE_PATH/docker-compose.yml"


        # 4. Intelligent Rebuild and Restart
        echo "    Updating containers..."
        cd "$SITE_PATH"
        
        # Skip build to save time (only up -d)
        docker compose up -d --remove-orphans
        cd "$BASE_DIR"
        
        echo "    [DONE] $SITE_NAME is now updated."
    fi
done

echo ">>> All sites have been refreshed successfully!"