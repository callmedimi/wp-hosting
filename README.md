# WP-HOSTING: Advanced Multi-Server WordPress Platform

**WP-HOSTING** is a production-ready solution for hosting and managing WordPress sites across multiple servers. It is designed for **High Availability**, **Disaster Recovery**, and **Geo-Location Routing** (specifically optimizing for Iran/International traffic split).

Manage 1 server or 100 servers from a single CLI and Web Dashboard.

---

## 🏗️ Architecture Overview

*   **Manager Node (VPS 1)**: The "Brain". Runs the Central Dashboard, Portainer, and standard sites.
*   **Worker Nodes (VPS 2+)**: The "Muscle". Runs sites and monitoring agents.
*   **Data Layer**:
    *   **Files**: Synced in real-time via **Syncthing**.
    *   **Databases**: Automatically dumped and restored via Replication Scripts.
*   **Traffic Layer**:
    *   **Traefik**: Handles SSL (Let's Encrypt) and routing per node.
    *   **GeoDNS (BIND9)**: Routes users to the nearest/best server (Iran vs. World).

---

## 📚 Documentation Index

| Topic | Description | Link |
| :--- | :--- | :--- |
| **GeoDNS Setup** | Complete guide to DNS management with Web UI tutorial. | [Read Guide](./GEODNS.md) |
| **Admin Tools** | How to use File Manager, DB, and Shared Tools.| [Read Guide](./SHARED_TOOLS_AND_DB.md) |
| **Monitoring** | Deep dive into Netdata, Graphs, and Alerts. | [Read Guide](./MONITORING.md) |
| **Replication** | Detailed setup for Syncthing and Disaster Recovery. | [Read Guide](./REPLICATION.md) |

---

## 🚀 Installation Guide (Quick Start)

### 1. Setup the Manager (First Server)
Download this repository to your main server (e.g., `/opt/wp-hosting`).
```bash
git clone https://github.com/aliqajarian/wp-hosting.git /opt/wp-hosting
cd /opt/wp-hosting
chmod +x manage.sh
sudo ./manage.sh
# Select: 1. Server Setup -> 1. MANAGER NODE
```
*   **Result**: Dashboard is live at `https://panel.yourdomain.com`.
*   **Action**: Go to `https://portainer.yourdomain.com` IMMEDIATELY to set your Admin Password.

### 2. Setup Workers (Replica Servers)
Download the repository to your secondary servers.
```bash
cd /opt/wp-hosting
sudo ./manage.sh
# Select: 1. Server Setup -> 2. WORKER NODE
```

### 3. Link Them (Central Monitoring)
Go back to the **Manager Node**:
```bash
sudo ./manage.sh
# Select: 2. Add Remote Worker Node
```
*   Enter the IP of the Worker.
*   This automatically connects **Portainer** and **Netdata** to your central dashboard.

---

## 🕹️ The Management Console (`./manage.sh`)

You don't need to memorize Docker commands. Everything is in the menu:

| Option | Description |
| :--- | :--- |
| **1. Server Setup** | Re-run setup or change roles. |
| **2. Add Remote Worker** | Connect a new VPS to the Manager. |
| **3. Create New Site** | Deploys WordPress with **Persian Support**, DB, and User Isolation. |
| **4. List Local Sites** | Quick status check of running sites. |
| **5. Access Site Tools** | Open **Shell**, View **Logs**, **Localize Fonts**, or **Manage Replication**. |
| **6. Manage Stack** | Restart services or run a **Cluster Health Check**. |
| **7. Replication Console** | **CRITICAL**: Manage Failover, Sync status, and Backups key menu. |
| **8. GeoDNS Manager** | Install/Config BIND9 for traffic routing. |

---

## 🔄 Replication & Failover (How it works)

Every site has a "Identity" config in `.env` defining where it lives and how other servers handle it.

### Modes
1.  **Primary Node**: The server that *owns* the site. It always runs the site.
2.  **Replica Mode - Active**: Other servers will **RUN** the site (Active-Active / GeoDNS).
3.  **Replica Mode - Passive**: Other servers sync data but keeping containers **STOPPED** (Cold Standby).
4.  **Replica Mode - Off**: Other servers delete/ignore the site.

### How to use it:
1.  **Setup Pairing**: Run `manage.sh -> 7 -> 3` on both servers to swap Syncthing IDs.
2.  **Approve Pairing**: Go to `http://<SERVER_IP>:8384` on both to accept the connection. **(Manual Step)**
3.  **Enable Auto-Sync**: Run `manage.sh -> 7 -> 6` on the **Replica** to enable the 30-min sync Cron Job.

### Disaster Recovery (Failover)
If VPS 1 dies:
1.  Log into VPS 2.
2.  Run `manage.sh -> 7 -> 2 (Configure Site Replication)`.
3.  Select the Site (`client1`) -> **Promote to Primary**.
4.  The site starts immediately with the latest data.
5.  Update DNS (or let GeoDNS handle it).

---

## 🌍 GeoDNS Traffic Routing

You can serve Iranian users from an IR-VPS and World users from an EU-VPS for the **same domain**.

### Quick Start

1.  Run `manage.sh -> 8` or `./scripts/setup-geodns.sh install`
2.  Access Web UI at `http://YOUR-SERVER-IP:1337`
3.  Click **"Add New Domain"** and enter:
    *   Domain: `example.com`
    *   World IP: Your international server IP
    *   Iran IP: Your Iran-based server IP
4.  **Registrar Step**: Update nameservers at your domain registrar to:
    *   `ns1.example.com` → Your DNS server IP
    *   `ns2.example.com` → Your DNS server IP

### Features

- **Web-Based Management**: Full DNS control via browser (port 1337)
- **CLI Tools**: Powerful command-line interface for automation
- **Advanced Records**: Support for A, CNAME, MX, TXT, NS records
- **Split-View**: Different DNS responses for Iran vs. World
- **Auto-Updates**: Scheduled Iran IP list refreshes

📖 **[Read the Complete GeoDNS Guide](./GEODNS.md)** for detailed tutorials, troubleshooting, and advanced configuration.

---

## ⚠️ Important: Things to Remember

1.  **Manual Syncthing Pairing**:
    The script helps you find your ID, but for security, **you must click "Add Device"** in the Syncthing Web UI (`http://IP:8384`) to actually link servers.

2.  **Portainer Initial Login**:
    After installing the Manager, immediately go to `https://portainer.yourdomain.com` to set your **Admin Password**. We do not set a default one for security.

3.  **The "Auto-Sync" Delay**:
    File synchronization is near-instant, but **User Creation / DB Restore / Container Start** happens when the Cron Job runs (every 30 mins). You can force it instantly via `manage.sh -> 7 -> 3`.

4.  **Domain Handling**:
    In a failover setup, **do not change the domain name** on the replica. Both servers should be configured to serve `client1.com`. You control which one is accessed via DNS.

5.  **Database Sync Direction**:
    Database dumps happen on the **Active** server and flow to the **Replica**. Avoid writing to the database on both servers simultaneously (Multi-Master) unless you know what you are doing. The provided setup is optimized for **Active-Passive** or **Geo-Splitting** (where users stick to one server).

---

## 🛠 Dashboard URLs (Default)

| Service | URL |
| :--- | :--- |
| **Main Panel** | `https://panel.yourdomain.com` |
| **GeoDNS Manager** | `http://YOUR-SERVER-IP:1337` |
| **Files** | `https://files.yourdomain.com` |
| **Portainer** | `https://portainer.yourdomain.com` |
| **Netdata** | `https://monitor.yourdomain.com` |
| **Dozzle Logs** | `https://logs.yourdomain.com` |
| **Database** | `https://pma.yourdomain.com` |
| **Uptime** | `https://status.yourdomain.com` |
| **Mailpit** | `https://mail.yourdomain.com` |
