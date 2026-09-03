#!/bin/bash

# ==========================================
# BACKUP SITE TOOL
# ==========================================
# Creates a complete backup of a site:
# 1. SQL database dump (via mysqldump from DB container)
# 2. Compressed tar.gz archive of the site home directory (sites/<site_name>)
# Stored in: backup/<site_name>/
#   - <site_name>.sql (and timestamped copy)
#   - <site_name>_files.tar.gz (and timestamped copy)
#   - backup.info (metadata manifest for easy restoration anywhere)

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITES_DIR="$BASE_DIR/sites"
BACKUP_ROOT="$BASE_DIR/backup"

mkdir -p "$BACKUP_ROOT" 2>/dev/null
# Compatibility symlink for "back up" directory name
if [ ! -e "$BASE_DIR/back up" ]; then
    ln -sfn "$BACKUP_ROOT" "$BASE_DIR/back up" 2>/dev/null || true
fi

TARGET_ARG=$1

list_available_sites() {
    printf "%-20s %-30s %-15s\n" "FOLDER" "DOMAIN" "STATUS"
    echo "----------------------------------------------------------------"
    local count=0
    if [ -d "$SITES_DIR" ]; then
        for d in "$SITES_DIR"/*/; do
            if [ -f "${d}docker-compose.yml" ]; then
                count=$((count + 1))
                FOLDER=$(basename "$d")
                DOMAIN="unknown"
                if [ -f "${d}.env" ]; then
                    DOMAIN=$(grep "^DOMAIN_NAME=" "${d}.env" 2>/dev/null | head -n 1 | cut -d '=' -f2 | tr -d '\r')
                fi
                if docker ps --format '{{.Names}}' | grep -q "^${FOLDER}_wp$"; then
                    STATUS="${GREEN}RUNNING${NC}"
                else
                    STATUS="${RED}STOPPED${NC}"
                fi
                printf "%-20s %-30s %b\n" "$FOLDER" "$DOMAIN" "$STATUS"
            fi
        done
    fi
    if [ $count -eq 0 ]; then
        echo "No sites found in $SITES_DIR."
    fi
    return $count
}

backup_single_site() {
    local SITE_NAME=$1
    local SITE_DIR="$SITES_DIR/$SITE_NAME"
    local SITE_BACKUP_DIR="$BACKUP_ROOT/$SITE_NAME"
    local TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    local HUMAN_DATE=$(date +"%Y-%m-%d %H:%M:%S")

    if [ ! -d "$SITE_DIR" ] || [ ! -f "$SITE_DIR/.env" ]; then
        echo -e "${RED}[ERROR] Site '$SITE_NAME' does not exist in $SITES_DIR.${NC}"
        return 1
    fi

    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}>>> Backing up Site: $SITE_NAME${NC}"
    echo -e "${CYAN}======================================================${NC}"

    mkdir -p "$SITE_BACKUP_DIR"

    # Extract credentials from .env
    local DB_USER=$(grep "^DB_USER=" "$SITE_DIR/.env" | cut -d'=' -f2- | tr -d '\r')
    local DB_PASS=$(grep "^DB_PASSWORD=" "$SITE_DIR/.env" | cut -d'=' -f2- | tr -d '\r')
    local DB_NAME=$(grep "^DB_NAME=" "$SITE_DIR/.env" | cut -d'=' -f2- | tr -d '\r')
    local DOMAIN=$(grep "^DOMAIN_NAME=" "$SITE_DIR/.env" | cut -d'=' -f2- | tr -d '\r')
    local DB_CONTAINER="${SITE_NAME}_db"

    # 1. Database Dump
    echo -e "--> [1/2] Creating SQL database dump..."
    local WAS_DB_STARTED=0
    if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
        echo "    DB container is not running. Starting temporarily for dump..."
        (cd "$SITE_DIR" && docker compose up -d db >/dev/null 2>&1)
        WAS_DB_STARTED=1
        
        # Wait for DB to be responsive
        for i in {1..30}; do
            if docker exec -e MYSQL_PWD="$DB_PASS" "$DB_CONTAINER" mysqladmin ping -u"$DB_USER" --silent >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
    fi

    local SQL_FILE="$SITE_BACKUP_DIR/${SITE_NAME}.sql"
    local SQL_TS_FILE="$SITE_BACKUP_DIR/${SITE_NAME}_db_${TIMESTAMP}.sql"

    if docker exec -e MYSQL_PWD="$DB_PASS" "$DB_CONTAINER" mysqldump -u"$DB_USER" \
        --single-transaction --quick --routines --triggers "$DB_NAME" > "$SQL_FILE" 2>/dev/null; then
        
        # Verify SQL file is not empty
        if [ -s "$SQL_FILE" ]; then
            cp "$SQL_FILE" "$SQL_TS_FILE"
            local SQL_SIZE=$(du -h "$SQL_FILE" | cut -f1)
            echo -e "${GREEN}    Database dumped successfully ($SQL_SIZE):${NC}"
            echo "    -> $SQL_FILE"
        else
            echo -e "${RED}[ERROR] Database dump produced an empty file.${NC}"
        fi
    else
        echo -e "${RED}[ERROR] mysqldump failed for $SITE_NAME.${NC}"
    fi

    # If we started DB container solely for this backup, stop it
    if [ $WAS_DB_STARTED -eq 1 ]; then
        echo "    Stopping temporarily started DB container..."
        (cd "$SITE_DIR" && docker compose stop db >/dev/null 2>&1)
    fi

    # 2. Site Files Archive (tar.gz)
    echo -e "--> [2/2] Archiving site home directory..."
    local TAR_FILE="$SITE_BACKUP_DIR/${SITE_NAME}_files.tar.gz"
    local TAR_TS_FILE="$SITE_BACKUP_DIR/${SITE_NAME}_files_${TIMESTAMP}.tar.gz"

    # Archive sites/$SITE_NAME excluding internal caches, dumps or previous archives
    tar --exclude='*.tar.gz' \
        --exclude='*.sql' \
        --exclude='*.tar' \
        --exclude='backups' \
        --exclude='.git' \
        -czf "$TAR_FILE" \
        -C "$SITES_DIR" "$SITE_NAME"

    if [ -s "$TAR_FILE" ]; then
        cp "$TAR_FILE" "$TAR_TS_FILE"
        local TAR_SIZE=$(du -h "$TAR_FILE" | cut -f1)
        echo -e "${GREEN}    Files archived successfully ($TAR_SIZE):${NC}"
        echo "    -> $TAR_FILE"
    else
        echo -e "${RED}[ERROR] File archiving failed for $SITE_NAME.${NC}"
    fi

    # 3. Write metadata info manifest
    cat <<EOF > "$SITE_BACKUP_DIR/backup.info"
# WP-HOSTING BACKUP MANIFEST
SITE_NAME=$SITE_NAME
DOMAIN_NAME=$DOMAIN
BACKUP_TIMESTAMP=$TIMESTAMP
BACKUP_DATE=$HUMAN_DATE
SQL_FILE=${SITE_NAME}.sql
SQL_TIMESTAMP_FILE=${SITE_NAME}_db_${TIMESTAMP}.sql
FILES_ARCHIVE=${SITE_NAME}_files.tar.gz
FILES_TIMESTAMP_ARCHIVE=${SITE_NAME}_files_${TIMESTAMP}.tar.gz
DB_NAME=$DB_NAME
DB_USER=$DB_USER
EOF

    echo ""
    echo -e "${GREEN}✅ Backup complete for '$SITE_NAME'!${NC}"
    echo -e "Destination folder: ${YELLOW}$SITE_BACKUP_DIR${NC}"
    echo "Files inside backup folder:"
    ls -lh "$SITE_BACKUP_DIR" | grep -v '^total' | awk '{printf "   %-10s %-8s %s\n", $5, $6" "$7, $9}'
    echo ""
    return 0
}

# --- Main Dispatch ---

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}             WP-HOSTING BACKUP TOOL                   ${NC}"
echo -e "${BLUE}======================================================${NC}"

if [ "$TARGET_ARG" == "--all" ] || [ "$TARGET_ARG" == "-a" ] || [ "$TARGET_ARG" == "all" ]; then
    echo -e "${GREEN}>>> Backing up ALL sites...${NC}"
    SUCCESS_COUNT=0
    TOTAL_COUNT=0
    for d in "$SITES_DIR"/*/; do
        if [ -f "${d}docker-compose.yml" ]; then
            TOTAL_COUNT=$((TOTAL_COUNT + 1))
            S_NAME=$(basename "$d")
            if backup_single_site "$S_NAME"; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            fi
        fi
    done
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}Finished: $SUCCESS_COUNT / $TOTAL_COUNT sites backed up successfully.${NC}"
    echo -e "All backups are stored in: ${YELLOW}$BACKUP_ROOT${NC}"
    exit 0
fi

if [ -n "$TARGET_ARG" ]; then
    backup_single_site "$TARGET_ARG"
    exit $?
fi

# Interactive Mode
echo -e "${CYAN}Select an action or choose a site to back up:${NC}"
echo ""
list_available_sites
echo ""
echo "Options:"
echo "  [Site Name] - Type the name of a site from above to back up"
echo "  [A]         - Backup ALL sites"
echo "  [Q]         - Cancel and Exit"
echo ""
read -p "Enter choice [Site Name / A / Q]: " USER_CHOICE

case "$USER_CHOICE" in
    [Aa])
        echo -e "${GREEN}>>> Starting full backup of all sites...${NC}"
        for d in "$SITES_DIR"/*/; do
            if [ -f "${d}docker-compose.yml" ]; then
                S_NAME=$(basename "$d")
                backup_single_site "$S_NAME"
            fi
        done
        ;;
    [Qq]|"")
        echo "Backup cancelled."
        exit 0
        ;;
    *)
        backup_single_site "$USER_CHOICE"
        ;;
esac
