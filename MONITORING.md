# Monitoring: Real-Time Metrics, Graphs, and Uptime

This document explains how to monitor the health of your servers, containers, and websites across your entire infrastructure.

---

## 📊 Overview

The WP-Hosting platform provides comprehensive monitoring through multiple integrated tools:

- **Homepage Dashboard**: Quick overview of all services
- **Netdata**: Real-time system and container metrics
- **Portainer**: Container management and stats
- **Uptime Kuma**: Website availability monitoring
- **Dozzle**: Live container logs
- **GeoDNS UI**: DNS server status and logs

---

## 1. Central Dashboard (Homepage)

**URL**: `https://panel.yourdomain.com`

The central dashboard provides an at-a-glance view of your entire infrastructure:

### What You See

- **Service Status**: Live status indicators for all services
- **Container Stats**: CPU and memory usage for critical containers
- **Portainer Widget**: Number of running containers and stacks
- **Netdata Widget**: Current system CPU usage
- **Uptime Kuma Widget**: Number of monitors and their status
- **Traefik Widget**: Active routers and services

### Quick Actions

Each service card is clickable and takes you directly to that service's management interface.

---

## 2. Detailed System Metrics (Netdata)

**URL**: `https://monitor.yourdomain.com`

Netdata provides real-time, detailed metrics for every aspect of your servers.

### Accessing Netdata

1. Click the **Netdata** icon on the Dashboard
2. Or navigate directly to `https://monitor.yourdomain.com`

### Key Features

#### System Overview
- **CPU Usage**: Per-core utilization, system vs. user time
- **Memory**: RAM usage, swap, buffers, cache
- **Disk I/O**: Read/write operations per disk
- **Network**: Bandwidth usage per interface

#### Container Metrics
Navigate to **Applications** → **docker** or **cgroups** in the right sidebar:

- **CPU per Container**: See which containers are consuming CPU
- **Memory per Container**: RAM usage breakdown
- **Network per Container**: Bandwidth usage
- **Disk I/O per Container**: Read/write operations

#### Useful Views

**Per-Container CPU**:
```
Applications → cgroups → cpu
```

**Per-Container Memory**:
```
Applications → cgroups → mem
```

**Network Traffic**:
```
Network Interfaces → [interface name] → bandwidth
```

### Historical Data

- Netdata stores metrics locally
- Zoom out to see the last hour, day, or week
- Use the time selector at the top-right

### Setting Up Alerts

Netdata can send alerts via:
- Email
- Slack
- Discord
- Telegram
- Custom webhooks

**To configure alerts**:
1. SSH into your server
2. Edit `/etc/netdata/health_alarm_notify.conf`
3. Configure your notification method
4. Restart Netdata: `docker restart shared_netdata`

---

## 3. Container Management (Portainer)

**URL**: `https://portainer.yourdomain.com`

Portainer provides a web UI for managing Docker containers, images, networks, and volumes.

### Accessing Portainer

1. Click **Portainer** on the Dashboard
2. Or navigate to `https://portainer.yourdomain.com`
3. **First-time setup**: Create your admin password immediately after installation

### Monitoring Containers

#### Container List
1. Go to **Containers** in the left sidebar
2. See all running, stopped, and paused containers
3. Quick actions: Start, Stop, Restart, Kill, Remove

#### Live Container Stats
1. Click on a specific container (e.g., `client1_wp`)
2. Click the **Stats** icon (📊 chart symbol)
3. View real-time graphs:
   - CPU usage
   - Memory usage
   - Network I/O
   - Block I/O

#### Container Logs
1. Select a container
2. Click **Logs**
3. View live streaming logs
4. Search and filter log output

### Multi-Server Management

If you've connected worker nodes:

1. Use the **Environments** dropdown at the top
2. Switch between servers instantly
3. Manage all your infrastructure from one interface

### Useful Features

