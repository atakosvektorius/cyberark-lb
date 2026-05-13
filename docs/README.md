# CyberArk High Availability Load Balancer

This project provides a **High Availability (HA) Layer 4 TCP Load Balancing** solution specifically tailored for CyberArk environments. It leverages **Nginx** (running in a Docker container) for stream routing and **Keepalived** for Virtual IP (VIP) failover management.

---

## What Does This Project Do?

It deploys an **active / standby pair** of Linux nodes, each running:

| Component | Role |
|---|---|
| **Nginx** (Docker container) | Layer 4 TCP reverse-proxy that load-balances three CyberArk services: **PVWA** (HTTPS/443), **PSM** (RDP/3389) and **PSMP** (SSH/22). |
| **Keepalived** (host service) | Manages a shared **Virtual IP (VIP)** between the two nodes using VRRP. If the primary node's Nginx becomes unhealthy the VIP automatically floats to the backup node. |

### Architecture Overview

```
                        ┌─────── VIP (DATAPLANE_VIP) ───────┐
                        │                                    │
               ┌────────▼────────┐               ┌──────────▼──────────┐
               │   Primary Node  │               │    Backup Node      │
               │  (priority 100) │ ◄── VRRP ──►  │   (priority 90)     │
               │  keepalived     │               │   keepalived        │
               │  ┌────────────┐ │               │  ┌────────────┐     │
               │  │ Nginx (LB) │ │               │  │ Nginx (LB) │     │
               │  └────────────┘ │               │  └────────────┘     │
               └─────────────────┘               └─────────────────────┘
                        │                                    │
          ┌─────────────┼─────────────────┐                  │
          ▼             ▼                 ▼                  ...
     PVWA ×2       PSM ×2          PSMP ×2
   (443/HTTPS)   (3389/RDP)       (22/SSH)
```

Both nodes run an identical Nginx container and Keepalived instance. Under normal conditions only the primary holds the VIP and therefore receives traffic. The backup stands by and takes over automatically.

---

## Prerequisites

- **Two Linux hosts** (Debian/Ubuntu recommended) with network connectivity between each other and to the CyberArk upstream servers.
- An unused IP address on the data-plane network to serve as the **VIP**.
- **Root / sudo access** on both hosts.
- Internet access (to install Docker and packages during `init.sh`).

> **Note:** Docker and Keepalived are installed automatically by `init.sh`; you do *not* need to pre-install them.

---

## Quick Start

### 1. Clone the repository on **both** nodes

```bash
git clone <repo-url> ~/cyberark-lb
cd ~/cyberark-lb
```

### 2. Create the `.env` file

Copy the sample and fill in your values:

```bash
cp .env.sample .env
```

Edit `.env`:

```dotenv
# ── Node role: primary | backup ──
NODE_ROLE=primary            # Set to "backup" on the second node

# ── Data-plane network ──
DATAPLANE_VIP=10.0.0.100           # Shared Virtual IP
DATAPLANE_IP_PRIMARY=10.0.0.101    # Primary node's real IP
DATAPLANE_IP_BACKUP=10.0.0.102     # Backup node's real IP

# ── CyberArk PVWA upstream servers (HTTPS/443) ──
PVWA_UPSTREAM_1=10.0.1.10
PVWA_UPSTREAM_2=10.0.1.11

# ── CyberArk PSM upstream servers (RDP/3389) ──
PSM_UPSTREAM_1=10.0.1.20
PSM_UPSTREAM_2=10.0.1.21

# ── CyberArk PSMP upstream servers (SSH/22) ──
PSMP_UPSTREAM_1=10.0.1.30
PSMP_UPSTREAM_2=10.0.1.31
```

> ⚠️ **The `.env` file must be configured individually on each node.** The only difference between the two is the `NODE_ROLE` value (`primary` vs `backup`).

### 3. Run the initialisation script

```bash
sudo bash init.sh
```

This will:
1. Install Docker and Keepalived.
2. Create the dedicated `nginx-lb` system user (UID 10101).
3. Validate all required `.env` variables.
4. Set the hostname (`cyberark-lb-primary` or `cyberark-lb-backup`).
5. Enable `net.ipv4.ip_nonlocal_bind` so Docker can bind to the VIP even when it isn't held locally.
6. Install the logrotate configuration.
7. Render the Nginx and Keepalived configs and start both services.

### 4. Verify

```bash
# Check Keepalived status
sudo systemctl status keepalived

# Check Nginx container
sudo docker ps

# Test VIP connectivity (from any client)
curl -k https://<DATAPLANE_VIP>
```

---

