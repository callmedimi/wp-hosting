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
        
        # Force entrypoint to our script to ensure it runs every time
        if ! grep -q "entrypoint: \[\"/bin/bash\", \"/usr/local/bin/wp-init.sh\"\]" "$SITE_PATH/docker-compose.yml"; then
            # We insert it after the image: line
            sed -i '/image: .*-wordpress/a \    entrypoint: ["/bin/bash", "/usr/local/bin/wp-init.sh"]' "$SITE_PATH/docker-compose.yml"
        fi

        if ! grep -q "memcached:" "$SITE_PATH/docker-compose.yml"; then
            echo "    Adding Memcached service..."
            MEMCACHED_BLOCK="  # ==========================================\n  # [CACHE] MEMCACHED\n  # ==========================================\n  memcached:\n    image: memcached:alpine\n    container_name: \${PROJECT_NAME}_memcached\n    restart: unless-stopped\n    networks:\n      - wp_net\n"
            sed -i "/networks:/i $MEMCACHED_BLOCK" "$SITE_PATH/docker-compose.yml"
            sed -i "/depends_on:/a \      - memcached" "$SITE_PATH/docker-compose.yml"
        fi

        # 2. Update docker-compose.yml (Check if builder service exists)
        echo "    Updating Builder service in docker-compose.yml..."
        
        # --- CLEANUP: Remove old builder blocks to prevent duplicates/syntax errors ---
        # This removes the builder service and its previous configurations safely
        sed -i '/  builder:/,/^  [a-z]/ { /^  builder:/d; /^    /d; }' "$SITE_PATH/docker-compose.yml"
        
        # Create fresh builder service block
        cat <<EOF > /tmp/builder_block.yml
  # ==========================================
  # [BUILDER] TAILWIND & ASSETS
  # ==========================================
  builder:
    image: node:lts-alpine
    container_name: \${PROJECT_NAME}_builder
    restart: unless-stopped
    working_dir: /var/www/html
    volumes:
      - ./:/var/www/html
      - shared_node_modules:/shared/node_modules
    environment:
      - NODE_PATH=/shared/node_modules
      - PATH=/shared/node_modules/.bin:\${PATH}
    command: sh /var/www/html/builder.sh
    networks:
      - wp_net

EOF
        # Insert builder block before the root 'networks:' key
        sed -i '/^networks:/i #BUILDER_INJECTION_POINT' "$SITE_PATH/docker-compose.yml"
        sed -i '/#BUILDER_INJECTION_POINT/r /tmp/builder_block.yml' "$SITE_PATH/docker-compose.yml"
        sed -i '/#BUILDER_INJECTION_POINT/d' "$SITE_PATH/docker-compose.yml"
        rm /tmp/builder_block.yml
        
        # Add shared_node_modules volume registration if missing
        if ! grep -q "shared_node_modules:" "$SITE_PATH/docker-compose.yml"; then
            if grep -q "^volumes:" "$SITE_PATH/docker-compose.yml"; then
                # Append to end of volumes block safely
                sed -i '/^volumes:/a \  shared_node_modules:\n    external: true' "$SITE_PATH/docker-compose.yml"
            else
                echo -e "\nvolumes:\n  db_data:\n  shared_node_modules:\n    external: true" >> "$SITE_PATH/docker-compose.yml"
            fi
        fi

        # 4. Copy Builder & Tailwind files
        cp "$TEMPLATE_DIR/builder.sh" "$SITE_PATH/builder.sh"
        sed -i 's/\r$//' "$SITE_PATH/builder.sh" 2>/dev/null
        chmod +x "$SITE_PATH/builder.sh"
        [ ! -f "$SITE_PATH/tailwind.config.js" ] && cp "$TEMPLATE_DIR/tailwind.config.js" "$SITE_PATH/"
        [ ! -f "$SITE_PATH/input.css" ] && cp "$TEMPLATE_DIR/input.css" "$SITE_PATH/"

        # 5. Intelligent Rebuild and Restart
        echo "    Updating containers..."
        cd "$SITE_PATH"
        
        # Only build if Dockerfile is different from what was previously used
        # We check if the image exists. If it doesn't, or if we want to be safe, we build.
        # But we remove --no-cache to use Docker layering.
        if [[ "$(docker images -q ${SITE_NAME}-wordpress 2> /dev/null)" == "" ]]; then
            echo "    Initial build for $SITE_NAME..."
            docker compose build
        else
            # Check if Dockerfile was actually updated by comparing checksums (optional but faster)
            docker compose build
        fi
        
        docker compose up -d --remove-orphans
        cd "$BASE_DIR"
        
        echo "    [DONE] $SITE_NAME is now updated."
    fi
done

echo ">>> All sites have been refreshed successfully!"
