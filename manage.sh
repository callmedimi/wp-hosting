#!/bin/bash

# ==============================================================================
# WP-HOSTING MANAGER
# ==============================================================================
# A comprehensive tool to install, manage, and monitor your Multi-Site Docker stack.
# Usage: sudo ./manage.sh

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BASE_DIR="/opt/wp-hosting"
CURRENT_DIR=$(dirname "$0")

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Run ./setup-ubuntu.sh first."
    exit 1
fi

show_header() {
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}   WP-HOSTING MANAGER (Multi-Server Edition)   ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo "Current Server: $(hostname) ($(hostname -I | cut -d' ' -f1))"
    echo ""
}

# 1. Setup Host
menu_install() {
    echo -e "${GREEN}>>> Server Initialization Role${NC}"
    echo "This script configures the base infrastructure."
    echo ""
    echo "1. MANAGER NODE (Runs Dashboard + Sites + Agents)"
    echo "   - Choose this for your PRIMARY VPS (e.g. VPS 1)."
    echo "   - It will host the central control panel."
    echo ""
    echo "2. WORKER NODE (Runs Sites + Agents only)"
    echo "   - Choose this for VPS 2, VPS 3, etc."
    echo "   - It connects back to the Manager via Portainer Agent."
    echo ""
    read -p "Select Role [1-2]: " ROLE
    
    if [ "$ROLE" == "1" ]; then
        bash ./setup-ubuntu.sh "manager"
        echo ""
        echo -e "${CYAN}TIP: Now log in to Portainer (http://$(hostname -I | cut -d' ' -f1):9000) and create your 'admin' user!${NC}"
    else
        bash ./setup-ubuntu.sh "node"
    fi
    # Create Node ID if missing
    if [ ! -f "$CURRENT_DIR/node_id" ]; then
        hostname > "$CURRENT_DIR/node_id"
    fi
    read -p "Press Enter to continue..."
}

# 2. Add Worker Node
menu_add_worker() {
    echo -e "${GREEN}>>> Add Remote Worker Node (Manager Only)${NC}"
    if [ ! -f "$CURRENT_DIR/shared/homepage/services.yaml" ]; then
        echo -e "${RED}Error: This server does not seem to be a Manager Node (Homepage config missing).${NC}"
        read -p "Press Enter..."
        return
    fi
    
    echo "This will connect a remote VPS to your Dashboard (Netdata + Portainer)."
    echo ""
    read -p "Enter Node Name (e.g., VPS-2): " N_NAME
    read -p "Enter Node IP (e.g., 192.168.1.50): " N_IP
    echo ""
    echo "To connect Portainer, we need your Portainer Admin credentials."
    read -p "Portainer Username (default: admin): " P_USER
    P_USER=${P_USER:-admin}
    read -s -p "Portainer Password: " P_PASS
    echo ""
    
    bash ./scripts/add-node.sh "$N_NAME" "$N_IP" "$P_USER" "$P_PASS"
    read -p "Press Enter to continue..."
}

# 3. Create Site
menu_create_site() {
    echo -e "${GREEN}>>> Create New WordPress Site${NC}"
    read -p "Enter Site Name (folder name, e.g., client1): " SITE_NAME
    read -p "Enter Domain Name (e.g., client1.com): " DOMAIN_NAME
    read -s -p "Enter SFTP Password for System User ($SITE_NAME): " SITE_PASS
    echo "" 
    
    bash ./create-site.sh "$SITE_NAME" "$DOMAIN_NAME" "$SITE_NAME" "$SITE_PASS"
    read -p "Press Enter to continue..."
}

