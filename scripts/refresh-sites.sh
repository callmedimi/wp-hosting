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
        cp "$TEMPLATE_DIR/wp-init.sh" "$SITE_PATH/wp-init.sh" 2>/dev/null

        # 2. Update docker-compose.yml (Check if memcached service exists)
        if ! grep -q "memcached:" "$SITE_PATH/docker-compose.yml"; then
            echo "    Adding Memcached service to docker-compose.yml..."
            
            MEMCACHED_BLOCK="  # ==========================================\n  # [CACHE] MEMCACHED\n  # ==========================================\n  memcached:\n    image: memcached:alpine\n    container_name: \${PROJECT_NAME}_memcached\n    restart: unless-stopped\n    networks:\n      - wp_net\n"
            
            sed -i "/networks:/i $MEMCACHED_BLOCK" "$SITE_PATH/docker-compose.yml"
            sed -i "/depends_on:/a \      - memcached" "$SITE_PATH/docker-compose.yml"
        fi

        # 3. Update docker-compose.yml (Check if builder service exists)
        if ! grep -q "builder:" "$SITE_PATH/docker-compose.yml"; then
            echo "    Adding Builder service to docker-compose.yml..."
            
            # We use a temporary file to construct the builder block to avoid sed escaping hell
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
    command: >
      sh -c "
      # Copy Lucide sprite if available and missing
      if [ -f /shared/node_modules/lucide/dist/lucide-sprite.svg ] && [ ! -f lucide-sprite.svg ]; then
        cp /shared/node_modules/lucide/dist/lucide-sprite.svg .
        echo 'Lucide sprite copied to site root.';
      fi;
      # Start Tailwind Watcher
      if [ -f input.css ]; then 
        npx tailwindcss -i ./input.css -o ./output.css --watch --poll; 
      else 
        echo 'No input.css found. Waiting...'; 
        tail -f /dev/null; 
      fi"
    networks:
      - wp_net

EOF
            # Insert builder block before the root 'networks:' key
            # 1. Insert marker
            sed -i '/^networks:/i #BUILDER_INJECTION_POINT' "$SITE_PATH/docker-compose.yml"
            # 2. Append file content after marker
            sed -i '/#BUILDER_INJECTION_POINT/r /tmp/builder_block.yml' "$SITE_PATH/docker-compose.yml"
            # 3. Remove marker
            sed -i '/#BUILDER_INJECTION_POINT/d' "$SITE_PATH/docker-compose.yml"
            
            rm /tmp/builder_block.yml
            
            # Add shared_node_modules volume if missing
             if ! grep -q "shared_node_modules:" "$SITE_PATH/docker-compose.yml"; then
                 # Check if volumes: block exists at the end
                 if grep -q "^volumes:" "$SITE_PATH/docker-compose.yml"; then
                     # Append to end
                     cat <<EOF >> "$SITE_PATH/docker-compose.yml"
  shared_node_modules:
    external: true
EOF
                 fi
             fi
        fi

        # 4. Copy Tailwind files if missing
        [ ! -f "$SITE_PATH/tailwind.config.js" ] && cp "$TEMPLATE_DIR/tailwind.config.js" "$SITE_PATH/"
        [ ! -f "$SITE_PATH/input.css" ] && cp "$TEMPLATE_DIR/input.css" "$SITE_PATH/"

        # 3. Rebuild and Restart
        echo "    Rebuilding and Restarting..."
        cd "$SITE_PATH"
        docker compose build --no-cache
        docker compose up -d
        cd "$BASE_DIR"
        
        echo "    [DONE] $SITE_NAME is now updated."
    fi
done

echo ">>> All sites have been refreshed successfully!"
