#!/bin/bash

# ==========================================
# WORDPRESS MIGRATION TOOL
# ==========================================
# Migrates an existing WordPress site to this server.
# 1. Creates a new site container.
# 2. Copies source files (wp-content).
# 3. Imports the SQL database.
# 4. Performs Search & Replace for the domain.

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}      WORDPRESS MIGRATION WIZARD          ${NC}"
echo -e "${BLUE}==========================================${NC}"

# Inputs
echo -e "${CYAN}--- Please provide the following details ---${NC}"

# Clear any trailing input
read -t 1 -n 10000 DISCARD 2>/dev/null

read -p "1. Enter New Site Name (folder, e.g. client_x): " SITE_NAME
if [ -z "$SITE_NAME" ]; then echo -e "${RED}Error: Site name is required.${NC}"; exit 1; fi

read -p "2. Enter New Domain (e.g. newsite.com): " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then echo -e "${RED}Error: Domain is required.${NC}"; exit 1; fi

read -p "3. Path to Source Files Directory (contains wp-content): " SRC_FILES
if [ -z "$SRC_FILES" ]; then echo -e "${RED}Error: Source path is required.${NC}"; exit 1; fi

read -p "4. Path to SQL Dump File (.sql): " SQP_PATH
if [ -z "$SQP_PATH" ]; then echo -e "${RED}Error: SQL path is required.${NC}"; exit 1; fi

read -p "5. Enter Old Domain to Replace: " OLD_DOMAIN
if [ -z "$OLD_DOMAIN" ]; then echo -e "${RED}Error: Old domain is required.${NC}"; exit 1; fi

read -s -p "6. Set SFTP/System Password: " SITE_PASS
echo -e "\n------------------------------------------"

# Define paths and IDs
SITE_DIR="$BASE_DIR/sites/$SITE_NAME"
WP_CONTAINER="${SITE_NAME}_wp"

# Guidance: Clean domains
NEW_DOMAIN_CLEAN=$(echo "$DOMAIN_NAME" | sed -e 's|^https\?://||' -e 's|/$||')
OLD_DOMAIN_CLEAN=$(echo "$OLD_DOMAIN" | sed -e 's|^https\?://||' -e 's|/$||')

# Validation
if [ ! -d "$SRC_FILES" ]; then
    echo -e "${RED}[ERROR] Source directory not found at: $SRC_FILES${NC}"
    exit 1
fi

if [ ! -f "$SQP_PATH" ]; then
    echo -e "${RED}[ERROR] SQL file not found at: $SQP_PATH${NC}"
    exit 1
fi

# Step 1: Create the Site Infrastructure
echo -e "${GREEN}>>> Step 1: Creating base site containers...${NC}"

# Detect prefix BEFORE starting for the first time if possible? 
# Actually create-site.sh starts it. We will adjust it after.
bash "$BASE_DIR/create-site.sh" "$SITE_NAME" "$DOMAIN_NAME" "$SITE_NAME" "$SITE_PASS"

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Site creation failed.${NC}"
    exit 1
fi

# Detect table prefix from source wp-config.php
TABLE_PREFIX="wp_"
if [ -f "$SRC_FILES/wp-config.php" ]; then
    DETECTED_PREFIX=$(sed -n "s/.*\$table_prefix *= *['\"]\(.*\)['\"];.*/\1/p" "$SRC_FILES/wp-config.php" | head -n 1)
    if [ -n "$DETECTED_PREFIX" ] && [ "$DETECTED_PREFIX" != "wp_" ]; then
        TABLE_PREFIX=$DETECTED_PREFIX
        echo -e "${CYAN}    Detected custom table prefix: $TABLE_PREFIX${NC}"
        # Use sed to replace or append
        if grep -q "WORDPRESS_TABLE_PREFIX" "$SITE_DIR/.env"; then
            sed -i "s/WORDPRESS_TABLE_PREFIX=.*/WORDPRESS_TABLE_PREFIX=$TABLE_PREFIX/" "$SITE_DIR/.env"
        else
            echo "WORDPRESS_TABLE_PREFIX=$TABLE_PREFIX" >> "$SITE_DIR/.env"
        fi
        echo "    Updating container to use custom prefix..."
        cd "$SITE_DIR" && docker compose up -d --force-recreate
    fi
fi

# Step 2: Copy Content
echo -e "${GREEN}>>> Step 2: Migrating wp-content and assets...${NC}"

# STOP container to prevent it from regenerating files while we copy
echo "    Pausing WordPress container for file migration..."
docker stop "$WP_CONTAINER" >/dev/null

# We remove the "fresh" wp-content to avoid conflicts
rm -rf "$SITE_DIR/wp-content"

if [ -d "$SRC_FILES/wp-content" ]; then
    cp -r "$SRC_FILES/wp-content" "$SITE_DIR/"
    echo "    copied wp-content from source."
