# Environment Variables Reference

> **Purpose:** Complete reference for every variable in `.env.sample` with descriptions, constraints, and examples.

---

## `.env.sample` Template

```dotenv
# ── Node role: primary | backup ──
NODE_ROLE=

# ── Data-plane network ──
DATAPLANE_VIP=
DATAPLANE_IP_PRIMARY=
DATAPLANE_IP_BACKUP=

# ── CyberArk PVWA upstream servers (HTTPS/443) ──
PVWA_UPSTREAM_1=
PVWA_UPSTREAM_2=

# ── CyberArk PSM upstream servers (RDP/3389) ──
PSM_UPSTREAM_1=
PSM_UPSTREAM_2=

# ── CyberArk PSMP upstream servers (SSH/22) ──
PSMP_UPSTREAM_1=
PSMP_UPSTREAM_2=
```

---

## Variable Details

### Node Identity

| Variable | Required | Values | Description |
|---|---|---|---|
| `NODE_ROLE` | ✅ | `primary` or `backup` | Determines which Keepalived template is used and the hostname set by `init.sh`. **This is the only variable that differs between the two nodes.** |

### Network Addressing

| Variable | Required | Format | Description |
|---|---|---|---|
| `DATAPLANE_VIP` | ✅ | IPv4 address | The Virtual IP shared between nodes. Clients connect to this address. Must be an unused IP on the data-plane subnet. |
| `DATAPLANE_IP_PRIMARY` | ✅ | IPv4 address | The real (static) IP of the **primary** node. Used for VRRP unicast communication between Keepalived instances. |
| `DATAPLANE_IP_BACKUP` | ✅ | IPv4 address | The real (static) IP of the **backup** node. Used for VRRP unicast communication. |

### CyberArk Upstream Servers

| Variable | Required | Format | Used In | Description |
|---|---|---|---|---|
| `PVWA_UPSTREAM_1` | ✅ | IPv4 address | `nginx.conf.template` | First PVWA server. Nginx proxies HTTPS (TCP/443) to this host. |
| `PVWA_UPSTREAM_2` | ✅ | IPv4 address | `nginx.conf.template` | Second PVWA server. |
| `PSM_UPSTREAM_1` | ✅ | IPv4 address | `nginx.conf.template` | First PSM server. Nginx proxies RDP (TCP/3389) to this host. |
| `PSM_UPSTREAM_2` | ✅ | IPv4 address | `nginx.conf.template` | Second PSM server. |
| `PSMP_UPSTREAM_1` | ✅ | IPv4 address | `nginx.conf.template` | First PSMP server. Nginx proxies SSH (TCP/22) to this host. |
| `PSMP_UPSTREAM_2` | ✅ | IPv4 address | `nginx.conf.template` | Second PSMP server. |

---

## Where Each Variable is Consumed

| Variable | `docker-compose.yml` | `nginx.conf.template` | `keepalived.conf.*` | `init.sh` |
|---|---|---|---|---|
| `NODE_ROLE` | — | — | template selection | hostname, validation |
| `DATAPLANE_VIP` | port bindings | — | `virtual_ipaddress` | validation |
| `DATAPLANE_IP_PRIMARY` | — | — | `unicast_src_ip` / `unicast_peer` | validation |
| `DATAPLANE_IP_BACKUP` | — | — | `unicast_src_ip` / `unicast_peer` | validation |
| `PVWA_UPSTREAM_*` | — | `pvwa_servers` upstream | — | validation |
| `PSM_UPSTREAM_*` | — | `psm_servers` upstream | — | validation |
| `PSMP_UPSTREAM_*` | — | `psmp_servers` upstream | — | validation |

---

## Example: Production `.env`

```dotenv
NODE_ROLE=primary

DATAPLANE_VIP=10.10.50.100
DATAPLANE_IP_PRIMARY=10.10.50.101
DATAPLANE_IP_BACKUP=10.10.50.102

PVWA_UPSTREAM_1=10.10.60.10
PVWA_UPSTREAM_2=10.10.60.11

PSM_UPSTREAM_1=10.10.60.20
PSM_UPSTREAM_2=10.10.60.21

PSMP_UPSTREAM_1=10.10.60.30
PSMP_UPSTREAM_2=10.10.60.31
```

---

## Important Notes

- All variables are **mandatory**. `init.sh` validates every one and aborts if any is empty.
- Values are **IP addresses only** — do not include port numbers (ports are hard-coded in the Nginx template).
- The `.env` file is **not** committed to version control (it contains environment-specific data). Only `.env.sample` is tracked.
