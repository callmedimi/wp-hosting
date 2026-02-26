#!/bin/bash

# ==============================================================================
# SECURITY & WAF MANAGEMENT
# ==============================================================================

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BASE_DIR="/opt/wp-hosting"
DYNAMIC_DIR="$BASE_DIR/shared/traefik-dynamic"
GEOBLOCK_FILE="$DYNAMIC_DIR/geoblock-waf.yml"

manage_geoblock() {
    echo -e "\n${BLUE}>>> Geo-IP Blocklist Management${NC}"
    
    if grep -q "ZZ # Placeholder" "$GEOBLOCK_FILE"; then
        echo -e "${YELLOW}No countries are currently blocked.${NC}"
    else
        echo -e "${CYAN}Currently Blocked Countries:${NC}"
        grep " - " "$GEOBLOCK_FILE" | grep -v "Placeholder"
    fi
    
    echo ""
    echo "1. Add a Country to Blocklist"
    echo "2. Remove a Country from Blocklist"
    echo "3. Clear All Blocks"
    echo "4. Back to Security Menu"
    read -p "Choose Option: " GOPT
    
    case $GOPT in
        1)
            read -p "Enter 2-letter Country Code to BLOCK (e.g. CN, RU, US): " CCODE
            CCODE=$(echo "$CCODE" | tr '[:lower:]' '[:upper:]')
            if [ -n "$CCODE" ]; then
                # Remove placeholder if first entry
                sed -i '/ZZ # Placeholder/d' "$GEOBLOCK_FILE"
                # Add new country
                if ! grep -q "\- $CCODE" "$GEOBLOCK_FILE"; then
                     sed -i "/countries:/a \            - $CCODE" "$GEOBLOCK_FILE"
                     echo -e "${GREEN}Country $CCODE added to blocklist. Traefik will apply this instantly!${NC}"
                else
                     echo -e "${YELLOW}Country $CCODE is already blocked.${NC}"
                fi
            fi
            ;;
        2)
            read -p "Enter 2-letter Country Code to UNBLOCK (e.g. CN): " CCODE
            CCODE=$(echo "$CCODE" | tr '[:lower:]' '[:upper:]')
            if [ -n "$CCODE" ]; then
                sed -i "/\- $CCODE/d" "$GEOBLOCK_FILE"
                echo -e "${GREEN}Country $CCODE removed from blocklist.${NC}"
                
                # Check if empty, add placeholder back
                if ! grep -q "\-" "$GEOBLOCK_FILE"; then
                    sed -i "/countries:/a \            - ZZ # Placeholder" "$GEOBLOCK_FILE"
                fi
            fi
            ;;
        3)
            echo "Clearing all blocked countries..."
            sed -i '/\- [A-Z]\{2\}/d' "$GEOBLOCK_FILE"
             sed -i "/countries:/a \            - ZZ # Placeholder" "$GEOBLOCK_FILE"
            echo -e "${GREEN}Blocklist cleared.${NC}"
            ;;
        4)
            return
            ;;
    esac
}

show_waf_logs() {
    echo -e "\n${BLUE}>>> Traefik & WAF Logs (Live)${NC}"
    echo "Press Ctrl+C to exit log view."
    cd "$BASE_DIR/shared" && docker compose logs -f traefik
}

while true; do
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}        SECURITY & WAF MANAGEMENT (Coraza)            ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo "1. Manage Geo-IP Blocklist (Block whole countries)"
    echo "2. View Traefik/WAF Live Logs"
    echo "3. Exit to Main Menu"
    
    read -p "Choose Option [1-3]: " SOPT
    
    case $SOPT in
        1) manage_geoblock; read -p "Press Enter..." ;;
        2) show_waf_logs ;;
        3) break ;;
        *) echo "Invalid Option" ;;
    esac
done