# 4. List Sites
menu_list_sites() {
    echo -e "${GREEN}>>> Active Local Sites${NC}"
    echo "Running Services:"
    printf "%-20s %-30s %-15s\n" "FOLDER" "URL" "STATUS"
    echo "----------------------------------------------------------------"
    
    if [ -d "$CURRENT_DIR/sites" ]; then
        for d in "$CURRENT_DIR/sites"/*/; do
             if [ -f "${d}docker-compose.yml" ]; then
                FOLDER=$(basename "$d")
                DOMAIN=$(grep "DOMAIN_NAME=" "${d}.env" | cut -d '=' -f2 | tr -d '\r')
                if docker ps --format '{{.Names}}' | grep -q "${FOLDER}_wp"; then
                    STATUS="${GREEN}RUNNING${NC}"
                else
                    STATUS="${RED}STOPPED${NC}"
                fi
                printf "%-20s %-30s %b\n" "$FOLDER" "$DOMAIN" "$STATUS"
             fi
        done
    else
        echo "No sites directory found."
    fi
    echo ""
    read -p "Press Enter to continue..."
}

# 5. Access Site Tools
menu_access_tools() {
    echo -e "${GREEN}>>> Access & Manage Site Tools${NC}"
    echo "Available Sites:"
    if [ -d "$CURRENT_DIR/sites" ]; then
         ls "$CURRENT_DIR/sites"
    else
         echo "No sites found."
         return
    fi
    echo ""
    read -p "Enter Site Name: " SITE_NAME
    
    if [ ! -d "$CURRENT_DIR/sites/$SITE_NAME" ]; then
        echo "Site not found."
        return
    fi
    
    echo ""
    echo "--- SERVICE CONTROL ---"
    echo "1. Start Site"
    echo "2. Stop Site"
    echo "3. Restart Site"
    echo "4. View Live Logs (Targeting WordPress)"
    echo "5. Fix Permissions (chown 1001:1001)"
    echo ""
    echo "--- TERMINAL ACCESS ---"
    echo "6. Shell: WordPress Container (Run 'wp', 'ls')"
    echo "7. Shell: Database Container (Run 'mysql')"
    echo ""
    echo "--- ADVANCED ---"
    echo "9. Localize Google Fonts (Download Vazirmatn...)"
    echo "10. View Credentials (DB/SFTP)"
    echo "11. Quick Replication Setup (Change Primary/Mode)"
    echo "12. DELETE SITE (Permanent)"
    
    read -p "Select Tool [1-12]: " TOOL_OPT
    
    case $TOOL_OPT in
        1) cd "$CURRENT_DIR/sites/$SITE_NAME" && docker compose up -d ;;
        2) cd "$CURRENT_DIR/sites/$SITE_NAME" && docker compose stop ;;
        3) cd "$CURRENT_DIR/sites/$SITE_NAME" && docker compose restart ;;
        4) 
            if docker ps -a --format '{{.Names}}' | grep -q "^${SITE_NAME}_wp$"; then
                echo ">>> Opening logs for ${SITE_NAME}_wp (Press Ctrl+C to exit)..."
                docker logs -f --tail=100 "${SITE_NAME}_wp"
            else
                echo -e "${RED}[ERROR] Container ${SITE_NAME}_wp not found.${NC}"
                echo "Please ensure the site is created and started first."
            fi
            ;;
        5) 
            echo "Applying chown -R 1001:1001 to sites/$SITE_NAME..."
            chown -R 1001:1001 "$CURRENT_DIR/sites/$SITE_NAME"
            echo "Permissions fixed."
            ;;
        6) docker exec -it "${SITE_NAME}_wp" bash ;;
        7) docker exec -it "${SITE_NAME}_db" bash ;;
        9) 
            echo ""
            echo "Common Fonts:"
            echo "  1. Vazirmatn (Persian) - All weights"
            echo "  2. Custom URL"
            read -p "Select [1-2]: " FOPT
            if [ "$FOPT" == "1" ]; then
                FURL="https://fonts.googleapis.com/css2?family=Vazirmatn:wght@100..900&display=swap"
            else
                read -p "Enter Google Fonts CSS URL: " FURL
            fi
            bash ./scripts/localize-font.sh "$SITE_NAME" "$FURL" 
            ;;
        10)
            echo ""
            cat "$CURRENT_DIR/sites/$SITE_NAME/.env"
            echo ""
            ;;
        11)
            bash ./scripts/manage-replication.sh "$SITE_NAME"
            ;;
        12)
            bash ./scripts/delete-site.sh "$SITE_NAME"
            ;;
    esac
    read -p "Press Enter to continue..."
}

# 6. Manage Stack
menu_manage_stack() {
    echo -e "${GREEN}>>> Manage Local Server Stack${NC}"
    echo "1. Start/Restart Base Stack (Gateway, Agents, Files)"
    echo "2. Start/Restart Manager Dashboard Stack"
    echo "3. Stop Everything"
    echo "4. Show Node Connection Info"
    echo "5. Run Cluster Health Check (NEW)"
    read -p "Select: " MOPT
    
    cd "$CURRENT_DIR/shared"
    case $MOPT in
        1) docker compose -f docker-compose.yml up -d ;;
        2) docker compose -f docker-compose-central.yml up -d ;;
        3) docker compose -f docker-compose.yml down && docker compose -f docker-compose-central.yml down ;;
        4)
            IP=$(hostname -I | cut -d' ' -f1)
            echo "=========================================="
            echo "NODE CONNECTION INFO"
            echo "Add this node to your Manager at:"
            echo "Name: $(hostname)"
            echo "URL:  $IP:9001"
            echo "=========================================="
            ;;
        5) 
            bash ./scripts/check-health.sh 
            ;;
    esac
    read -p "Press Enter to continue..."
}

# 7. Replication Failover
menu_replication() {
    echo -e "${GREEN}>>> Replication, Failover & Backups${NC}"
    echo "1. View Replication Cluster Status (ALL SITES)"
    echo "2. Configure Site Replication (Promote/Change Mode)"
    echo "3. Trigger Auto-Sync Agent (Re-apply Rules NOW)"
    echo "--------------------------------------------------------"
    echo "4. Setup/Manage Replication Pairing (Wizard)"
    echo "5. Import/Restore Replica Sites (Full Manual Hydration)"
    echo "6. Enable Auto-Sync Cron Job (Every 30m)"
    echo "--------------------------------------------------------"
    echo "7. Run Local Backup Rotation (Dumps SQL + Archives)"
    echo "8. Setup Daily Cron Job for Backups"
    
    read -p "Select: " RO
    
    case $RO in
        1) bash ./scripts/list-replication-status.sh ;;
        2) 
            read -p "Enter Site Name: " SITE_NAME
            bash ./scripts/manage-replication.sh "$SITE_NAME"
            echo "[INFO] Running Auto-Sync to apply changes..."
            bash ./scripts/auto-replica.sh
            ;;
        3) 
            echo "[INFO] Running Auto-Sync Agent..."
            bash ./scripts/auto-replica.sh
            ;;
        4) bash ./scripts/replication-wizard.sh ;;
        5) 
            bash ./scripts/import-replica.sh
            bash ./scripts/restore-sites.sh
            ;;
        6) 
            echo "Enabling Auto-Sync Agent (Runs every 30 mins)..."
            (crontab -l 2>/dev/null; echo "*/30 * * * * $CURRENT_DIR/scripts/auto-replica.sh >> /var/log/wp-replica-sync.log 2>&1") | crontab -
            echo "Done."
            ;;
        7) bash ./scripts/rotate-backups.sh ;;
        8) 
            (crontab -l 2>/dev/null; echo "0 3 * * * $CURRENT_DIR/scripts/rotate-backups.sh >> /var/log/wp-backups.log 2>&1") | crontab -
            echo "Cron added."
            ;;
    esac
    read -p "Press Enter to continue..."
}