- **Quick Actions**: Restart containers with one click
- **Console Access**: Open a shell inside any container
- **Resource Limits**: Set CPU and memory limits
- **Health Checks**: Configure container health monitoring

---

## 4. Website Uptime Monitoring (Uptime Kuma)

**URL**: `https://status.yourdomain.com`

Uptime Kuma monitors your websites and services, alerting you when they go down.

### Initial Setup

1. Navigate to `https://status.yourdomain.com`
2. Create your admin account (first-time only)
3. Start adding monitors

### Adding a Website Monitor

1. Click **Add New Monitor**
2. Configure:
   - **Monitor Type**: HTTP(s)
   - **Friendly Name**: `Client1 Website`
   - **URL**: `https://client1.com`
   - **Heartbeat Interval**: 60 seconds
   - **Retries**: 3
3. Click **Save**

### Monitor Types

- **HTTP(s)**: Check website availability
- **TCP Port**: Monitor specific ports (e.g., MySQL, SSH)
- **Ping**: ICMP ping monitoring
- **DNS**: Check DNS resolution
- **Docker Container**: Monitor container status
- **Keyword**: Check if specific text appears on a page

### Setting Up Notifications

#### Email Notifications
1. Go to **Settings** → **Notifications**
2. Click **Setup Notification**
3. Select **Email (SMTP)**
4. Configure your SMTP server
5. Test the notification

#### Telegram Notifications
1. Create a Telegram bot via @BotFather
2. Get your bot token
3. Get your chat ID
4. Add notification in Uptime Kuma
5. Test the notification

#### Other Notification Methods
- Slack
- Discord
- Webhook
- Pushover
- Signal
- And many more...

### Public Status Page

Create a public status page for your clients:

1. Go to **Status Pages**
2. Click **New Status Page**
3. Select which monitors to display
4. Customize appearance
5. Share the public URL

---

## 5. Live Container Logs (Dozzle)

**URL**: `https://logs.yourdomain.com`

Dozzle provides a real-time log viewer for all your Docker containers.

### Features

- **Live Streaming**: See logs as they happen
- **Multi-Container View**: View multiple containers simultaneously
- **Search**: Filter logs by keyword
- **Color Coding**: Error, warning, and info messages are color-coded
- **No Authentication Required**: Protected by Traefik (internal access only)

### Using Dozzle

1. Navigate to `https://logs.yourdomain.com`
2. Select a container from the list
3. Logs stream in real-time
4. Use the search box to filter
5. Click **Download** to save logs locally

### Troubleshooting with Dozzle

**Scenario**: WordPress site is showing errors

1. Open Dozzle
2. Select `client1_wp` container
3. Look for PHP errors or warnings
4. Search for specific error messages
5. Download logs for detailed analysis

---

## 6. GeoDNS Monitoring

**URL**: `http://YOUR-SERVER-IP:1337`

The GeoDNS Web UI includes monitoring capabilities.

### Checking DNS Status

1. Access the GeoDNS UI
2. Click **"Show Status & Logs"**
3. View:
   - Container status
   - Recent DNS queries
   - Configuration errors
   - Zone file issues

### DNS Query Logging

Enable query logging to see all DNS requests:

```bash
docker exec shared_geodns rndc querylog on
docker logs -f shared_geodns
```

You'll see:
- Client IP addresses
- Queried domains
- Response types (A, CNAME, MX, etc.)
- Which view was used (Iran vs. World)

---

## 7. Multi-Server Monitoring

### Connecting Worker Nodes

When you add worker nodes via `manage.sh → Option 2`, they automatically appear in:

1. **Portainer**: Switch environments to manage each server
2. **Netdata**: Each node streams to the central dashboard
3. **Homepage**: Worker services appear in dedicated sections

### Viewing Worker Metrics

**In Netdata**:
- Each worker node has its own Netdata instance
- Access via `http://WORKER-IP:19999`
- Or view aggregated metrics on the Manager

**In Portainer**:
- Use the **Environments** dropdown
- Select the worker node
- Manage containers remotely

