#!/bin/bash

# ==========================================
# ROTATE BACKUPS
# ==========================================
# 1. Calls backup-all-dbs.sh to get fresh SQL dumps
# 2. Compresses the sites/ folder (excluding node_modules/backups if desired, but here we keep full archive)
# 3. Rotates old backups (keeps last 7 days)

# Wait, the previous logic was that Syncthing handles the replication.
# So this script is mainly for:
# - Triggering the SQL dump so Syncthing has something to sync.
# - (Optional) Creating local tarballs for long-term storage (not synced).

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
BACKUP_ARCHIVE_DIR="$BASE_DIR/archives"

echo ">>> Starting Backup Rotation..."

# 1. Dump Databases & Create Per-Site Archives (stored in backup/<site>/)
if [ -f "$SCRIPTS_DIR/backup-site.sh" ]; then
    bash "$SCRIPTS_DIR/backup-site.sh" --all
else
    bash "$SCRIPTS_DIR/backup-all-dbs.sh"
fi

# 2. Ensure Archive Directory
mkdir -p "$BACKUP_ARCHIVE_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_FILE="$BACKUP_ARCHIVE_DIR/sites_backup_$TIMESTAMP.tar.gz"

echo "--> Archiving 'sites' folder..."
# We exclude the 'backups' folder inside sites to avoid large recursive archives if we run this often.
# But wait, we just put .sql files there. Let's include them.
# We exclude node_modules via shared volume logic (they are not in sites/ folder usually, they are mounted).
# Actually, node_modules is inside container, but shared volume content? 
# The shared node_modules is a volume.
# Let's just tar the sites directory.

tar -czf "$ARCHIVE_FILE" -C "$BASE_DIR" sites

echo "    Created: $ARCHIVE_FILE"

# 3. Rotate Old Archives (Keep 7)
echo "--> Cleaning old archives (Keep 7)..."
ls -tp "$BACKUP_ARCHIVE_DIR"/sites_backup_*.tar.gz | grep -v '/$' | tail -n +8 | xargs -I {} rm -- {}

echo ">>> Backup Rotation Complete."
