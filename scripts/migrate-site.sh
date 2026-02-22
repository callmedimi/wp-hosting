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
read -p "1. Enter New Site Name (folder, e.g. client_x): " SITE_NAME
read -p "2. Enter New Domain Name (e.g. newsite.com): " DOMAIN_NAME
read -p "3. Path to Source Files Directory (e.g. /tmp/old_files): " SRC_FILES
read -p "4. Path to SQL Dump File (e.g. /tmp/backup.sql): " SQP_PATH
read -p "5. Enter Old Domain to Replace (e.g. oldsite.com): " OLD_DOMAIN
read -s -p "6. Set SFTP/System Password: " SITE_PASS
echo ""

# Validation
if [ ! -d "$SRC_FILES" ]; then
    echo -e "${RED}[ERROR] Source directory not found: $SRC_FILES${NC}"
    exit 1
fi

if [ ! -f "$SQP_PATH" ]; then
    echo -e "${RED}[ERROR] SQL file not found: $SQP_PATH${NC}"
    exit 1
fi

# Step 1: Create the Site Infrastructure
echo -e "${GREEN}>>> Step 1: Creating base site containers...${NC}"
bash "$BASE_DIR/create-site.sh" "$SITE_NAME" "$DOMAIN_NAME" "$SITE_NAME" "$SITE_PASS"

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Site creation failed.${NC}"
    exit 1
fi

SITE_DIR="$BASE_DIR/sites/$SITE_NAME"

# Step 2: Copy Content
echo -e "${GREEN}>>> Step 2: Migrating wp-content and assets...${NC}"

# We remove the "fresh" wp-content to avoid conflicts
rm -rf "$SITE_DIR/wp-content"

if [ -d "$SRC_FILES/wp-content" ]; then
    cp -r "$SRC_FILES/wp-content" "$SITE_DIR/"
    echo "    copied wp-content from source."
else
    echo -e "${RED}[WARN] wp-content not found in source directory. Copying everything else...${NC}"
    cp -r "$SRC_FILES/"* "$SITE_DIR/"
fi

# Fix ownership
chown -R 1001:1001 "$SITE_DIR"
chmod -R 775 "$SITE_DIR"

# Step 3: Database Import
echo -e "${GREEN}>>> Step 3: Importing database...${NC}"
DB_CONTAINER="${SITE_NAME}_db"
DB_NAME=$(grep "DB_NAME=" "$SITE_DIR/.env" | cut -d'=' -f2)
DB_USER=$(grep "DB_USER=" "$SITE_DIR/.env" | cut -d'=' -f2)
DB_PASS=$(grep "DB_PASSWORD=" "$SITE_DIR/.env" | cut -d'=' -f2)

# Wait for DB to be ready
echo "    Waiting for MariaDB to initialize..."
sleep 10

# Import using docker exec
docker exec -i "$DB_CONTAINER" mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQP_PATH"

if [ $? -eq 0 ]; then
    echo "    Database imported successfully."
else
    echo -e "${RED}[ERROR] Database import failed.${NC}"
fi

# Step 4: Search and Replace
echo -e "${GREEN}>>> Step 4: Updating URLs in database...${NC}"
WP_CONTAINER="${SITE_NAME}_wp"

# Perform search-replace via WP-CLI inside the container
docker exec -u 1001 "$WP_CONTAINER" wp search-replace "$OLD_DOMAIN" "$DOMAIN_NAME" --allow-root

echo -e "${GREEN}>>> Step 5: Finalizing...${NC}"
# Flush cache if object cache is active
docker exec -u 1001 "$WP_CONTAINER" wp cache flush --allow-root 2>/dev/null

echo ""
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}✅ MIGRATION COMPLETE!${NC}"
echo "New Site URL: https://$DOMAIN_NAME"
echo "Folder:       $SITE_DIR"
echo -e "${BLUE}==========================================${NC}"
