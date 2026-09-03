#!/bin/bash

# ==========================================
# TAKE DOWN SITE SCRIPT
# ==========================================
# Easily and safely takes a site offline (docker compose down or stop)
# without touching database volumes, uploaded files, or configurations.

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITES_DIR="$BASE_DIR/sites"

SITE_NAME=$1
ACTION_MODE=$2

# Function to list sites with status
list_sites_summary() {
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
                    DOMAIN=$(grep "DOMAIN_NAME=" "${d}.env" 2>/dev/null | head -n 1 | cut -d '=' -f2 | tr -d '\r')
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
}

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}           TAKE DOWN A SITE (OFFLINE)                 ${NC}"
echo -e "${BLUE}======================================================${NC}"

# If site name wasn't passed as argument, show available sites & prompt
if [ -z "$SITE_NAME" ]; then
    echo -e "${CYAN}Available Sites:${NC}"
    list_sites_summary
    echo ""
    read -p "Enter Site Name to take down (folder name): " SITE_NAME
fi

if [ -z "$SITE_NAME" ]; then
    echo "No site specified. Operation cancelled."
    exit 0
fi

SITE_DIR="$SITES_DIR/$SITE_NAME"

if [ ! -d "$SITE_DIR" ] || [ ! -f "$SITE_DIR/docker-compose.yml" ]; then
    echo -e "${RED}[ERROR] Site '$SITE_NAME' not found in $SITES_DIR.${NC}"
    exit 1
fi

# Check current running state
IS_RUNNING=0
if docker ps --format '{{.Names}}' | grep -q "^${SITE_NAME}_wp$"; then
    IS_RUNNING=1
fi

if [ -z "$ACTION_MODE" ]; then
    echo ""
    if [ $IS_RUNNING -eq 1 ]; then
        echo -e "Site status: ${GREEN}RUNNING${NC}"
        echo "Choose take-down method:"
        echo "1. Complete Take Down (docker compose down) [Recommended]"
        echo "   - Frees containers, memory, CPU & network ports"
        echo "   - Preserves ALL database data, uploads, and site files"
        echo "2. Quick Stop (docker compose stop)"
        echo "   - Pauses containers without removing them"
        echo "3. Cancel"
        read -p "Select option [1-3, default 1]: " OPT
        OPT=${OPT:-1}
        
        case $OPT in
            1) ACTION_MODE="down" ;;
            2) ACTION_MODE="stop" ;;
            *) echo "Cancelled."; exit 0 ;;
        esac
    else
        echo -e "Site status: ${RED}STOPPED / OFFLINE${NC}"
        echo "1. Run 'docker compose down' anyway (cleans up any leftover containers/networks)"
        echo "2. Start site ('docker compose up -d')"
        echo "3. Cancel"
        read -p "Select option [1-3, default 1]: " OPT
        OPT=${OPT:-1}
        
        case $OPT in
            1) ACTION_MODE="down" ;;
            2) ACTION_MODE="up" ;;
            *) echo "Cancelled."; exit 0 ;;
        esac
    fi
fi

echo ""
cd "$SITE_DIR" || exit 1

if [ "$ACTION_MODE" == "down" ]; then
    echo -e "${YELLOW}>>> Taking down site '$SITE_NAME' (docker compose down)...${NC}"
    docker compose down
    echo ""
    echo -e "${GREEN}✅ SUCCESS: Site '$SITE_NAME' is now taken down.${NC}"
    echo -e "${CYAN}ℹ️  All WordPress files, uploads, and databases are preserved.${NC}"
    echo -e "To bring the site back online, run:"
    echo -e "    ${YELLOW}./manage.sh -> Access Site Tools -> Start Site${NC}"
    echo -e "    or: ${YELLOW}cd $SITE_DIR && docker compose up -d${NC}"
elif [ "$ACTION_MODE" == "stop" ]; then
    echo -e "${YELLOW}>>> Stopping site '$SITE_NAME' (docker compose stop)...${NC}"
    docker compose stop
    echo ""
    echo -e "${GREEN}✅ SUCCESS: Site '$SITE_NAME' has been stopped.${NC}"
    echo -e "To restart the site, run:"
    echo -e "    ${YELLOW}./manage.sh -> Access Site Tools -> Start Site${NC}"
    echo -e "    or: ${YELLOW}cd $SITE_DIR && docker compose start${NC}"
elif [ "$ACTION_MODE" == "up" ]; then
    echo -e "${YELLOW}>>> Starting site '$SITE_NAME' (docker compose up -d)...${NC}"
    docker compose up -d
    echo ""
    echo -e "${GREEN}✅ SUCCESS: Site '$SITE_NAME' is now running.${NC}"
else
    echo -e "${RED}[ERROR] Invalid action mode: $ACTION_MODE${NC}"
    exit 1
fi
