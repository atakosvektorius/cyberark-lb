# `nginx.conf.template` — Layer 4 TCP Stream Configuration

> **Purpose:** Defines Nginx as a **Layer 4 (TCP) reverse proxy** that load-balances three CyberArk services across two upstream servers each. This is a **template** — `${VAR}` placeholders are resolved by `envsubst` at deploy time.

---

## Overview

This config uses Nginx's `stream {}` module (not `http {}`). All traffic is handled as raw TCP; Nginx never terminates TLS or inspects HTTP payloads.

| Service | Listen Port (internal) | External Port (VIP) | Upstream Port | LB Algorithm |
|---|---|---|---|---|
| PVWA (HTTPS) | 8443 | 443 | 443 | `hash $remote_addr consistent` |
| PSM (RDP) | 3389 | 3389 | 3389 | `least_conn` |
| PSMP (SSH) | 2222 | 2222 | 22 | `least_conn` |

---

## Core Settings Block

```nginx
worker_processes auto;
worker_rlimit_nofile 65535;
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;
```

| Directive | What it does |
|---|---|
| `worker_processes auto` | Spawns one worker process per CPU core, maximising parallelism. |
| `worker_rlimit_nofile 65535` | Raises the per-worker file descriptor limit. Each proxied TCP connection consumes two file descriptors (client ↔ nginx + nginx ↔ upstream). |
| `error_log ... notice` | Logs warnings and above to the mounted volume. The `notice` level catches connection failures without flooding with debug noise. |
| `pid /var/run/nginx.pid` | Stores the master PID in a tmpfs mount (see `docker-compose.yml`). Required for graceful reload via `kill -USR1`. |

---

## Events Block

```nginx
events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}
```

| Directive | What it does |
|---|---|
| `worker_connections 4096` | Each worker can handle up to 4096 simultaneous connections. With `auto` workers this gives `cores × 4096` total capacity. |
| `use epoll` | Selects Linux's `epoll` event notification mechanism — the most efficient for high-connection-count servers. |
| `multi_accept on` | When a worker is woken up, it accepts **all** pending connections at once instead of one at a time, reducing context switches. |

---

## Stream Block — Upstream Definitions

### 1. PVWA (HTTPS/443) — `pvwa_servers`

```nginx
upstream pvwa_servers {
    hash $remote_addr consistent;
    server ${PVWA_UPSTREAM_1}:443 max_fails=2 fail_timeout=30s;
    server ${PVWA_UPSTREAM_2}:443 max_fails=2 fail_timeout=30s;
}
```

| Element | What it does |
|---|---|
| `hash $remote_addr consistent` | **Consistent hashing** on the client's source IP. The same client always reaches the same PVWA server, preserving HTTPS session cookies. The `consistent` keyword uses a ketama-style hash ring, so adding/removing servers only remaps a minority of clients. |
| `max_fails=2` | After **2** consecutive failed connection attempts, the server is marked as down. |
| `fail_timeout=30s` | The server stays in the "down" penalty box for **30 seconds** before Nginx retries it. This also defines the window within which `max_fails` is counted. |

**Why consistent hashing for PVWA?** PVWA is a web application that uses session cookies. If a client were bounced between servers, its session would be lost. Consistent hashing provides soft session affinity without requiring application-layer inspection.

### 2. PSM (RDP/3389) — `psm_servers`

```nginx
upstream psm_servers {
    least_conn;
    server ${PSM_UPSTREAM_1}:3389 max_fails=2 fail_timeout=30s;
    server ${PSM_UPSTREAM_2}:3389 max_fails=2 fail_timeout=30s;
}
```

| Element | What it does |
|---|---|
| `least_conn` | Routes each new connection to the server with the **fewest active connections**. Ideal for long-lived RDP sessions where connection duration varies widely. |

### 3. PSMP (SSH/22) — `psmp_servers`

```nginx
upstream psmp_servers {
    least_conn;
    server ${PSMP_UPSTREAM_1}:22 max_fails=2 fail_timeout=30s;
    server ${PSMP_UPSTREAM_2}:22 max_fails=2 fail_timeout=30s;
}
```

Same algorithm as PSM — `least_conn` is optimal for long-lived SSH sessions.

---

## Stream Block — Server (Listener) Definitions

### PVWA Listener

```nginx
server {
    listen 8443;
    proxy_pass pvwa_servers;
    proxy_connect_timeout 3s;
    proxy_timeout 120s;
}
```

| Directive | What it does |
|---|---|
| `listen 8443` | Binds to port 8443 inside the container. Docker maps `VIP:443 → 8443` (see `docker-compose.yml`). |
| `proxy_pass pvwa_servers` | Forwards TCP to the `pvwa_servers` upstream group. |
| `proxy_connect_timeout 3s` | If the upstream doesn't accept a TCP connection within **3 seconds**, Nginx tries the next server. Fast failover. |
| `proxy_timeout 120s` | If no data flows in either direction for **2 minutes**, the connection is closed. Web traffic is typically short-lived, so 2 minutes is generous. |

### PSM Listener

```nginx
server {
    listen 3389 so_keepalive=60s:15s:3;
    proxy_pass psm_servers;
    proxy_socket_keepalive on;
    proxy_connect_timeout 3s;
    proxy_timeout 2h;
}
```

| Directive | What it does |
|---|---|
| `listen 3389 so_keepalive=60s:15s:3` | Enables **OS-level TCP keepalive** on the client-facing socket: idle 60s before first probe, probe every 15s, drop after 3 missed probes. This detects dead clients (e.g., laptop lid closed). |
| `proxy_socket_keepalive on` | Enables TCP keepalive on the **upstream** connection too, detecting dead PSM servers. |
| `proxy_timeout 2h` | RDP sessions can be idle for long periods; **2 hours** accommodates this. |

### PSMP Listener

```nginx
server {
    listen 2222 so_keepalive=60s:15s:3;
    proxy_pass psmp_servers;
    proxy_socket_keepalive on;
    proxy_connect_timeout 3s;
    proxy_timeout 2h;
}
```

Identical to PSM. SSH sessions also tend to be long-lived and benefit from the same keepalive and timeout settings.

> **Note:** PSMP listens on port **2222** (not 22) to avoid conflicting with the host's own SSH daemon. Docker maps `VIP:2222 → container:2222`, and Nginx then proxies to the real PSMP servers on port 22.
