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

# --- FUNCTION: Force Let's Encrypt ACME Online Check/Renewal ---
force_acme_renewal() {
    local target_domain=$1
    if [ -z "$target_domain" ]; then
        read -p "Enter Domain Name (e.g. hny24.ir): " target_domain
    fi
    [ -z "$target_domain" ] && echo "Domain cannot be empty." && return 1

    echo -e "\n${CYAN}>>> Initiating Force Let's Encrypt (ACME) Renewal for: $target_domain...${NC}"

    # 1. Pre-Flight DNS Check
    echo -e "${CYAN}[1/4] Running DNS Pre-Flight Check...${NC}"
    local public_ip=$(curl -s --connect-timeout 5 https://ipinfo.io/ip || curl -s --connect-timeout 5 https://api.ipify.org || echo "UNKNOWN")
    local domain_ip=$(getent ahosts "$target_domain" 2>/dev/null | head -n1 | awk '{print $1}')
    
    if [ "$public_ip" != "UNKNOWN" ] && [ -n "$domain_ip" ]; then
        echo -e "    Public IP of Server: ${GREEN}$public_ip${NC}"
        echo -e "    DNS Resolves $target_domain to: ${GREEN}$domain_ip${NC}"
        if [ "$public_ip" != "$domain_ip" ]; then
            echo -e "${YELLOW}[WARNING] DNS resolution mismatch!${NC}"
            echo -e "          Your domain resolves to $domain_ip, but the server's public IP is $public_ip."
            echo -e "          ACME HTTP validation might fail if the DNS hasn't propagated or uses an incompatible CDN/Proxy."
            read -p "Do you want to proceed anyway? [y/N]: " proceed
            if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
                echo "Cancelled."
                return 1
            fi
        else
            echo -e "    ${GREEN}[SUCCESS] DNS points correctly to this server.${NC}"
        fi
    else
        echo -e "${YELLOW}[WARN] Could not perform full DNS pre-flight verification (offline or DNS tools missing). Proceeding...${NC}"
    fi

    # 2. Clean cache inside acme.json using python3
    echo -e "${CYAN}[2/4] Purging cached SSL certificates for $target_domain...${NC}"
    local acme_file="$BASE_DIR/shared/letsencrypt/acme.json"
    if [ -f "$acme_file" ]; then
        # Ensure we have a backup of acme.json just in case
        cp "$acme_file" "${acme_file}.bak"
        python3 -c "
import json, sys
file_path = '$acme_file'
domain = '$target_domain'
try:
    with open(file_path, 'r') as f:
        data = json.load(f)
    modified = False
    for resolver in data.values():
        if isinstance(resolver, dict) and 'Certificates' in resolver and resolver['Certificates']:
            certs = resolver['Certificates']
            filtered = [c for c in certs if c.get('domain', {}).get('main') != domain and c.get('domain', {}).get('main') != f'www.{domain}']
            if len(filtered) != len(certs):
                resolver['Certificates'] = filtered
                modified = True
    if modified:
        with open(file_path, 'w') as f:
            json.dump(data, f, indent=2)
        print('    Successfully removed cached domain states from acme.json')
    else:
        print('    No cached states found for this domain.')
except Exception as e:
    print(f'    Skipped acme.json optimization: {e}')
"
    else
        echo "    acme.json not found. Traefik will generate a new database on restart."
    fi

    # 3. Restart Traefik
    echo -e "${CYAN}[3/4] Restarting Traefik shared gateway to trigger immediate ACME check...${NC}"
    if command -v docker &> /dev/null && docker ps --format '{{.Names}}' | grep -q "^shared_gateway$"; then
        docker compose -f "$BASE_DIR/shared/docker-compose.yml" restart traefik
        echo -e "    ${GREEN}[SUCCESS] Traefik shared gateway restarted.${NC}"
    else
        echo -e "${RED}[ERROR] Traefik container (shared_gateway) is not running!${NC}"
        return 1
    fi

    # 4. Stream Live Logs
    echo -e "${CYAN}[4/4] Streaming live Traefik ACME logs for $target_domain...${NC}"
    echo -e "${YELLOW}>>> Press Ctrl+C to close log stream when SSL issue is completed.${NC}"
    echo -e "----------------------------------------------------------------------"
    docker logs -f shared_gateway 2>&1 | grep --line-buffered -E -i "acme|$target_domain"
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
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}         SSL MANAGEMENT FOR DOMAIN: $DOMAIN          ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo "1. Register Manual SSL (Offline / Local Certificates)"
    echo "2. Force Let's Encrypt ACME Online Check/Renewal"
    echo "3. Exit"
    echo "======================================================"
    read -p "Select option [1-3]: " CHOICE

    case $CHOICE in
        1) register_domain_interactive "$DOMAIN" ;;
        2) force_acme_renewal "$DOMAIN" ;;
        3) exit 0 ;;
        *) echo "Invalid option." ;;
    esac
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
    echo "3. Force Let's Encrypt ACME Online Check/Renewal"
    echo "4. Exit"
    echo ""
    read -p "Select option [1-4]: " CHOICE

    case $CHOICE in
        1) register_domain_interactive ;;
        2) sync_manual_certs ;;
        3) force_acme_renewal ;;
        4) exit 0 ;;
        *) echo "Invalid option." ;;
    esac
fi

