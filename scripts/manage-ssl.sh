#!/bin/bash
# ==============================================================================
# HYBRID SSL MANAGEMENT TOOL (Manual + ACME Let's Encrypt)
# ==============================================================================
# Resolves certificates offline (manual upload) and online (automatic ACME)
# ==============================================================================

DOMAIN=$1
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LE_DIR="$BASE_DIR/shared/letsencrypt"
TLS_CONF="$BASE_DIR/shared/traefik-dynamic/tls.yml"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Ensure base directories exist
mkdir -p "$LE_DIR"
mkdir -p "$(dirname "$TLS_CONF")"

# --- FUNCTION: Auto-Scan & Sync Manual Certificates ---
sync_manual_certs() {
    echo -e "\n${CYAN}>>> Scanning for manual SSL certificates in: $LE_DIR...${NC}"
    
    # Create a secure temporary file for the YAML config
    TEMP_CONF=$(mktemp)
    echo "tls:" > "$TEMP_CONF"
    echo "  certificates:" >> "$TEMP_CONF"
    
    local count=0
    
    # Find all subdirectories under shared/letsencrypt
    for dir in "$LE_DIR"/*/; do
        [ -d "$dir" ] || continue
        local folder_name=$(basename "$dir")
        
        # Skip special/internal folders
        if [ "$folder_name" == "manual" ] || [ "$folder_name" == "acme.json" ] || [ "$folder_name" == "traefik-dynamic" ]; then
            continue
        fi
        
        local cert_file="$dir/fullchain.pem"
        local key_file="$dir/privkey.pem"
        
        if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
            # SECURITY & STABILITY VALIDATION:
            # Traefik will fail/stop loading other certificates if any file is empty or corrupted.
            # We strictly validate the PEM structure before writing it.
            if ! grep -q "\-----BEGIN CERTIFICATE-----" "$cert_file"; then
                echo -e "${RED}[WARNING] Skipped $folder_name: Certificate file ($cert_file) does not contain valid PEM data!${NC}"
                continue
            fi
            if ! grep -q "\-----BEGIN" "$key_file" || ! grep -q "KEY-----" "$key_file"; then
                echo -e "${RED}[WARNING] Skipped $folder_name: Private key file ($key_file) does not contain valid PEM key data!${NC}"
                continue
            fi
            
            echo -e "${GREEN}  [FOUND] Valid manual certificates for domain: $folder_name${NC}"
            cat <<EOF >> "$TEMP_CONF"
    - certFile: /letsencrypt/$folder_name/fullchain.pem
      keyFile: /letsencrypt/$folder_name/privkey.pem
EOF
            count=$((count+1))
        fi
    done
    
    if [ $count -gt 0 ]; then
        mv "$TEMP_CONF" "$TLS_CONF"
        echo -e "${GREEN}✅ [SUCCESS] Rebuilt tls.yml with $count active manual certificates.${NC}"
        
        # Trigger dynamic reload
        touch "$TLS_CONF"
        if command -v docker &> /dev/null && docker ps --format '{{.Names}}' | grep -q "^shared_gateway$"; then
            echo -e "${CYAN}>>> Triggering Traefik dynamic hot-reload...${NC}"
            docker exec shared_gateway kill -s SIGHUP 1 2>/dev/null || true
            echo -e "${GREEN}>>> Hot-reload successfully sent to Traefik!${NC}"
        fi
    else
        # Clean up temp file
        rm -f "$TEMP_CONF"
        if [ -f "$TLS_CONF" ]; then
            rm "$TLS_CONF"
            echo -e "${YELLOW}>>> No manual certificates found. Cleared tls.yml so Traefik fully delegates to automatic Let's Encrypt (ACME).${NC}"
            # Reload Traefik to clear cache
            if command -v docker &> /dev/null && docker ps --format '{{.Names}}' | grep -q "^shared_gateway$"; then
                docker exec shared_gateway kill -s SIGHUP 1 2>/dev/null || true
            fi
        else
            echo -e "${YELLOW}>>> No manual certificates found. Traefik will run in 100% Automatic Let's Encrypt mode.${NC}"
        fi
    fi
}

# --- FUNCTION: Interactive Register Domain ---
register_domain_interactive() {
    local target_domain=$1
    if [ -z "$target_domain" ]; then
        read -p "Enter Domain Name (e.g. hny24.ir): " target_domain
    fi
    [ -z "$target_domain" ] && echo "Domain cannot be empty." && return 1

    echo -e "\n${CYAN}>>> Registering Manual SSL for: $target_domain...${NC}"
    mkdir -p "$LE_DIR/$target_domain"
    
    if [ ! -f "$LE_DIR/$target_domain/fullchain.pem" ]; then
        echo -e "${YELLOW}[ACTION REQUIRED] Please upload or place your certificate files on the host at:${NC}"
        echo -e "  📄 Certificate Chain:  ${GREEN}$LE_DIR/$target_domain/fullchain.pem${NC}"
        echo -e "  🔑 Private Key:         ${GREEN}$LE_DIR/$target_domain/privkey.pem${NC}"
        echo ""
        echo "Once the files are uploaded, run option 2 (Scan & Sync) to activate them."
    else
        sync_manual_certs
    fi
}

# MAIN EXECUTION
if [ -n "$DOMAIN" ]; then
    # Run directly for a specific domain
    register_domain_interactive "$DOMAIN"
else
    # Interactive Console Mode
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}         HYBRID SSL CERTIFICATE CONSOLE               ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo "  💡 Offline/Restricted: Upload cert files to use them manualy."
    echo "  💡 Online: Let Traefik auto-issue Let's Encrypt certs."
    echo "======================================================"
    echo "1. Register a New Domain for Manual SSL"
    echo "2. Re-Scan & Sync All Uploaded Certificates"
    echo "3. Exit"
    echo ""
    read -p "Select option [1-3]: " CHOICE

    case $CHOICE in
        1) register_domain_interactive ;;
        2) sync_manual_certs ;;
        3) exit 0 ;;
        *) echo "Invalid option." ;;
    esac
fi

