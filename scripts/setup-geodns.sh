#!/bin/bash
# ==============================================================================
# GEO-DNS SETUP SCRIPT (BIND9 + Docker)
# ==============================================================================
# This script installs and configures a BIND9 server with Geo-routing.
# It works on ANY server role (Manager, Worker, or Standalone).
# 
# Usage:
#   ./setup-geodns.sh install         - Full deployment (Docker + Config)
#   ./setup-geodns.sh add             - Add a new domain zone
#   ./setup-geodns.sh refresh         - Refresh Iran IP Lists
#   ./setup-geodns.sh status          - Check DNS container status
# ==============================================================================

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Directory Config (Relative to script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIND_DIR="$BASE_DIR/shared/bind9"
CONFIG_DIR="$BIND_DIR/config"
RECORDS_DIR="$BIND_DIR/records"
CACHE_DIR="$BIND_DIR/cache"

# Ensure directories exist
mkdir -p "$CONFIG_DIR" "$RECORDS_DIR" "$CACHE_DIR"

# --- HELPER: Create Docker Compose ---
create_docker_compose() {
    # 1. Custom UI Dockerfile (Need Docker CLI inside)
    cat <<EOF > "$BIND_DIR/Dockerfile.ui"
FROM olivetin/olivetin:latest
RUN apk add --no-cache docker-cli bash curl
EOF

    # 2. BIND9 + UI Compose
    cat <<EOF > "$BIND_DIR/docker-compose.yml"
version: '3.8'
services:
  bind9:
    image: ubuntu/bind9:latest
    container_name: shared_geodns
    user: root
    ports:
      - "53:53/udp"
      - "53:53/tcp"
    volumes:
      - ./config:/etc/bind
      - ./records:/var/lib/bind
      - ./cache:/var/cache/bind
    environment:
      - BIND9_USER=root
      - TZ=UTC
    networks:
      - wp_shared_net
    restart: unless-stopped

  dns_ui:
    build:
      context: .
      dockerfile: Dockerfile.ui
    image: custom-olivetin:latest
    container_name: shared_geodns_ui
    ports:
      - "1337:1337"
    volumes:
      - ./config/olivetin.yaml:/config/config.yaml
      - ../..:/opt/wp-hosting:ro
      - ./records:/var/lib/bind:rw
      - ./config:/etc/bind:rw
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - TZ=UTC
    networks:
      - wp_shared_net
    restart: unless-stopped
    depends_on:
      - bind9

networks:
  wp_shared_net:
    external: true
EOF
    echo -e "${GREEN}[SUCCESS] docker-compose.yml created (BIND9 + Web UI).${NC}"

    # 3. OliveTin Config
    cat <<EOF > "$CONFIG_DIR/olivetin.yaml"
actions:
  - title: "Restart DNS Service"
    icon: "restart"
    shell: "docker restart shared_geodns"
    timeout: 30

  - title: "List Domains & IPs"
    icon: "format-list-bulleted"
    shell: "grep 'zone \"' /etc/bind/named.conf.zones.world | cut -d '\"' -f 2 | while read domain; do echo \"\$domain (World: \$(grep -E '@\s+IN\s+A' /var/lib/bind/db.\$domain.world | awk '{print \$NF}' | head -1))\"; done"

  - title: "Add New Domain"
    icon: "plus-box"
    shell: "/bin/bash /opt/wp-hosting/scripts/setup-geodns.sh add '{{ domain }}' '{{ world_ip }}' '{{ iran_ip }}'"
    timeout: 30
    arguments:
      - name: domain
        title: "Domain Name (e.g. example.com)"
        type: ascii
      - name: world_ip
        title: "World IP"
        type: ip_address
      - name: iran_ip
        title: "Iran IP (Replica)"
        type: ip_address

  - title: "Quick Update Domain IP"
    icon: "pencil"
    shell: "/bin/bash /opt/wp-hosting/scripts/setup-geodns.sh add '{{ domain }}' '{{ world_ip }}' '{{ iran_ip }}'"
    timeout: 30
    arguments:
      - name: domain
        title: "Existing Domain"
        type: ascii
      - name: world_ip
        title: "New World IP"
        type: ip_address
      - name: iran_ip
        title: "New Iran IP"
        type: ip_address

  - title: "Refresh Iran IP Lists"
    icon: "refresh"
    shell: "/bin/bash /opt/wp-hosting/scripts/setup-geodns.sh refresh"

  - title: "View Logs"
    icon: "text-box-search"
    shell: "docker logs --tail 50 shared_geodns"

EOF
    echo -e "${GREEN}[SUCCESS] Web UI configuration generated.${NC}"
}

# --- HELPER: Register with Dashboard ---
register_dashboard() {
    HOMEPAGE_FILE="$BASE_DIR/shared/homepage/services.yaml"
    
    if [ -f "$HOMEPAGE_FILE" ]; then
        if ! grep -q "GeoDNS Manager" "$HOMEPAGE_FILE"; then
            echo -e "${YELLOW}--> Adding GeoDNS to Manager Dashboard...${NC}"
            
            # Use specific insertion to keep YAML valid
            # We append it to the end or a specific section
            cat <<EOF >> "$HOMEPAGE_FILE"

    - GeoDNS Manager:
        icon: dns.png
        href: "http://$(hostname -I | cut -d' ' -f1):1337"
        description: "Manage Zones & Records"
        widget:
            type: olivetin
            url: http://shared_geodns_ui:1337
EOF
            echo -e "${GREEN}[SUCCESS] Added to Dashboard!${NC}"
        else
            echo "Dashboard already configured."
        fi
    else
        echo -e "${YELLOW}[NOTE] Dashboard Config not found locally.${NC}"
        echo "If this is a remote node, add this to your Manager's services.yaml:"
        echo ""
        echo "    - GeoDNS ($(hostname)):"
        echo "        icon: dns.png"
        echo "        href: \"http://$(hostname -I | cut -d' ' -f1):1337\""
        echo "        description: \"DNS Manager for $(hostname)\""
        echo ""
    fi
}

# --- HELPER: Create Base Config ---
create_base_config() {
    # 1. Download Iran IP Ranges
    echo -e "${YELLOW}--> Downloading Iran IP Ranges...${NC}"
    IRAN_CIDR_URL="https://raw.githubusercontent.com/herrbischoff/country-ip-blocks/master/ipv4/ir.cidr"
    
    echo "acl \"iran\" {" > "$CONFIG_DIR/named.conf.iran-acl"
    curl -s "$IRAN_CIDR_URL" | sed 's/$/;/' >> "$CONFIG_DIR/named.conf.iran-acl"
    echo "};" >> "$CONFIG_DIR/named.conf.iran-acl"
    
    # 2. Base named.conf
    cat <<EOF > "$CONFIG_DIR/named.conf"
options {
    directory "/var/cache/bind";
    recursion no;
    allow-query { any; };
    allow-transfer { none; };
    listen-on { any; };
    listen-on-v6 { any; };
};

include "/etc/bind/named.conf.iran-acl";

# VIEW: IRAN (Domestic Traffic)
view "iran" {
    match-clients { iran; };
    recursion no;
    include "/etc/bind/named.conf.zones.iran";
};

# VIEW: WORLD (International Traffic)
view "world" {
    match-clients { any; };
    recursion no;
    include "/etc/bind/named.conf.zones.world";
};
EOF
    
    # 3. Create empty zone lists
    touch "$CONFIG_DIR/named.conf.zones.iran"
    touch "$CONFIG_DIR/named.conf.zones.world"
    
    echo -e "${GREEN}[SUCCESS] BIND9 configuration initialized.${NC}"
}

# --- HELPER: Register with Dashboard ---
register_dashboard() {
    HOMEPAGE_FILE="$BASE_DIR/shared/homepage/services.yaml"
    
    if [ -f "$HOMEPAGE_FILE" ]; then
        if ! grep -q "GeoDNS Manager" "$HOMEPAGE_FILE"; then
            echo -e "${YELLOW}--> Adding GeoDNS to Manager Dashboard...${NC}"
            
            # Use specific insertion to keep YAML valid
            # We append it to the end or a specific section
            cat <<EOF >> "$HOMEPAGE_FILE"

    - GeoDNS Manager:
        icon: dns.png
        href: "http://$(hostname -I | cut -d' ' -f1):1337"
        description: "Manage Zones & records"
        widget:
            type: olivetin
            url: http://shared_geodns_ui:1337
EOF
            echo -e "${GREEN}[SUCCESS] Added to Dashboard!${NC}"
        else
            echo "Dashboard already configured."
        fi
    else
        echo -e "${YELLOW}[NOTE] Dashboard Config not found locally.${NC}"
        echo "If this is a remote node, add this to your Manager's services.yaml:"
        echo ""
        echo "    - GeoDNS ($(hostname)):"
        echo "        icon: dns.png"
        echo "        href: \"http://$(hostname -I | cut -d' ' -f1):1337\""
        echo "        description: \"DNS Manager for $(hostname)\""
        echo ""
    fi
}

# --- HELPER: Create Base Config ---
create_base_config() {
    # 1. Download Iran IP Ranges
    echo -e "${YELLOW}--> Downloading Iran IP Ranges...${NC}"
    IRAN_CIDR_URL="https://raw.githubusercontent.com/herrbischoff/country-ip-blocks/master/ipv4/ir.cidr"
    
    echo "acl \"iran\" {" > "$CONFIG_DIR/named.conf.iran-acl"
    curl -s "$IRAN_CIDR_URL" | sed 's/$/;/' >> "$CONFIG_DIR/named.conf.iran-acl"
    echo "};" >> "$CONFIG_DIR/named.conf.iran-acl"
    
    # 2. Base named.conf
    cat <<EOF > "$CONFIG_DIR/named.conf"
options {
    directory "/var/cache/bind";
    recursion no;
    allow-query { any; };
    allow-transfer { none; };
    listen-on { any; };
    listen-on-v6 { any; };
};

include "/etc/bind/named.conf.iran-acl";

# VIEW: IRAN (Domestic Traffic)
view "iran" {
    match-clients { iran; };
    recursion no;
    include "/etc/bind/named.conf.zones.iran";
};

# VIEW: WORLD (International Traffic)
view "world" {
    match-clients { any; };
    recursion no;
    include "/etc/bind/named.conf.zones.world";
};
EOF
    
    # 3. Create empty zone lists
    touch "$CONFIG_DIR/named.conf.zones.iran"
    touch "$CONFIG_DIR/named.conf.zones.world"
    
    echo -e "${GREEN}[SUCCESS] BIND9 configuration initialized.${NC}"
}

# --- HELPER: Generate Zone File ---
generate_zone() {
    local ZONE_FILE=$1
    local DOMAIN=$2
    local TARGET_IP=$3
    local NS_IP=$4
    local SERIAL=$(date +%Y%m%d01)
    
cat <<EOF > "$ZONE_FILE"
\$TTL 3600
@   IN  SOA ns1.$DOMAIN. admin.$DOMAIN. (
        $SERIAL ; Serial
        3600       ; Refresh
        1800       ; Retry
        604800     ; Expire
        86400 )    ; Minimum TTL

; Nameservers
@       IN  NS      ns1.$DOMAIN.
@       IN  NS      ns2.$DOMAIN.

; A Records
@       IN  A       $TARGET_IP
www     IN  A       $TARGET_IP
*       IN  A       $TARGET_IP

; NS Records (Glue)
ns1     IN  A       $NS_IP
ns2     IN  A       $NS_IP
EOF
}

# Main Logic
clear
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}        GeoDNS MANAGER (BIND9 + Docker)       ${NC}"
echo -e "${BLUE}======================================================${NC}"

