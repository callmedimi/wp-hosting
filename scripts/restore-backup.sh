#!/bin/bash

# ==========================================
# RESTORE SITE BACKUP TOOL
# ==========================================
# Easily restores a site from a backup folder (backup/<site_name>/)
# or custom archive paths on THIS server or ANY OTHER server.
#
# Process:
# 1. Unpacks the site home directory (tar.gz) into sites/<site_name>
# 2. Ensures the Docker network (wp_shared_net) is ready
# 3. Boots containers (docker compose up -d)
# 4. Imports the SQL dump into MariaDB
# 5. Optional Search & Replace (if domain changed or moved servers)
# 6. Corrects file permissions and flushes cache

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITES_DIR="$BASE_DIR/sites"
BACKUP_ROOT="$BASE_DIR/backup"

mkdir -p "$SITES_DIR" 2>/dev/null
mkdir -p "$BACKUP_ROOT" 2>/dev/null

INPUT_SRC=$1
TARGET_NAME=$2

list_available_backups() {
    printf "%-20s %-25s %-12s %-12s\n" "SITE" "BACKUP DATE" "SQL SIZE" "FILES SIZE"
    echo "----------------------------------------------------------------------------------"
    local count=0
    if [ -d "$BACKUP_ROOT" ]; then
        for b_dir in "$BACKUP_ROOT"/*/; do
            if [ -d "$b_dir" ]; then
                local S_NAME=$(basename "$b_dir")
                local SQL_F=$(find "$b_dir" -maxdepth 1 -name "*.sql" | head -n 1)
                local TAR_F=$(find "$b_dir" -maxdepth 1 -name "*.tar.gz" | head -n 1)
                local B_DATE="Unknown"
                
                if [ -f "$b_dir/backup.info" ]; then
                    B_DATE=$(grep "^BACKUP_DATE=" "$b_dir/backup.info" 2>/dev/null | cut -d'=' -f2- | tr -d '\r')
                elif [ -n "$SQL_F" ]; then
                    B_DATE=$(date -r "$SQL_F" +"%Y-%m-%d %H:%M" 2>/dev/null || echo "Existing")
                fi
                
                local SQL_SZ="N/A"
                local TAR_SZ="N/A"
                if [ -n "$SQL_F" ] && [ -f "$SQL_F" ]; then SQL_SZ=$(du -h "$SQL_F" | cut -f1); fi
                if [ -n "$TAR_F" ] && [ -f "$TAR_F" ]; then TAR_SZ=$(du -h "$TAR_F" | cut -f1); fi
                
                if [ -n "$SQL_F" ] || [ -n "$TAR_F" ]; then
                    count=$((count + 1))
                    printf "%-20s %-25s %-12s %-12s\n" "$S_NAME" "$B_DATE" "$SQL_SZ" "$TAR_SZ"
                fi
            fi
        done
    fi
    if [ $count -eq 0 ]; then
        echo "No backups currently found in $BACKUP_ROOT."
    fi
    return $count
}

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}           WP-HOSTING RESTORE WIZARD                  ${NC}"
echo -e "${BLUE}======================================================${NC}"

# If no input argument provided, interactive selection
if [ -z "$INPUT_SRC" ]; then
    echo -e "${CYAN}Available Site Backups in $BACKUP_ROOT:${NC}"
    echo ""
    list_available_backups
    echo ""
    echo "Options:"
    echo "  - Type a site name from above to restore from $BACKUP_ROOT/<site_name>"
    echo "  - Or provide a custom path to a backup folder or files"
    echo ""
    read -p "Enter backup site name or path (or press Enter to cancel): " INPUT_SRC
fi

if [ -z "$INPUT_SRC" ]; then
    echo "Restoration cancelled."
    exit 0
fi

# Determine backup directory and file paths
BACKUP_DIR=""
if [ -d "$BACKUP_ROOT/$INPUT_SRC" ]; then
    BACKUP_DIR="$BACKUP_ROOT/$INPUT_SRC"
    BACKUP_SITE_NAME="$INPUT_SRC"
elif [ -d "$INPUT_SRC" ]; then
    BACKUP_DIR="$INPUT_SRC"
    BACKUP_SITE_NAME=$(basename "$INPUT_SRC")
else
    echo -e "${RED}[ERROR] Backup directory not found at: $INPUT_SRC (or $BACKUP_ROOT/$INPUT_SRC)${NC}"
    exit 1
fi

# Locate SQL and TAR files
SQL_FILE=$(find "$BACKUP_DIR" -maxdepth 1 -name "${BACKUP_SITE_NAME}.sql" 2>/dev/null | head -n 1)
if [ -z "$SQL_FILE" ]; then
    SQL_FILE=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.sql" 2>/dev/null | sort -r | head -n 1)
fi

TAR_FILE=$(find "$BACKUP_DIR" -maxdepth 1 -name "${BACKUP_SITE_NAME}_files.tar.gz" 2>/dev/null | head -n 1)
if [ -z "$TAR_FILE" ]; then
    TAR_FILE=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" 2>/dev/null | sort -r | head -n 1)
fi

if [ -z "$TAR_FILE" ] || [ ! -f "$TAR_FILE" ]; then
    echo -e "${RED}[ERROR] Could not find a valid .tar.gz archive in $BACKUP_DIR.${NC}"
    exit 1
fi

if [ -z "$SQL_FILE" ] || [ ! -f "$SQL_FILE" ]; then
    echo -e "${RED}[ERROR] Could not find a valid .sql database dump in $BACKUP_DIR.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Detected Backup Files:${NC}"
echo "  Archive: $TAR_FILE ($(du -h "$TAR_FILE" | cut -f1))"
echo "  SQL:     $SQL_FILE ($(du -h "$SQL_FILE" | cut -f1))"

# Read metadata if present
SAVED_DOMAIN=""
if [ -f "$BACKUP_DIR/backup.info" ]; then
    SAVED_DOMAIN=$(grep "^DOMAIN_NAME=" "$BACKUP_DIR/backup.info" 2>/dev/null | cut -d'=' -f2- | tr -d '\r')
fi

# Confirm Target Site Name
if [ -z "$TARGET_NAME" ]; then
    echo ""
    read -p "Enter Target Site Name for this server [Default: $BACKUP_SITE_NAME]: " TARGET_NAME
    TARGET_NAME=${TARGET_NAME:-$BACKUP_SITE_NAME}
fi

TARGET_SITE_DIR="$SITES_DIR/$TARGET_NAME"

# Check if site already exists
if [ -d "$TARGET_SITE_DIR" ]; then
    echo ""
    echo -e "${YELLOW}⚠️ WARNING: Site '$TARGET_NAME' already exists in $SITES_DIR!${NC}"
    read -p "Do you want to OVERWRITE this site with the backup? [y/N]: " OVERWRITE_CONFIRM
    if [[ ! "$OVERWRITE_CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Restoration aborted."
        exit 0
    fi
    
    echo ">>> Stopping existing containers for $TARGET_NAME..."
    (cd "$TARGET_SITE_DIR" && docker compose down 2>/dev/null || true)
fi

# Step 1: Extract Files
echo ""
echo -e "${CYAN}>>> [1/5] Extracting site files...${NC}"
mkdir -p "$TARGET_SITE_DIR"

# Test whether the tar archive contains a top-level directory matching BACKUP_SITE_NAME
FIRST_ENTRY=$(tar -tf "$TAR_FILE" 2>/dev/null | head -n 1 | cut -d'/' -f1)

if [ "$FIRST_ENTRY" == "$BACKUP_SITE_NAME" ]; then
    # Extract into parent directory if names match, or strip component if renaming
    if [ "$TARGET_NAME" == "$BACKUP_SITE_NAME" ]; then
        tar -xzf "$TAR_FILE" -C "$SITES_DIR"
    else
        tar -xzf "$TAR_FILE" -C "$TARGET_SITE_DIR" --strip-components=1
    fi
else
    tar -xzf "$TAR_FILE" -C "$TARGET_SITE_DIR"
fi

if [ ! -f "$TARGET_SITE_DIR/.env" ]; then
    echo -e "${RED}[ERROR] Extraction completed, but no .env file was found in $TARGET_SITE_DIR.${NC}"
    exit 1
fi

# If site was renamed, adapt .env and docker-compose.yml
if [ "$TARGET_NAME" != "$BACKUP_SITE_NAME" ]; then
    echo "    Adjusting project and container names to '$TARGET_NAME'..."
    sed -i "s/^PROJECT_NAME=.*/PROJECT_NAME=$TARGET_NAME/" "$TARGET_SITE_DIR/.env" 2>/dev/null || true
    sed -i "s/^WORDPRESS_DB_HOST=.*/WORDPRESS_DB_HOST=${TARGET_NAME}_db/" "$TARGET_SITE_DIR/.env" 2>/dev/null || true
    if [ -f "$TARGET_SITE_DIR/docker-compose.yml" ]; then
        sed -i "s/container_name: ${BACKUP_SITE_NAME}_/container_name: ${TARGET_NAME}_/g" "$TARGET_SITE_DIR/docker-compose.yml" 2>/dev/null || true
    fi
fi

# Step 2: Ensure Network and Start Stack
echo -e "${CYAN}>>> [2/5] Initializing Docker network & starting containers...${NC}"
docker network create wp_shared_net 2>/dev/null || true

cd "$TARGET_SITE_DIR" || exit 1
docker compose up -d

WP_CONTAINER="${TARGET_NAME}_wp"
DB_CONTAINER="${TARGET_NAME}_db"

# Step 3: Wait for MariaDB & Import SQL Dump
echo -e "${CYAN}>>> [3/5] Waiting for Database and importing SQL dump...${NC}"
DB_USER=$(grep "^DB_USER=" "$TARGET_SITE_DIR/.env" | cut -d'=' -f2- | tr -d '\r')
DB_PASS=$(grep "^DB_PASSWORD=" "$TARGET_SITE_DIR/.env" | cut -d'=' -f2- | tr -d '\r')
DB_NAME=$(grep "^DB_NAME=" "$TARGET_SITE_DIR/.env" | cut -d'=' -f2- | tr -d '\r')

echo "    Pinging MariaDB in $DB_CONTAINER..."
DB_READY=0
for i in {1..35}; do
    if docker exec -e MYSQL_PWD="$DB_PASS" "$DB_CONTAINER" mysqladmin ping -u"$DB_USER" --silent >/dev/null 2>&1; then
        DB_READY=1
        break
    fi
    sleep 2
done

if [ $DB_READY -eq 0 ]; then
    echo -e "${RED}[ERROR] MariaDB failed to respond in container $DB_CONTAINER.${NC}"
    exit 1
fi

echo "    Processing SQL dump for maximum compatibility..."
TMP_SQL="/tmp/${TARGET_NAME}_restore.sql"

# Sanitize collations and strip CREATE DATABASE / USE to prevent cross-database collision
sed -e 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_ci/g' \
    -e 's/utf8mb4_unicode_520_ci/utf8mb4_unicode_ci/g' \
    -e '/^[[:space:]]*CREATE DATABASE/Id' \
    -e '/^[[:space:]]*USE /Id' \
    "$SQL_FILE" > "$TMP_SQL"

echo "    Importing database dump into '$DB_NAME'..."
if docker exec -e MYSQL_PWD="$DB_PASS" -i "$DB_CONTAINER" mysql -u"$DB_USER" "$DB_NAME" < "$TMP_SQL"; then
    echo -e "${GREEN}    Database imported successfully.${NC}"
else
    echo -e "${RED}[ERROR] Database import failed.${NC}"
fi
rm -f "$TMP_SQL"

# Step 4: Domain Handling / Search & Replace
echo -e "${CYAN}>>> [4/5] Domain Configuration...${NC}"
CURRENT_DOMAIN=$(grep "^DOMAIN_NAME=" "$TARGET_SITE_DIR/.env" | cut -d'=' -f2- | tr -d '\r')
if [ -z "$CURRENT_DOMAIN" ]; then CURRENT_DOMAIN="$SAVED_DOMAIN"; fi

echo "Backup Domain: $CURRENT_DOMAIN"
echo "Options:"
echo "  1. Keep '$CURRENT_DOMAIN' (No URL changes) [Default]"
echo "  2. Migrate to a NEW domain (Runs WP-CLI Search & Replace across DB)"
read -p "Select [1-2, default 1]: " DOMAIN_OPT
DOMAIN_OPT=${DOMAIN_OPT:-1}

if [ "$DOMAIN_OPT" == "2" ]; then
    read -p "Enter NEW Domain (e.g. newsite.com): " NEW_DOMAIN
    if [ -n "$NEW_DOMAIN" ]; then
        OLD_DOMAIN_CLEAN=$(echo "$CURRENT_DOMAIN" | sed -e 's|^https\?://||' -e 's|/$||')
        NEW_DOMAIN_CLEAN=$(echo "$NEW_DOMAIN" | sed -e 's|^https\?://||' -e 's|/$||')

        # Update .env
        sed -i "s/^DOMAIN_NAME=.*/DOMAIN_NAME=$NEW_DOMAIN_CLEAN/" "$TARGET_SITE_DIR/.env"
        
        # Wait for WP-CLI
        echo "    Waiting for WP-CLI inside $WP_CONTAINER..."
        for i in {1..30}; do
            if docker exec "$WP_CONTAINER" [ -f /usr/local/bin/wp ] 2>/dev/null; then
                break
            fi
            sleep 2
        done

        DOCROOT="/var/www/vhosts/localhost/html"
        WP_CMD="php -d memory_limit=1024M /usr/local/bin/wp"

        echo "    Replacing: $OLD_DOMAIN_CLEAN -> $NEW_DOMAIN_CLEAN..."
        docker exec -w "$DOCROOT" "$WP_CONTAINER" $WP_CMD search-replace "$OLD_DOMAIN_CLEAN" "$NEW_DOMAIN_CLEAN" --all-tables --allow-root --path="$DOCROOT" 2>/dev/null || true
        docker exec -w "$DOCROOT" "$WP_CONTAINER" $WP_CMD search-replace "https://$OLD_DOMAIN_CLEAN" "https://$NEW_DOMAIN_CLEAN" --all-tables --allow-root --path="$DOCROOT" 2>/dev/null || true
        docker exec -w "$DOCROOT" "$WP_CONTAINER" $WP_CMD search-replace "http://$OLD_DOMAIN_CLEAN" "https://$NEW_DOMAIN_CLEAN" --all-tables --allow-root --path="$DOCROOT" 2>/dev/null || true

        CURRENT_DOMAIN="$NEW_DOMAIN_CLEAN"
        # Restart web container to apply Traefik labels
        cd "$TARGET_SITE_DIR" && docker compose up -d
    fi
fi

# Step 5: Permissions, Cache & Finalization
echo -e "${CYAN}>>> [5/5] Finalizing permissions & flushing cache...${NC}"
DOCROOT="/var/www/vhosts/localhost/html"
docker exec "$WP_CONTAINER" chown -R nobody:nogroup "$DOCROOT" 2>/dev/null || true
chown -R 1001:1001 "$TARGET_SITE_DIR" 2>/dev/null || true
chmod -R 775 "$TARGET_SITE_DIR" 2>/dev/null || true

# Flush cache
docker exec -w "$DOCROOT" "$WP_CONTAINER" php -d memory_limit=512M /usr/local/bin/wp cache flush --allow-root --path="$DOCROOT" 2>/dev/null || true

# Register in Homepage dashboard if file exists
HOMEPAGE_FILE="$BASE_DIR/shared/homepage/services.yaml"
if [ -f "$HOMEPAGE_FILE" ] && [ -n "$CURRENT_DOMAIN" ]; then
    if ! grep -q "$CURRENT_DOMAIN" "$HOMEPAGE_FILE"; then
        if ! grep -q -- "- Sites:" "$HOMEPAGE_FILE"; then
            echo -e "\n- Sites:" >> "$HOMEPAGE_FILE"
        fi
        cat <<EOF >> "$HOMEPAGE_FILE"
    - $TARGET_NAME:
        icon: wordpress.png
        href: https://$CURRENT_DOMAIN
        description: Restored WordPress Site
        server: my-docker
        container: ${TARGET_NAME}_wp
EOF
        echo "    Registered site in Dashboard."
    fi
fi

echo ""
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}✅ SITE RESTORED SUCCESSFULLY!${NC}"
echo -e "${GREEN}======================================================${NC}"
echo "Site Name:   $TARGET_NAME"
echo "Site Domain: https://$CURRENT_DOMAIN"
echo "Site Path:   $TARGET_SITE_DIR"
echo "Status:      Running in Docker"
echo ""