else
    echo -e "${RED}[WARN] wp-content not found in source directory. Copying everything else...${NC}"
    cp -r "$SRC_FILES/"* "$SITE_DIR/"
fi

# START container back
docker start "$WP_CONTAINER" >/dev/null
echo "    WordPress container resumed."

# Fix ownership (Host should match the SITE_NAME/SFTP_USER)
chown -R "$SITE_NAME:$SITE_NAME" "$SITE_DIR"
chmod -R 775 "$SITE_DIR"

# Step 3: Database Import
echo -e "${GREEN}>>> Step 3: Importing database...${NC}"
DB_CONTAINER="${SITE_NAME}_db"
DB_NAME=$(grep "DB_NAME=" "$SITE_DIR/.env" | cut -d'=' -f2)
DB_USER=$(grep "DB_USER=" "$SITE_DIR/.env" | cut -d'=' -f2)
DB_PASS=$(grep "DB_PASSWORD=" "$SITE_DIR/.env" | cut -d'=' -f2)

# Wait for DB to be ready
echo "    Waiting for MariaDB to initialize..."
for i in {1..30}; do
    if docker exec "$DB_CONTAINER" mysqladmin ping -u"$DB_USER" -p"$DB_PASS" --silent; then
        break
    fi
    sleep 2
done

# Import using docker exec with collation fix (utf8mb4_0900_ai_ci is MySQL 8 only)
echo "    Processing SQL and importing (auto-fixing collations)..."
sed -e 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_ci/g' \
    -e 's/utf8mb4_unicode_520_ci/utf8mb4_unicode_ci/g' \
    "$SQP_PATH" | docker exec -i "$DB_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME"

if [ $? -eq 0 ]; then
    echo "    Database imported successfully."
else
    echo -e "${RED}[ERROR] Database import failed.${NC}"
fi

# Step 4: Search and Replace
echo -e "${GREEN}>>> Step 4: Updating URLs in database...${NC}"

# Wait for WP-CLI to be ready inside the container (wp-init.sh might be downloading it)
echo "    Waiting for WP-CLI to be ready..."
for i in {1..60}; do
    # Check if command exists OR if files exist in known locations
    if docker exec "$WP_CONTAINER" command -v wp >/dev/null 2>&1 || \
       docker exec "$WP_CONTAINER" [ -f /usr/local/bin/wp ] || \
       docker exec "$WP_CONTAINER" [ -f /tmp/wp ]; then
        break
    fi
    [ $((i % 5)) -eq 0 ] && echo "    ...still waiting for WP-CLI ($i/60)"
    sleep 2
done

# Define WP_CMD to Use inside docker exec
WP_CMD="wp"
if ! docker exec "$WP_CONTAINER" command -v wp >/dev/null 2>&1; then
    if docker exec "$WP_CONTAINER" [ -f /usr/local/bin/wp ]; then
        WP_CMD="/usr/local/bin/wp"
    elif docker exec "$WP_CONTAINER" [ -f /tmp/wp ]; then
        WP_CMD="/tmp/wp"
    fi
fi

if ! docker exec "$WP_CONTAINER" $WP_CMD --version >/dev/null 2>&1; then
     echo -e "${RED}[ERROR] WP-CLI is not functional. Search & Replace skipped!${NC}"
     echo "        Please run it manually later: docker exec $WP_CONTAINER wp search-replace ..."
else
    # Perform search-replace
    docker exec "$WP_CONTAINER" $WP_CMD search-replace "$OLD_DOMAIN_CLEAN" "$NEW_DOMAIN_CLEAN" --all-tables --allow-root
fi

# Step 5: Fix wp-config.php (Database Host)
echo "    Ensuring wp-config.php uses the internal Docker DB host..."
docker exec "$WP_CONTAINER" sed -i "s/define( *'DB_HOST', *'[^']*' *)/define('DB_HOST', 'db')/g" wp-config.php 2>/dev/null
docker exec "$WP_CONTAINER" sed -i "s/define( *\"DB_HOST\", *\"[^\"]*\" *)/define(\"DB_HOST\", \"db\")/g" wp-config.php 2>/dev/null

echo -e "${GREEN}>>> Step 6: Finalizing...${NC}"
# Flush cache if object cache is active
if docker exec "$WP_CONTAINER" command -v wp >/dev/null 2>&1; then
    docker exec "$WP_CONTAINER" wp cache flush --allow-root 2>/dev/null
fi

# Ensure correct permissions one last time 
docker exec "$WP_CONTAINER" chown -R www-data:www-data /var/www/html

echo ""
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}✅ MIGRATION COMPLETE!${NC}"
echo "New Site URL: https://$DOMAIN_NAME"
echo "Folder:       $SITE_DIR"
echo -e "${BLUE}==========================================${NC}"
