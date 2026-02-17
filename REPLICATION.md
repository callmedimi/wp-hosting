# Replication, Failover & Disaster Recovery

This document explains how to secure your data, set up multi-server replication, and handle disaster recovery scenarios.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Automated Local Backups](#automated-local-backups)
3. [Server-to-Server Replication](#server-to-server-replication)
4. [Replication Modes](#replication-modes)
5. [Disaster Recovery](#disaster-recovery)
6. [GeoDNS Integration](#geodns-integration)
7. [Troubleshooting](#troubleshooting)

---

## Overview

The WP-Hosting platform provides multiple layers of data protection:

- **Local Backups**: Automated daily backups on each server
- **Real-Time File Sync**: Syncthing for continuous file replication
- **Database Replication**: Automated database dumps and restoration
- **Multi-Mode Operation**: Active-Active, Active-Passive, or Cold Standby
- **GeoDNS Integration**: Automatic traffic routing to healthy servers

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    PRIMARY SERVER                       │
│  ┌──────────────┐         ┌──────────────────────────┐ │
│  │   Sites      │────────▶│   Syncthing              │ │
│  │   (Active)   │         │   (Real-time sync)       │ │
│  └──────────────┘         └──────────────────────────┘ │
│         │                           │                   │
│         ▼                           ▼                   │
│  ┌──────────────┐         ┌──────────────────────────┐ │
│  │  DB Dumps    │         │   Backups/               │ │
│  │  (Hourly)    │         │   (Daily rotation)       │ │
│  └──────────────┘         └──────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                              │
                              │ Syncthing
                              ▼
┌─────────────────────────────────────────────────────────┐
│                   REPLICA SERVER                        │
│  ┌──────────────┐         ┌──────────────────────────┐ │
│  │   Sites      │◀────────│   Auto-Sync Agent        │ │
│  │   (Standby)  │         │   (Every 30 mins)        │ │
│  └──────────────┘         └──────────────────────────┘ │
│         │                           │                   │
│         ▼                           ▼                   │
│  ┌──────────────┐         ┌──────────────────────────┐ │
│  │  DB Restore  │         │   User Creation          │ │
│  │  (Auto)      │         │   (Auto)                 │ │
│  └──────────────┘         └──────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

---

## Automated Local Backups

### What Gets Backed Up

The backup system (`scripts/rotate-backups.sh`) creates:

1. **Database Dumps**: `.sql` files for each WordPress site
2. **Site Archives**: Compressed `.tar.gz` of entire `sites/` folder
3. **Rotation**: Keeps last 7 days, deletes older backups

### Backup Location

```
/opt/wp-hosting/backups/
├── 2026-02-16/
│   ├── client1_db.sql
│   ├── client2_db.sql
│   └── sites_backup.tar.gz
├── 2026-02-15/
│   └── ...
└── 2026-02-14/
    └── ...
```

### Manual Backup

Run a backup immediately:

```bash
sudo ./scripts/rotate-backups.sh
```

### Automated Daily Backups

Enable automatic backups:

```bash
sudo ./manage.sh
# Select: 7. Replication, Failover & Backups Console
# Select: 8. Setup Daily Cron Job for Backups
```

This runs backups every day at 3 AM.

### Restoring from Local Backup

**Restore a database**:

```bash
# Find the backup
ls /opt/wp-hosting/backups/2026-02-16/

# Restore to container
docker exec -i client1_db mysql -u client1_user -p'password' client1_db < /opt/wp-hosting/backups/2026-02-16/client1_db.sql
```

**Restore files**:

```bash
# Extract backup
cd /opt/wp-hosting
tar -xzf backups/2026-02-16/sites_backup.tar.gz

# Fix permissions
sudo chown -R client1:client1 sites/client1/
```

---

## Server-to-Server Replication

### Prerequisites

- Two or more servers with WP-Hosting installed
- Network connectivity between servers
- Ports 22000 (Syncthing) and 21027 (Syncthing discovery) open

### Step 1: Pair the Servers

**On Server A (Primary)**:

```bash
sudo ./manage.sh
# Select: 7. Replication, Failover & Backups Console
# Select: 4. Setup/Manage Replication Pairing (Wizard)
```

The wizard will:
1. Show you Server A's Syncthing Device ID
2. Ask for Server B's Device ID
3. Configure the pairing

**On Server B (Replica)**:

```bash
sudo ./manage.sh
# Select: 7. Replication, Failover & Backups Console
# Select: 4. Setup/Manage Replication Pairing (Wizard)
```

The wizard will:
1. Show you Server B's Syncthing Device ID
2. Ask for Server A's Device ID
3. Configure the pairing

### Step 2: Approve the Connection

**Important**: Syncthing requires manual approval for security.

**On Server A**:
1. Open browser to `http://SERVER-A-IP:8384`
2. You'll see a notification: "New device wants to connect"
3. Click **Add Device**
4. Confirm

**On Server B**:
1. Open browser to `http://SERVER-B-IP:8384`
2. You'll see a notification: "New device wants to connect"
3. Click **Add Device**
4. Confirm

### Step 3: Share Folders

**On Server A** (via Syncthing Web UI):
1. Go to `http://SERVER-A-IP:8384`
2. Find the `sites` folder
3. Click **Edit**
4. Go to **Sharing** tab
5. Check the box for **Server B**
6. Click **Save**

**On Server B**:
1. Go to `http://SERVER-B-IP:8384`
2. You'll see: "Server A wants to share folder 'sites'"
3. Click **Add**
4. Confirm the folder path
5. Click **Save**

### Step 4: Configure Site Replication

For each site, configure how the replica should handle it:

```bash
sudo ./manage.sh
# Select: 7. Replication, Failover & Backups Console
# Select: 2. Configure Site Replication (Promote/Change Mode)
```

Select the site and choose a mode (see [Replication Modes](#replication-modes) below).

### Step 5: Enable Auto-Sync

**On the Replica Server**:

```bash
sudo ./manage.sh
# Select: 7. Replication, Failover & Backups Console
# Select: 6. Enable Auto-Sync Cron Job (Every 30m)
```

This enables the auto-sync agent that:
- Creates missing Linux users
- Restores databases
- Starts/stops containers based on mode
- Fixes file permissions

---

## Replication Modes

Each site has a replication mode defined in its `.env` file:

### Mode 1: Primary Node

```bash
REPLICATION_MODE=primary
PRIMARY_NODE=server-a
```

- **Behavior**: Site always runs on this server
- **Use Case**: The main production server
- **Containers**: Running
- **Database**: Active (writes allowed)

### Mode 2: Active Replica

```bash
REPLICATION_MODE=active
PRIMARY_NODE=server-a
```

- **Behavior**: Site runs on this server too
- **Use Case**: Active-Active setup with GeoDNS
- **Containers**: Running
- **Database**: Synced from primary (read-only recommended)
- **Best For**: Geo-distributed traffic (Iran vs. World)

### Mode 3: Passive Replica

```bash
REPLICATION_MODE=passive
PRIMARY_NODE=server-a
```

- **Behavior**: Files synced, containers stopped
- **Use Case**: Cold standby for disaster recovery
- **Containers**: Stopped
- **Database**: Synced but not loaded
- **Best For**: Cost-effective backup server

### Mode 4: Off

```bash
REPLICATION_MODE=off
PRIMARY_NODE=server-a
```

- **Behavior**: Site ignored on this server
- **Use Case**: Site doesn't belong here
- **Containers**: Removed
- **Files**: Deleted (if not primary)

### Changing Modes

```bash
sudo ./manage.sh
# Select: 7. Replication, Failover & Backups Console
# Select: 2. Configure Site Replication
# Select the site
# Choose new mode
```

The auto-sync agent will apply changes within 30 minutes, or run manually:

```bash
sudo ./scripts/auto-replica.sh
```

---

## Disaster Recovery

### Scenario 1: Primary Server Fails

**Symptoms**: Server A is down, clients can't access websites

**Recovery Steps**:

1. **Log into Server B** (Replica)

2. **Promote sites to primary**:
   ```bash
   sudo ./manage.sh
   # Select: 7. Replication, Failover & Backups Console
   # Select: 2. Configure Site Replication
   # Select each site
   # Choose: Promote to Primary
   ```

3. **Force immediate sync**:
   ```bash
   sudo ./scripts/auto-replica.sh
   ```

4. **Verify sites are running**:
   ```bash
   docker ps | grep _wp
   ```

5. **Update DNS**:
   - **Manual**: Update A records to point to Server B IP
   - **GeoDNS**: Automatically routes to healthy server

6. **Verify websites**:
   ```bash
   curl -I https://client1.com
   ```

**Time to Recovery**: 5-10 minutes (manual) or instant (with GeoDNS)

### Scenario 2: Database Corruption

**Symptoms**: Site shows database errors

**Recovery Steps**:

1. **Find latest backup**:
   ```bash
   ls -lh /opt/wp-hosting/backups/
   ```

2. **Restore database**:
   ```bash
   docker exec -i client1_db mysql -u client1_user -p'password' client1_db < /opt/wp-hosting/backups/2026-02-16/client1_db.sql
   ```

3. **Restart WordPress container**:
   ```bash
   docker restart client1_wp
   ```

4. **Verify**:
   ```bash
   curl https://client1.com
   ```

### Scenario 3: File Corruption

**Symptoms**: Theme files missing or corrupted

**Recovery Steps**:

1. **Check Syncthing**:
   - Go to `http://SERVER-IP:8384`
   - Verify sync status
   - Check for conflicts

2. **Restore from backup**:
   ```bash
   cd /opt/wp-hosting
   tar -xzf backups/2026-02-16/sites_backup.tar.gz sites/client1/
   sudo chown -R client1:client1 sites/client1/
   ```

3. **Or sync from replica**:
   - If replica has good files, reverse sync direction temporarily

### Scenario 4: Complete Server Loss

**Symptoms**: Server hardware failure, can't access server

**Recovery Steps**:

1. **Provision new server**

2. **Install WP-Hosting**:
   ```bash
   git clone https://github.com/aliqajarian/wp-hosting.git /opt/wp-hosting
   cd /opt/wp-hosting
   sudo ./manage.sh
   # Select: 1. Server Setup → 2. WORKER NODE
   ```

3. **Connect to existing replica**:
   ```bash
   sudo ./manage.sh
   # Select: 7. Replication, Failover & Backups Console
   # Select: 4. Setup/Manage Replication Pairing
   ```

4. **Wait for sync** (or restore from backup)

5. **Promote to primary** (if needed)

6. **Update DNS**

---

## GeoDNS Integration

### Active-Active with GeoDNS

Perfect for serving users from the nearest server:

**Setup**:

1. **Configure both servers as Active**:
   - Server A (EU): `REPLICATION_MODE=active`
   - Server B (Iran): `REPLICATION_MODE=active`

2. **Setup GeoDNS**:
   ```bash
   sudo ./scripts/setup-geodns.sh install
   ```

3. **Add domain**:
   ```bash
   sudo ./scripts/setup-geodns.sh add example.com SERVER-A-IP SERVER-B-IP
   ```

4. **Update registrar**:
   - Set nameservers to `ns1.example.com` and `ns2.example.com`

**Result**:
- Iranian users → Server B (low latency)
- International users → Server A (global CDN)
- Both servers serve live traffic
- Automatic failover if one server goes down

### Automatic Failover

GeoDNS can detect server health and route traffic accordingly:

1. **Enable health checks** in GeoDNS configuration
2. **Set up monitoring** with Uptime Kuma
3. **Configure automatic IP updates** based on health status

---

## Troubleshooting

### Files Not Syncing

**Check Syncthing status**:
```bash
# Via Web UI
http://SERVER-IP:8384

# Via CLI
docker logs shared_replication
```

**Common issues**:
- Firewall blocking port 22000
- Devices not paired
- Folder not shared
- Disk full

**Solutions**:
```bash
# Check firewall
sudo ufw status
sudo ufw allow 22000

# Restart Syncthing
docker restart shared_replication

# Check disk space
df -h
```

### Database Not Restoring

**Symptoms**: Auto-sync runs but database is empty

**Check**:
```bash
# Verify backup exists
ls -lh /opt/wp-hosting/sites/client1/backups/

# Check auto-sync logs
sudo ./scripts/auto-replica.sh
```

**Common issues**:
- No database dump file
- Incorrect database credentials
- Database container not running

**Solutions**:
```bash
# Manually create dump on primary
docker exec client1_db mysqldump -u client1_user -p'password' client1_db > /opt/wp-hosting/sites/client1/backups/db.sql

# Verify credentials
cat /opt/wp-hosting/sites/client1/.env | grep DB_

# Restart database
docker restart client1_db
```

### Containers Not Starting on Replica

**Symptoms**: Files synced but containers don't start

**Check**:
```bash
# View replication status
sudo ./manage.sh
# Select: 7 → 1 (View Replication Cluster Status)

# Check site .env
cat /opt/wp-hosting/sites/client1/.env | grep REPLICATION
```

**Common issues**:
- Mode set to `passive` or `off`
- User not created
- Permission errors

**Solutions**:
```bash
# Change mode to active
sudo ./manage.sh
# Select: 7 → 2 → Select site → Change mode to Active

# Force sync
sudo ./scripts/auto-replica.sh

# Check user exists
id client1

# Fix permissions
sudo chown -R client1:client1 /opt/wp-hosting/sites/client1/
```

### Sync Conflicts

**Symptoms**: Syncthing shows conflicts

**Check**:
```bash
# Via Web UI
http://SERVER-IP:8384
# Look for .sync-conflict files
```

**Resolution**:
1. Identify which version is correct
2. Delete conflict files
3. Keep the correct version
4. Syncthing will sync the resolution

---

## Best Practices

### 1. Regular Testing

- **Monthly**: Test failover procedure
- **Quarterly**: Full disaster recovery drill
- **After changes**: Verify replication still works

### 2. Monitoring

- Monitor Syncthing sync status
- Alert on backup failures
- Track replication lag

### 3. Documentation

- Document which server is primary for each site
- Keep DNS credentials accessible
- Maintain runbook for common scenarios

### 4. Backup Verification

- Regularly test backup restoration
- Verify backup file integrity
- Ensure backups are complete

### 5. Security

- Use SSH keys for server access
- Encrypt Syncthing connections (default)
- Restrict Syncthing Web UI access
- Keep backup credentials secure

---

## Quick Reference

### Common Commands

```bash
# Run backup now
sudo ./scripts/rotate-backups.sh

# Force sync now
sudo ./scripts/auto-replica.sh

# View replication status
sudo ./manage.sh → 7 → 1

# Change site mode
sudo ./manage.sh → 7 → 2

# Setup pairing
sudo ./manage.sh → 7 → 4

# Import replica sites
sudo ./manage.sh → 7 → 5

# Enable auto-sync cron
sudo ./manage.sh → 7 → 6
```

### Important Files

```
/opt/wp-hosting/sites/[site]/.env          # Replication config
/opt/wp-hosting/sites/[site]/backups/      # Database dumps
/opt/wp-hosting/backups/                   # Daily backups
/opt/wp-hosting/scripts/auto-replica.sh    # Sync agent
```

### Syncthing URLs

- **Server A**: `http://SERVER-A-IP:8384`
- **Server B**: `http://SERVER-B-IP:8384`

---

## Support

For replication issues:
1. Check Syncthing Web UI first
2. Review auto-sync logs
3. Verify .env configuration
4. Test manual sync
5. Check this documentation
