# `docker-compose.yml` — Nginx Container Definition

> **Purpose:** Defines the Nginx load-balancer container, its port bindings, volumes, security constraints, and networking.

---

## Full Source

```yaml
services:
  nginx-lb:
    image: nginx:1.30.0
    container_name: cyberark-lb
    restart: unless-stopped
    user: "10101:10101"
    read_only: true

    ports:
      - "${DATAPLANE_VIP}:443:8443"     # PVWA HTTPS
      - "${DATAPLANE_VIP}:3389:3389"    # PSM (RDP)
      - "${DATAPLANE_VIP}:2222:2222"    # PSMP (SSH)

    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx-data/logs:/var/log/nginx
      - ./nginx-data/cache:/var/cache/nginx

    tmpfs:
      - /var/run:uid=10101,gid=10101

    networks:
      dataplan:
        ipv4_address: 172.20.0.10

networks:
  dataplan:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
```

---

## Directive-by-Directive Walkthrough

### Service Definition

| Directive | What it does |
|---|---|
| `image: nginx:1.30.0` | Uses a **pinned** Nginx version for reproducibility. Avoids surprise breaking changes from `latest`. |
| `container_name: cyberark-lb` | Fixed container name. Used by logrotate's `postrotate` script to send `USR1` signals for log rotation. |
| `restart: unless-stopped` | Automatically restarts the container on crash or host reboot, unless it was explicitly stopped with `docker stop`. |
| `user: "10101:10101"` | Runs the Nginx process as UID/GID 10101 (the `nginx-lb` user created by `init.sh`). Avoids running as root inside the container. |
| `read_only: true` | Makes the container's root filesystem **read-only**. Nginx can only write to explicitly mounted volumes and tmpfs. This is a security hardening measure. |

### Port Bindings

```yaml
ports:
  - "${DATAPLANE_VIP}:443:8443"
  - "${DATAPLANE_VIP}:3389:3389"
  - "${DATAPLANE_VIP}:2222:2222"
```

| Mapping | What it does |
|---|---|
| `${DATAPLANE_VIP}:443:8443` | Binds **VIP:443** on the host to **8443** inside the container. Only traffic arriving on the VIP reaches Nginx — not on the node's real IP. |
| `${DATAPLANE_VIP}:3389:3389` | PSM (RDP) — same port inside and outside. |
| `${DATAPLANE_VIP}:2222:2222` | PSMP (SSH) — exposed on 2222 to avoid conflict with the host's SSH on port 22. |

**Why bind to the VIP?** This ensures traffic is only served when the VIP is held locally. On the backup node (where the VIP is absent), Docker still starts successfully thanks to `net.ipv4.ip_nonlocal_bind=1`, but no external traffic reaches it until failover.

### Volumes

```yaml
volumes:
  - ./nginx.conf:/etc/nginx/nginx.conf:ro
  - ./nginx-data/logs:/var/log/nginx
  - ./nginx-data/cache:/var/cache/nginx
```

| Mount | What it does |
|---|---|
| `nginx.conf:ro` | Bind-mounts the rendered config as **read-only**. Any config change requires a container restart (handled by `runUpdate.sh`). |
| `nginx-data/logs` | Writable volume for access and error logs. Managed by logrotate on the host. |
| `nginx-data/cache` | Writable volume for Nginx's internal cache structures. Required because the root filesystem is read-only. |

### tmpfs

```yaml
tmpfs:
  - /var/run:uid=10101,gid=10101
```

- Creates an **in-memory filesystem** at `/var/run` for the Nginx PID file
- Owned by UID 10101 so the non-root Nginx process can write its PID
- No data persists across container restarts (appropriate for a PID file)

### Network

```yaml
networks:
  dataplan:
    ipv4_address: 172.20.0.10
```

- Assigns a **static IP** (`172.20.0.10`) within a dedicated Docker bridge network
- The Keepalived health check (`chk_lb`) probes this exact IP to verify Nginx is alive
- The `172.20.0.0/24` subnet is internal to Docker and doesn't conflict with the data-plane network

---

## Security Hardening Summary

| Feature | Benefit |
|---|---|
| `user: "10101:10101"` | Non-root container process |
| `read_only: true` | Immutable root filesystem |
| `tmpfs` for `/var/run` | PID file in memory only |
| `:ro` config mount | Config cannot be modified from inside the container |
| VIP-only port binding | Container doesn't listen on the node's real IP |