# Support CLI args
ACTION=$1

if [ -z "$ACTION" ]; then
    echo "1. Full Installation (Any Server Role)"
    echo "2. Add a New Domain Zone"
    echo "3. Quick Modify Domain IPs"
    echo "4. Advanced Zone Management (Records: MX, TXT, CNAME...)"
    echo "5. Refresh Iran IP Lists"
    echo "6. Restart DNS Container"
    echo "7. Show Status & Logs"
    read -p "Select Option [1-7]: " CHOICE
else
    case $ACTION in
        install) CHOICE=1 ;;
        add) CHOICE=2 ;;
        modify) CHOICE=3 ;;
        manage) CHOICE=4 ;;
        refresh) CHOICE=5 ;;
        restart) CHOICE=6 ;;
        status) CHOICE=7 ;;
        *) echo -e "${RED}Unknown action: $ACTION${NC}"; exit 1 ;;
    esac
fi

# --- ADVANCED ZONE MANAGEMENT FUNCTION ---
manage_advanced_zone() {
    echo -e "\n${BLUE}>>> Advanced Zone Management${NC}"
    mapfile -t Z_LIST < <(grep 'zone "' "$CONFIG_DIR/named.conf.zones.world" | cut -d '"' -f 2)
    
    if [ ${#Z_LIST[@]} -eq 0 ]; then
        echo "No domains found."
        return
    fi

    for i in "${!Z_LIST[@]}"; do echo "$((i+1)). ${Z_LIST[$i]}"; done
    read -p "Select domain [1-${#Z_LIST[@]}]: " Z_IDX
    [ -z "$Z_IDX" ] && return
    SEL_DOMAIN="${Z_LIST[$((Z_IDX-1))]}"

    while true; do
        echo -e "\n${CYAN}Managing: $SEL_DOMAIN${NC}"
        echo "1. List All Records"
        echo "2. Add Custom Record"
        echo "3. Add Nameserver (NS + Glue)"
        echo "4. Delete Custom Record"
        echo "5. Manual Edit (vi)"
        echo "6. Back"
        read -p "Option: " Z_OPT

        case $Z_OPT in
            1)
                echo -e "\n--- WORLD VIEW ---"
                cat "$RECORDS_DIR/db.$SEL_DOMAIN.world"
                echo -e "\n--- IRAN VIEW ---"
                cat "$RECORDS_DIR/db.$SEL_DOMAIN.iran"
                ;;
            2)
                echo "Views: 1) World Only  2) Iran Only  3) Both"
                read -p "Target View [1-3]: " V_TARGET
                read -p "Record Name (e.g. mail, @, _acme-challenge): " R_NAME
                read -p "Type (A, CNAME, MX, TXT, NS): " R_TYPE
                read -p "Value (IP, domain, or \"text\"): " R_VALUE
                
                # Format MX specifically if needed
                [ "$R_TYPE" == "MX" ] && read -p "Priority (e.g. 10): " R_PRIO && R_VALUE="$R_PRIO $R_VALUE"

                VIEWS_TO_EDIT=()
                [ "$V_TARGET" == "1" ] && VIEWS_TO_EDIT=("world")
                [ "$V_TARGET" == "2" ] && VIEWS_TO_EDIT=("iran")
                [ "$V_TARGET" == "3" ] && VIEWS_TO_EDIT=("world" "iran")

                for v in "${VIEWS_TO_EDIT[@]}"; do
                    echo "$R_NAME    IN  $R_TYPE    $R_VALUE" >> "$RECORDS_DIR/db.$SEL_DOMAIN.$v"
                done
                echo -e "${GREEN}Record added.${NC}"
                ;;
            3)
                echo -e "${CYAN}--- Add Nameserver & Glue ---${NC}"
                read -p "Nameserver Hostname (e.g. ns3): " NS_HOST
                # Ensure no dot at the end of hostname if it's a subdomain of the current zone
                NS_HOST=${NS_HOST%.$SEL_DOMAIN.} # Remove full domain if typed
                NS_HOST=${NS_HOST%.} # Remove trailing dot

                read -p "Nameserver IP (e.g. 1.2.3.4): " NS_IP
                
                # 1. Add NS Record (@ IN NS ns3.domain.com.)
                # 2. Add Glue Record (ns3 IN A 1.2.3.4)
                
                for v in "world" "iran"; do
                    echo "@       IN  NS      $NS_HOST.$SEL_DOMAIN." >> "$RECORDS_DIR/db.$SEL_DOMAIN.$v"
                    echo "$NS_HOST     IN  A       $NS_IP" >> "$RECORDS_DIR/db.$SEL_DOMAIN.$v"
                done
                echo -e "${GREEN}Nameserver $NS_HOST.$SEL_DOMAIN added with IP $NS_IP (Both Views).${NC}"
                ;;
            4)
                echo "Enter a unique string from the record line you want to DELETE:"
                read -p "Pattern: " R_PAT
                [ -z "$R_PAT" ] && continue
                sed -i "/$R_PAT/d" "$RECORDS_DIR/db.$SEL_DOMAIN.world"
                sed -i "/$R_PAT/d" "$RECORDS_DIR/db.$SEL_DOMAIN.iran"
                echo -e "${YELLOW}Matching records removed from both views.${NC}"
                ;;
            5)
                vi "$RECORDS_DIR/db.$SEL_DOMAIN.world"
                vi "$RECORDS_DIR/db.$SEL_DOMAIN.iran"
                ;;
            6) break ;;
        esac
        # Reload BIND after any change
        docker exec shared_geodns rndc reload >/dev/null 2>&1
    done
}