## Configuration Reference

> [!NOTE]
> **Network interfaces:** This setup assumes a **single network interface** for both management (SSH) and data-plane (CyberArk) traffic. The PSMP listener is therefore exposed on port **2222** to avoid conflicting with the host's own SSH daemon on port 22.
>
> Ideally, use **two interfaces** — one for management and one for the data plane. With a dual-interface setup, bind the host's SSH daemon to the management IP only (set `ListenAddress` in `/etc/ssh/sshd_config` to the management IP on port 22), then change the PSMP port mapping in `docker-compose.yml` from `2222:2222` to `22:2222`. Since Nginx runs inside Docker, its internal listen port doesn't conflict with the host — only the host-side published port matters.

### Changing Upstream IPs / Adding Nodes

All upstream server IPs are defined in **`.env`**. To change them:

1. Edit `.env` with the new IP addresses.
2. Re-run the update script to re-render configs and restart services:

```bash
sudo bash runUpdate.sh
```

### Changing the VIP or Node IPs

Update `DATAPLANE_VIP`, `DATAPLANE_IP_PRIMARY`, and/or `DATAPLANE_IP_BACKUP` in `.env` on **both** nodes, then run:

```bash
sudo bash runUpdate.sh
```

### Environment Variables

| Variable | Description | Example |
|---|---|---|
| `NODE_ROLE` | Role of this node: `primary` or `backup` | `primary` |
| `DATAPLANE_VIP` | Virtual IP shared between both nodes | `10.0.0.100` |
| `DATAPLANE_IP_PRIMARY` | Real IP of the primary node | `10.0.0.101` |
| `DATAPLANE_IP_BACKUP` | Real IP of the backup node | `10.0.0.102` |
| `PVWA_UPSTREAM_1` | First PVWA server IP | `10.0.1.10` |
| `PVWA_UPSTREAM_2` | Second PVWA server IP | `10.0.1.11` |
| `PSM_UPSTREAM_1` | First PSM server IP | `10.0.1.20` |
| `PSM_UPSTREAM_2` | Second PSM server IP | `10.0.1.21` |
| `PSMP_UPSTREAM_1` | First PSMP server IP | `10.0.1.30` |
| `PSMP_UPSTREAM_2` | Second PSMP server IP | `10.0.1.31` |

---

## Day-2 Operations

### Updating Upstream IPs

```bash
vim .env                  # change the IP(s)
sudo bash runUpdate.sh    # re-render + restart
```

### Viewing Nginx Logs

```bash
tail -f nginx-data/logs/error.log
```

### Manually Triggering a Failover (for testing)

On the primary node:

```bash
sudo systemctl stop keepalived
# VIP should float to the backup node within ~6 seconds
```

### Checking VIP ownership

```bash
ip addr show | grep <DATAPLANE_VIP>
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Container won't start / port bind error | VIP not present on the host and `ip_nonlocal_bind` is off | Run `sudo sysctl -w net.ipv4.ip_nonlocal_bind=1` |
| VIP doesn't float on failure | Keepalived not running or health check script failing | Check `sudo systemctl status keepalived` and `journalctl -u keepalived` |
| Upstream unreachable | Wrong IP in `.env` or firewall blocking | Verify `.env` values; test with `nc -zv <IP> <PORT>` |
| Permission denied on `nginx-data/` | UID mismatch | Run `sudo chown -R 10101:10101 nginx-data/` |

---

## Project Structure

```
cyberark-lb/
├── .env.sample              # Template for environment variables
├── docker-compose.yml       # Docker Compose definition for the Nginx container
├── nginx.conf.template      # Nginx stream config (envsubst template)
├── keepalived.conf.primary  # Keepalived template for the primary node
├── keepalived.conf.backup   # Keepalived template for the backup node
├── init.sh                  # One-time initialisation script
├── runUpdate.sh             # Re-render configs and restart services
├── cyberark-nginx           # Logrotate configuration for Nginx logs
├── docs/                    # Extended documentation
│   ├── init-sh.md           # Line-by-line walkthrough of init.sh
│   ├── runupdate-sh.md      # Line-by-line walkthrough of runUpdate.sh
│   ├── nginx-conf.md        # Deep-dive into nginx.conf.template
│   ├── keepalived-conf.md   # Deep-dive into keepalived configurations
│   ├── docker-compose.md    # Explanation of docker-compose.yml
│   ├── env-reference.md     # Full environment variable reference
│   └── logrotate.md         # Logrotate configuration explained
├── LICENSE                  # MIT License
└── README.md                # This file
```

---

## License

[MIT](LICENSE)
