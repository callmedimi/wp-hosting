# GeoDNS Management System - Complete Guide

## 📋 Table of Contents
1. [Overview](#overview)
2. [Installation](#installation)
3. [Web UI Tutorial](#web-ui-tutorial)
4. [CLI Reference](#cli-reference)
5. [Advanced Zone Management](#advanced-zone-management)
6. [Nameserver Configuration](#nameserver-configuration)
7. [Troubleshooting](#troubleshooting)

---

## Overview

The **GeoDNS Management System** is a comprehensive DNS solution built on BIND9 that enables intelligent traffic routing based on geographic location. It's specifically optimized for routing Iranian traffic to local servers while directing international traffic to global servers.

### Key Features

- **Geo-Location Routing**: Automatically route Iran-based users to domestic servers and international users to global servers
- **Web-Based Management**: Full-featured web UI for managing DNS zones without SSH access
- **CLI Tools**: Powerful command-line interface for automation and advanced users
- **Advanced Record Management**: Support for A, CNAME, MX, TXT, and NS records
- **Split-View Configuration**: Different DNS responses for Iran vs. World traffic
- **Dashboard Integration**: Seamlessly integrates with your central management dashboard

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                  GeoDNS Server                      │
│  ┌──────────────┐         ┌──────────────────────┐ │
│  │   BIND9      │◄────────┤   Web UI (OliveTin)  │ │
│  │  Container   │         │   Port: 1337         │ │
│  │  Port: 53    │         └──────────────────────┘ │
│  └──────────────┘                                   │
│         │                                           │
│         ▼                                           │
│  ┌──────────────────────────────────────────────┐  │
│  │  Zone Files (Iran View / World View)        │  │
│  │  - db.example.com.iran                       │  │
│  │  - db.example.com.world                      │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## Installation

### Prerequisites

- Ubuntu 20.04+ or similar Linux distribution
- Docker and Docker Compose installed
- Root or sudo access
- At least 512MB RAM available
- Port 53 (UDP/TCP) and 1337 available

### Quick Install

#### Option 1: During Server Setup

When running the main setup script, you'll be prompted to install GeoDNS:

```bash
cd /opt/wp-hosting
sudo ./setup-ubuntu.sh
# Answer "y" when asked: "Do you want to install BIND9 GeoDNS on this server?"
```

#### Option 2: Standalone Installation

Install GeoDNS on any server at any time:

```bash
cd /opt/wp-hosting
sudo ./scripts/setup-geodns.sh install
```

Or use the management console:

```bash
sudo ./manage.sh
# Select: 8. GeoDNS & Traffic Management
# Select: 1. Install/Update GeoDNS Server
```

### What Gets Installed

The installation process:

1. **Creates directory structure**:
   ```
   /opt/wp-hosting/shared/bind9/
   ├── config/           # BIND9 configuration files
   ├── records/          # DNS zone files
   ├── cache/            # BIND9 cache directory
   ├── docker-compose.yml
   ├── Dockerfile.ui     # Custom OliveTin image
   └── config/olivetin.yaml
   ```

2. **Downloads Iran IP ranges** from GitHub (updated CIDR blocks)

3. **Launches two containers**:
   - `shared_geodns` - BIND9 DNS server
   - `shared_geodns_ui` - Web management interface

4. **Registers with dashboard** (if on Manager node)

### Post-Installation

After installation completes, you'll see:

```
✅ GeoDNS active.
Web UI available at: http://YOUR-SERVER-IP:1337
```

Access the Web UI immediately to verify installation.

---

## Web UI Tutorial

### Accessing the Web UI

1. **Direct Access**: Navigate to `http://YOUR-SERVER-IP:1337`
2. **Via Dashboard**: If on a Manager node, click "GeoDNS Manager" widget

### Dashboard Overview

The Web UI provides six main actions:

```
┌─────────────────────────────────────────────────┐
│  🔄 Restart DNS Service                         │
│  📋 List Domains & IPs                          │
│  ➕ Add New Domain                              │
│  ✏️  Quick Update Domain IP                     │
│  🔃 Refresh Iran IP Lists                       │
│  📊 View Logs                                   │
└─────────────────────────────────────────────────┘
```

### Tutorial: Adding Your First Domain

#### Step 1: Add New Domain

1. Click **"Add New Domain"** button
2. Fill in the form:
   - **Domain Name**: `example.com` (without www)
   - **World IP**: `185.123.45.67` (Your international server IP)
   - **Iran IP**: `5.78.90.123` (Your Iran-based server IP)
3. Click **"Execute"**

The system will:
- Generate zone files for both views
- Configure NS records (ns1.example.com, ns2.example.com)
- Add glue records pointing to this DNS server
- Reload BIND9 automatically

#### Step 2: Configure Your Domain Registrar

After adding the domain, you must update your domain registrar:

**At Namecheap/GoDaddy/etc:**

1. Go to Domain Management
2. Select "Custom DNS" or "Custom Nameservers"
3. Add these nameservers:
   - `ns1.example.com` → `YOUR-DNS-SERVER-IP`
   - `ns2.example.com` → `YOUR-DNS-SERVER-IP`

**Important**: You must add **glue records** (A records for the nameservers) at your registrar since the nameservers are subdomains of the domain itself.

#### Step 3: Verify DNS Propagation

Wait 5-60 minutes for DNS propagation, then test:

```bash
# Test from Iran (should return Iran IP)
dig @YOUR-DNS-SERVER-IP example.com

# Test from outside Iran (should return World IP)
dig @8.8.8.8 example.com
```

### Tutorial: Updating Domain IPs

If you migrate servers or change IPs:

1. Click **"Quick Update Domain IP"**
2. Enter:
   - **Existing Domain**: `example.com`
   - **New World IP**: `185.200.100.50`
   - **New Iran IP**: `5.90.80.70`
3. Click **"Execute"**

Changes take effect immediately (no registrar update needed).

### Tutorial: Managing Multiple Domains

#### List All Domains

Click **"List Domains & IPs"** to see:

```
example.com (World: 185.123.45.67)
shop.example.com (World: 185.123.45.68)
blog.example.com (World: 185.123.45.69)
```

This helps you audit your DNS configuration at a glance.

#### Bulk Operations

For managing many domains, use the CLI (see below) or the Advanced Zone Management menu.

---

## CLI Reference

### Basic Commands

```bash
# Full installation
sudo ./scripts/setup-geodns.sh install

# Add a domain (non-interactive)
sudo ./scripts/setup-geodns.sh add example.com 185.1.2.3 5.4.3.2

# Modify existing domain IPs
sudo ./scripts/setup-geodns.sh modify

# Advanced zone management
sudo ./scripts/setup-geodns.sh manage

# Refresh Iran IP lists
sudo ./scripts/setup-geodns.sh refresh

# Restart DNS service
sudo ./scripts/setup-geodns.sh restart

# Check status and logs
sudo ./scripts/setup-geodns.sh status
```

### Interactive Menu

Run without arguments for the full menu:

```bash
sudo ./scripts/setup-geodns.sh
```

You'll see:

```
======================================================
        GeoDNS MANAGER (BIND9 + Docker)       
======================================================

1. Full Installation (Any Server Role)
2. Add a New Domain Zone
3. Quick Modify Domain IPs
4. Advanced Zone Management (Records: MX, TXT, CNAME...)
5. Refresh Iran IP Lists
6. Restart DNS Container
7. Show Status & Logs

Select Option [1-7]:
```

### Automation Examples

#### Add Multiple Domains

```bash
#!/bin/bash
DOMAINS=(
  "example.com 185.1.2.3 5.4.3.2"
  "shop.com 185.1.2.4 5.4.3.3"
  "blog.com 185.1.2.5 5.4.3.4"
)

for domain_config in "${DOMAINS[@]}"; do
  sudo ./scripts/setup-geodns.sh add $domain_config
done
```

#### Scheduled IP List Updates

Add to crontab to refresh Iran IP ranges weekly:

```bash
# Refresh Iran IP lists every Sunday at 3 AM
0 3 * * 0 /opt/wp-hosting/scripts/setup-geodns.sh refresh >> /var/log/geodns-refresh.log 2>&1
```

---

## Advanced Zone Management

### Accessing Advanced Management

**Via CLI:**
```bash
sudo ./scripts/setup-geodns.sh manage
```

**Via Web UI:**
Not available in Web UI - use CLI for advanced features.

### Menu Overview

```
Managing: example.com

1. List All Records
2. Add Custom Record
3. Add Nameserver (NS + Glue)
4. Delete Custom Record
5. Manual Edit (vi)
6. Back
```

### Adding Custom Records

#### A Record (Subdomain)

**Use Case**: Point `mail.example.com` to a specific server

1. Select **"2. Add Custom Record"**
2. Choose view:
   - `1` = World Only
   - `2` = Iran Only
   - `3` = Both
3. Enter:
   - **Record Name**: `mail`
   - **Type**: `A`
   - **Value**: `185.10.20.30`

Result in zone file:
```
mail    IN  A    185.10.20.30
```

#### CNAME Record (Alias)

**Use Case**: Make `www.example.com` point to `example.com`

1. Select **"2. Add Custom Record"**
2. Choose view: `3` (Both)
3. Enter:
   - **Record Name**: `www`
   - **Type**: `CNAME`
   - **Value**: `example.com.` (note the trailing dot)

Result:
```
www     IN  CNAME    example.com.
```

#### MX Record (Mail Server)

**Use Case**: Configure email delivery for your domain

1. Select **"2. Add Custom Record"**
2. Choose view: `3` (Both)
3. Enter:
   - **Record Name**: `@` (for root domain)
   - **Type**: `MX`
   - **Value**: `mail.example.com.`
   - **Priority**: `10`

Result:
```
@       IN  MX    10 mail.example.com.
```

For multiple mail servers:
```
@       IN  MX    10 mail1.example.com.
@       IN  MX    20 mail2.example.com.
```

#### TXT Record (SPF, DKIM, Verification)

**Use Case**: Add SPF record for email authentication

1. Select **"2. Add Custom Record"**
2. Choose view: `3` (Both)
3. Enter:
   - **Record Name**: `@`
   - **Type**: `TXT`
   - **Value**: `"v=spf1 mx ~all"`

Result:
```
@       IN  TXT    "v=spf1 mx ~all"
```

**Common TXT Records:**

```bash
# Google Site Verification
@       IN  TXT    "google-site-verification=ABC123..."

# DKIM
default._domainkey  IN  TXT  "v=DKIM1; k=rsa; p=MIGfMA0GCS..."

# DMARC
_dmarc  IN  TXT    "v=DMARC1; p=quarantine; rua=mailto:admin@example.com"
```

### Split-View Configuration

**Use Case**: Different mail servers for Iran vs. World

**Iran View** (mail.ir-server.com):
```bash
# Select view: 2 (Iran Only)
Record Name: @
Type: MX
Value: mail.ir-server.com.
Priority: 10
```

**World View** (mail.eu-server.com):
```bash
# Select view: 1 (World Only)
Record Name: @
Type: MX
Value: mail.eu-server.com.
Priority: 10
```

Now Iranian users will send email through the Iran server, while international users use the EU server.

### Deleting Records

1. Select **"4. Delete Custom Record"**
2. Enter a unique pattern from the record line
   - Example: To delete `mail.example.com`, enter `mail`
   - Example: To delete specific MX, enter `mail1.example.com`
3. Confirm

**Warning**: This deletes from BOTH views. Be specific with your pattern.

### Manual Editing

For power users who want direct control:

1. Select **"5. Manual Edit (vi)"**
2. Edit `db.example.com.world` first
3. Save and exit
4. Edit `db.example.com.iran`
5. Save and exit

BIND9 automatically reloads after you exit.

**Zone File Format:**
```
$TTL 3600
@   IN  SOA ns1.example.com. admin.example.com. (
        2026021601 ; Serial (YYYYMMDDNN)
        3600       ; Refresh
        1800       ; Retry
        604800     ; Expire
        86400 )    ; Minimum TTL

; Nameservers
@       IN  NS      ns1.example.com.
@       IN  NS      ns2.example.com.

; A Records
@       IN  A       185.1.2.3
www     IN  A       185.1.2.3
mail    IN  A       185.1.2.4

; MX Records
@       IN  MX      10 mail.example.com.

; TXT Records
@       IN  TXT     "v=spf1 mx ~all"

; NS Glue Records
ns1     IN  A       YOUR-DNS-SERVER-IP
ns2     IN  A       YOUR-DNS-SERVER-IP
```

---

## Nameserver Configuration

### Adding Additional Nameservers

**Use Case**: Add `ns3.example.com` as a third nameserver

1. Go to **Advanced Zone Management**
2. Select your domain
3. Choose **"3. Add Nameserver (NS + Glue)"**
4. Enter:
   - **Nameserver Hostname**: `ns3`
   - **Nameserver IP**: `185.50.60.70`

This automatically adds:
```
@       IN  NS      ns3.example.com.
ns3     IN  A       185.50.60.70
```

### Delegating Subdomains

**Use Case**: Delegate `api.example.com` to another DNS server

1. Select **"2. Add Custom Record"**
2. Enter:
   - **Record Name**: `api`
   - **Type**: `NS`
   - **Value**: `ns1.api-provider.com.`

Then add the glue record if needed:
```
api     IN  NS      ns1.api-provider.com.
```

### Best Practices

1. **Always use at least 2 nameservers** for redundancy
2. **Use different IPs** for ns1 and ns2 if possible
3. **Keep glue records updated** when changing server IPs
4. **Test with `dig`** before updating registrar

---

## Troubleshooting

### DNS Not Resolving

**Symptom**: `dig @YOUR-SERVER-IP example.com` returns no answer

**Solutions**:

1. **Check if BIND9 is running**:
   ```bash
   docker ps | grep shared_geodns
   ```

2. **View BIND9 logs**:
   ```bash
   docker logs shared_geodns
   # Or via Web UI: Click "View Logs"
   ```

3. **Verify zone files exist**:
   ```bash
   ls -la /opt/wp-hosting/shared/bind9/records/
   ```

4. **Check for syntax errors**:
   ```bash
   docker exec shared_geodns named-checkzone example.com /var/lib/bind/db.example.com.world
   ```

5. **Restart DNS service**:
   ```bash
   ./scripts/setup-geodns.sh restart
   ```

### Wrong IP Returned

**Symptom**: Iranian users get World IP or vice versa

**Solutions**:

1. **Verify Iran IP lists are current**:
   ```bash
   ./scripts/setup-geodns.sh refresh
   ```

2. **Check which view is matching**:
   ```bash
   docker exec shared_geodns rndc querylog
   # Then query the domain and check logs
   docker logs shared_geodns | tail -20
   ```

3. **Test from specific IP**:
   ```bash
   # Simulate query from Iran IP
   dig @YOUR-SERVER-IP example.com +subnet=5.1.1.1/32
   ```

### Web UI Not Accessible

**Symptom**: Cannot access `http://SERVER-IP:1337`

**Solutions**:

1. **Check if container is running**:
   ```bash
   docker ps | grep shared_geodns_ui
   ```

2. **Verify port is open**:
   ```bash
   sudo netstat -tulpn | grep 1337
   ```

3. **Check firewall**:
   ```bash
   sudo ufw status
   # If port 1337 is blocked:
   sudo ufw allow 1337/tcp
   ```

4. **Rebuild UI container**:
   ```bash
   cd /opt/wp-hosting/shared/bind9
   docker compose up -d --build dns_ui
   ```

### Changes Not Taking Effect

**Symptom**: Updated records but still seeing old values

**Solutions**:

1. **Force BIND reload**:
   ```bash
   docker exec shared_geodns rndc reload
   ```

2. **Check serial number** in zone file (must increment):
   ```bash
   grep Serial /opt/wp-hosting/shared/bind9/records/db.example.com.world
   ```

3. **Clear DNS cache** on client:
   ```bash
   # Linux
   sudo systemd-resolve --flush-caches
   
   # macOS
   sudo dscacheutil -flushcache
   
   # Windows
   ipconfig /flushdns
   ```

4. **Wait for TTL expiration** (default: 3600 seconds = 1 hour)

### Permission Errors

**Symptom**: "Permission denied" when modifying zone files

**Solutions**:

```bash
# Fix permissions
sudo chmod -R 777 /opt/wp-hosting/shared/bind9/records
sudo chmod -R 777 /opt/wp-hosting/shared/bind9/config
```

### Container Won't Start

**Symptom**: `docker compose up` fails

**Solutions**:

1. **Check Docker logs**:
   ```bash
   cd /opt/wp-hosting/shared/bind9
   docker compose logs
   ```

2. **Verify network exists**:
   ```bash
   docker network ls | grep wp_shared_net
   # If missing:
   docker network create wp_shared_net
   ```

3. **Check for port conflicts**:
   ```bash
   sudo lsof -i :53
   # If another service is using port 53, stop it
   ```

4. **Rebuild from scratch**:
   ```bash
   cd /opt/wp-hosting/shared/bind9
   docker compose down
   docker compose up -d --build
   ```

---

## Advanced Topics

### Monitoring DNS Queries

Enable query logging:

```bash
docker exec shared_geodns rndc querylog on
docker logs -f shared_geodns
```

### Performance Tuning

For high-traffic domains, edit `/opt/wp-hosting/shared/bind9/config/named.conf`:

```
options {
    directory "/var/cache/bind";
    recursion no;
    allow-query { any; };
    allow-transfer { none; };
    listen-on { any; };
    listen-on-v6 { any; };
    
    # Performance tuning
    max-cache-size 256M;
    clients-per-query 10;
    max-clients-per-query 100;
};
```

Then restart:
```bash
docker restart shared_geodns
```

### Backup and Restore

**Backup**:
```bash
tar -czf geodns-backup-$(date +%Y%m%d).tar.gz /opt/wp-hosting/shared/bind9/
```

**Restore**:
```bash
tar -xzf geodns-backup-20260216.tar.gz -C /
docker restart shared_geodns
```

### Integration with External Monitoring

Monitor DNS health with Uptime Kuma or similar:

- **Check Type**: DNS
- **Hostname**: `example.com`
- **DNS Server**: `YOUR-DNS-SERVER-IP`
- **Expected IP**: `185.1.2.3`

---

## Support and Resources

### Log Locations

- **BIND9 Logs**: `docker logs shared_geodns`
- **Web UI Logs**: `docker logs shared_geodns_ui`
- **Zone Files**: `/opt/wp-hosting/shared/bind9/records/`
- **Config Files**: `/opt/wp-hosting/shared/bind9/config/`

### Useful Commands

```bash
# Check DNS version
docker exec shared_geodns named -v

# Validate all zones
docker exec shared_geodns named-checkconf

# View current configuration
docker exec shared_geodns cat /etc/bind/named.conf

# List all zones
grep 'zone "' /opt/wp-hosting/shared/bind9/config/named.conf.zones.world
```

### Getting Help

1. Check logs first: `docker logs shared_geodns`
2. Verify configuration: `docker exec shared_geodns named-checkconf`
3. Test with dig: `dig @YOUR-SERVER-IP example.com`
4. Review this documentation
5. Check GitHub issues

---

## Quick Reference Card

```
┌─────────────────────────────────────────────────────────┐
│  GEODNS QUICK REFERENCE                                 │
├─────────────────────────────────────────────────────────┤
│  Install:        ./scripts/setup-geodns.sh install      │
│  Add Domain:     ./scripts/setup-geodns.sh add          │
│  Modify:         ./scripts/setup-geodns.sh modify       │
│  Advanced:       ./scripts/setup-geodns.sh manage       │
│  Restart:        ./scripts/setup-geodns.sh restart      │
│  Status:         ./scripts/setup-geodns.sh status       │
│                                                          │
│  Web UI:         http://SERVER-IP:1337                  │
│  BIND Logs:      docker logs shared_geodns              │
│  Reload:         docker exec shared_geodns rndc reload  │
│                                                          │
│  Zone Files:     /opt/wp-hosting/shared/bind9/records/  │
│  Config:         /opt/wp-hosting/shared/bind9/config/   │
└─────────────────────────────────────────────────────────┘
```
