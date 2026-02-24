#!/bin/bash

# ==========================================
# IMPORT SITES (For Replica Server)
# ==========================================
# This script is meant to be run on SERVER B (The Replica).
# It assumes Syncthing has already copied the 'sites/' folder structure.
# But permissions (UID/GID) might be wrong, or users might not exist.
# This script:
# 1. Finds all synced sites.
# 2. Creates the missing users on Server B.
# 3. Ensures UIDs match what's in .env (if possible) or fixes .env to match local UID.
# 4. Fixes file ownership.

SITES_DIR="/opt/wp-hosting/sites"

echo ">>> Starting Site Import / Permission Fix..."

if [ ! -d "$SITES_DIR" ]; then
    echo "ERROR: Sites directory not found. Did Syncthing run?"
    exit 1
fi

# Loop through each site folder
for SITE_PATH in "$SITES_DIR"/*; do
    if [ -d "$SITE_PATH" ]; then
        SITE_NAME=$(basename "$SITE_PATH")
        ENV_FILE="$SITE_PATH/.env"

        echo "--> Processing: $SITE_NAME"

        if [ -f "$ENV_FILE" ]; then
            # Extract credentials from .env
            SITE_USER=$(grep "^SYS_USER=" "$ENV_FILE" | cut -d'=' -f2)
            SITE_USER=${SITE_USER:-$SITE_NAME}
            SITE_PASS=$(grep "^SYS_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2)

            # Check if user exists
            if id "$SITE_USER" &>/dev/null; then
                echo "    User $SITE_USER exists. Updating home directory..."
                usermod -d "$SITE_PATH" -s /usr/sbin/nologin "$SITE_USER"
            else
                echo "    Creating user $SITE_USER..."
                useradd -d "$SITE_PATH" -M -s /usr/sbin/nologin "$SITE_USER"
            fi
            
            # Set password if found
            if [ ! -z "$SITE_PASS" ]; then
                echo "$SITE_USER:$SITE_PASS" | chpasswd
                echo "    Password updated for $SITE_USER."
            fi
            
            # Get local UID/GID
            NEW_UID=$(id -u "$SITE_USER")
            NEW_GID=$(id -g "$SITE_USER")
            
            # Update .env to match THIS server's UID/GID
            # This is crucial because UID 1001 on Server A might be UID 1002 on Server B.
            # We must update the .env file so the container runs as the LOCAL user.
            sed -i "s/^SYS_UID=.*/SYS_UID=$NEW_UID/" "$ENV_FILE"
            sed -i "s/^SYS_GID=.*/SYS_GID=$NEW_GID/" "$ENV_FILE"
            
            echo "    Updated .env with UID: $NEW_UID"

            # Fix File Ownership
            # Syncthing might have synced files as root or 'syncthing' user.
            # We force them to be owned by the site user.
            chown -R "$SITE_USER:$SITE_USER" "$SITE_PATH"
            echo "    Fixed file permissions."
            
            # Start/Restart Containers to pick up new UID
            # Optional: Uncomment if you want to auto-start everything
            # cd "$SITE_PATH" && docker compose up -d
            
        else
            echo "    [SKIP] No .env file found (incomplete sync?)"
        fi
    fi
done

echo ">>> Import Complete."