case $CHOICE in
    1)
        echo "--> Installing GeoDNS Stack..."
        if ! command -v docker &> /dev/null; then echo -e "${RED}Error: Docker not found.${NC}"; exit 1; fi
        create_docker_compose
        create_base_config
        
        echo "--> Launching Container..."
        docker network create wp_shared_net 2>/dev/null || true
        cd "$BIND_DIR" && docker compose up -d --build
        
        register_dashboard
        
        echo -e "${GREEN}✅ GeoDNS active.${NC}"
        echo -e "Web UI available at: http://$(hostname -I | cut -d' ' -f1):1337"
        ;;
        
    2|3)
        if [ "$CHOICE" == "3" ]; then
            echo -e "\n${BLUE}>>> Existing Domains:${NC}"
            mapfile -t ZONES < <(grep 'zone "' "$CONFIG_DIR/named.conf.zones.world" | cut -d '"' -f 2)
            if [ ${#ZONES[@]} -eq 0 ]; then echo "No domains found."; exit 0; fi
            for i in "${!ZONES[@]}"; do
                DOMAIN="${ZONES[$i]}"
                CUR_W_IP=$(grep -E "@\s+IN\s+A" "$RECORDS_DIR/db.$DOMAIN.world" | awk '{print $NF}' | head -1)
                CUR_I_IP=$(grep -E "@\s+IN\s+A" "$RECORDS_DIR/db.$DOMAIN.iran" | awk '{print $NF}' | head -1)
                echo "$((i+1)). $DOMAIN (World: $CUR_W_IP, Iran: $CUR_I_IP)"
            done
            read -p "Select domain [1-${#ZONES[@]}]: " Z_NUM
            if [ -z "$Z_NUM" ]; then exit 0; fi
            DOMAIN="${ZONES[$((Z_NUM-1))]}"
            CUR_W_IP=$(grep -E "@\s+IN\s+A" "$RECORDS_DIR/db.$DOMAIN.world" | awk '{print $NF}' | head -1)
            CUR_I_IP=$(grep -E "@\s+IN\s+A" "$RECORDS_DIR/db.$DOMAIN.iran" | awk '{print $NF}' | head -1)
            read -p "World IP [$CUR_W_IP]: " W_IP; W_IP=${W_IP:-$CUR_W_IP}
            read -p "Iran IP [$CUR_I_IP]: " I_IP; I_IP=${I_IP:-$CUR_I_IP}
        else
            echo -e "\n${CYAN}--> Add New Domain Zone${NC}"
            DOMAIN=$2; W_IP=$3; I_IP=$4
            [ -z "$DOMAIN" ] && read -p "Domain Name: " DOMAIN
            [ -z "$W_IP" ] && read -p "International IP: " W_IP
            [ -z "$I_IP" ] && read -p "Iran IP: " I_IP
        fi
        MY_IP=$(curl -s ifconfig.me); NS_IP=${5:-$MY_IP}
        [ -z "$5" ] && [ -z "$ACTION" ] && read -p "DNS IP [$MY_IP]: " INPUT_IP && NS_IP=${INPUT_IP:-$MY_IP}
        generate_zone "$RECORDS_DIR/db.$DOMAIN.world" "$DOMAIN" "$W_IP" "$NS_IP"
        generate_zone "$RECORDS_DIR/db.$DOMAIN.iran" "$DOMAIN" "$I_IP" "$NS_IP"
        for view in world iran; do
            if ! grep -q "zone \"$DOMAIN\"" "$CONFIG_DIR/named.conf.zones.$view"; then
                echo -e "zone \"$DOMAIN\" {\n    type master;\n    file \"/var/lib/bind/db.$DOMAIN.$view\";\n};" >> "$CONFIG_DIR/named.conf.zones.$view"
            fi
        done
        chmod -R 777 "$BIND_DIR"; docker exec shared_geodns rndc reload
        echo -e "${GREEN}Configuration updated.${NC}"
        ;;

    4)
        manage_advanced_zone
        ;;
        
    5)
        echo "--> Refreshing Iran IP ACL..."
        update_iran_acl
        docker exec shared_geodns rndc reload
        echo -e "${GREEN}Done.${NC}"
        ;;
        
    6)
        echo "--> Restarting..."
        cd "$BIND_DIR" && docker compose restart
        ;;
        
    7)
        echo -e "\n${BLUE}>>> Container Status:${NC}"
        docker ps -f name=shared_geodns
        echo -e "\n${BLUE}>>> Recent Logs:${NC}"
        docker logs --tail 20 shared_geodns
        ;;
esac

echo ""
[ -z "$ACTION" ] && read -p "Press Enter to exit..."