# 8. GeoDNS
menu_geodns() {
    echo -e "${GREEN}>>> GeoDNS & Traffic Management${NC}"
    echo "1. Install/Update GeoDNS Server (BIND9)"
    echo "   - Configures THIS server as the DNS Authority."
    echo "   - Routes 'Iran' IPs -> Replica, 'World' -> Main."
    echo "   - Use this on your Main or Replica server (your choice)."
    
    read -p "Select: " GDOS
    if [ "$GDOS" == "1" ]; then
        bash ./scripts/setup-geodns.sh
    fi
     read -p "Press Enter to continue..."
}

# Main Loop
while true; do
    show_header
    echo "1. Server Setup (Manager vs Worker Role)"
    echo "2. Add Remote Worker Node (Manager Only - Central Monitoring)"
    echo "3. Create New Site"
    echo "4. DELETE A SITE (Safe Cleanup)"
    echo "5. List Local Sites (Simple)"
    echo "6. Access Site Tools (Shell, Logs, Fonts, Creds)"
    echo "7. Manage Server Stack"
    echo "8. Replication, Failover & Backups Console"
    echo "9. GeoDNS & Traffic Management"
    echo "10. Update/Refresh All Sites (Apply Template & Optimizations)"
    echo "11. Migrate Existing Site (Import Files & SQL)"
    echo "12. Exit"
    echo ""
    read -p "Choose Option [1-12]: " CHOICE
    
    case $CHOICE in
        1) menu_install ;;
        2) menu_add_worker ;;
        3) menu_create_site ;;
        4) 
            read -p "Enter Site Name to DELETE: " D_SITE
            bash ./scripts/delete-site.sh "$D_SITE"
            ;;
        5) menu_list_sites ;;
        6) menu_access_tools ;;
        7) menu_manage_stack ;;
        8) menu_replication ;;
        9) menu_geodns ;;
        10) bash ./scripts/refresh-sites.sh ;;
        11) bash ./scripts/migrate-site.sh ;;
        12) exit 0 ;;
        *) echo "Invalid option." ;;
    esac
done