---

## 8. Health Checks and Alerts

### Automated Health Checks

Run the cluster health check:

```bash
sudo ./manage.sh
# Select: 6. Manage Server Stack
# Select: 5. Run Cluster Health Check
```

This checks:
- Docker daemon status
- Critical container status
- Disk space
- Memory usage
- Network connectivity

### Setting Up Alerts

#### Netdata Alerts (System-Level)

Edit `/etc/netdata/health.d/` to configure alerts for:
- High CPU usage
- Low disk space
- High memory usage
- Container crashes

#### Uptime Kuma Alerts (Application-Level)

Configure monitors for:
- Website downtime
- Slow response times
- SSL certificate expiration
- DNS resolution failures

---

## 9. Performance Monitoring Best Practices

### What to Monitor

1. **CPU Usage**: Should stay below 70% average
2. **Memory**: Watch for memory leaks in containers
3. **Disk Space**: Alert when below 20% free
4. **Network**: Monitor for unusual traffic spikes
5. **Response Times**: Website should load in <2 seconds

### Regular Checks

**Daily**:
- Check Uptime Kuma for any downtime
- Review Dozzle for error messages

**Weekly**:
- Review Netdata graphs for trends
- Check disk space usage
- Verify backup completion

**Monthly**:
- Review container resource usage
- Optimize containers using too much CPU/RAM
- Clean up old Docker images and volumes

---

## 10. Troubleshooting Common Issues

### High CPU Usage

1. **Identify the culprit**:
   ```bash
   docker stats
   ```
2. **Check Netdata**: Applications → cgroups → cpu
3. **View container logs**: Use Dozzle or `docker logs`
4. **Restart if needed**: Via Portainer or CLI

### High Memory Usage

1. **Check Netdata**: Applications → cgroups → mem
2. **Identify memory leaks**: Look for constantly increasing memory
3. **Restart container**: `docker restart container_name`
4. **Set memory limits**: Via Portainer or docker-compose

### Container Keeps Restarting

1. **Check logs**: Dozzle or `docker logs container_name`
2. **Check health**: `docker inspect container_name`
3. **Verify configuration**: Check `.env` files
4. **Check dependencies**: Ensure database is running

### Website Down

1. **Check Uptime Kuma**: Is it really down?
2. **Check Traefik**: Is the route configured?
3. **Check container**: Is it running? (`docker ps`)
4. **Check logs**: Dozzle or `docker logs`
5. **Check DNS**: Is domain pointing to correct IP?

---

## 11. Dashboard URLs Reference

| Service | URL | Purpose |
|---------|-----|---------|
| **Homepage** | `https://panel.yourdomain.com` | Central dashboard |
| **Netdata** | `https://monitor.yourdomain.com` | System metrics |
| **Portainer** | `https://portainer.yourdomain.com` | Container management |
| **Uptime Kuma** | `https://status.yourdomain.com` | Uptime monitoring |
| **Dozzle** | `https://logs.yourdomain.com` | Live logs |
| **GeoDNS UI** | `http://SERVER-IP:1337` | DNS management |
| **Traefik** | `https://gateway.yourdomain.com` | Reverse proxy dashboard |
| **Syncthing** | `http://SERVER-IP:8384` | File sync status |

---

## 12. Quick Reference Commands

```bash
# View all container stats
docker stats

# Check specific container logs
docker logs -f container_name

# Restart a container
docker restart container_name

# Check disk space
df -h

# Check memory usage
free -h

# View running containers
docker ps

# Run health check
sudo ./manage.sh
# Select: 6 → 5

# Enable DNS query logging
docker exec shared_geodns rndc querylog on

# View Netdata config
docker exec shared_netdata cat /etc/netdata/netdata.conf
```

---

## Support

For issues with monitoring:
1. Check the service's own logs first
2. Verify the container is running
3. Check Traefik routes
4. Review this documentation
5. Check GitHub issues
