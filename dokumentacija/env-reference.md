# Aplinkos kintamųjų žinynas

> **Paskirtis:** Pilnas kiekvieno `.env.sample` kintamojo žinynas su aprašymais, apribojimais ir pavyzdžiais.

---

## `.env.sample` šablonas

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

## Kintamųjų detalės

### Mazgo tapatybė

| Kintamasis | Privalomas | Reikšmės | Aprašymas |
|---|---|---|---|
| `NODE_ROLE` | ✅ | `primary` arba `backup` | Nustato, kuris Keepalived šablonas naudojamas ir kokį hostname nustato `init.sh`. **Tai vienintelis kintamasis, kuris skiriasi tarp dviejų mazgų.** |

### Tinklo adresavimas

| Kintamasis | Privalomas | Formatas | Aprašymas |
|---|---|---|---|
| `DATAPLANE_VIP` | ✅ | IPv4 adresas | Virtualus IP, bendrinamas tarp mazgų. Klientai jungiasi prie šio adreso. Turi būti nenaudojamas IP data-plane potinklyje. |
| `DATAPLANE_IP_PRIMARY` | ✅ | IPv4 adresas | Tikrasis (statinis) **primary** mazgo IP. Naudojamas VRRP unicast komunikacijai tarp Keepalived instancijų. |
| `DATAPLANE_IP_BACKUP` | ✅ | IPv4 adresas | Tikrasis (statinis) **backup** mazgo IP. Naudojamas VRRP unicast komunikacijai. |

### CyberArk upstream serveriai

| Kintamasis | Privalomas | Formatas | Naudojamas | Aprašymas |
|---|---|---|---|---|
| `PVWA_UPSTREAM_1` | ✅ | IPv4 adresas | `nginx.conf.template` | Pirmas PVWA serveris. Nginx proxy'ina HTTPS (TCP/443) į šį serverį. |
| `PVWA_UPSTREAM_2` | ✅ | IPv4 adresas | `nginx.conf.template` | Antras PVWA serveris. |
| `PSM_UPSTREAM_1` | ✅ | IPv4 adresas | `nginx.conf.template` | Pirmas PSM serveris. Nginx proxy'ina RDP (TCP/3389) į šį serverį. |
| `PSM_UPSTREAM_2` | ✅ | IPv4 adresas | `nginx.conf.template` | Antras PSM serveris. |
| `PSMP_UPSTREAM_1` | ✅ | IPv4 adresas | `nginx.conf.template` | Pirmas PSMP serveris. Nginx proxy'ina SSH (TCP/22) į šį serverį. |
| `PSMP_UPSTREAM_2` | ✅ | IPv4 adresas | `nginx.conf.template` | Antras PSMP serveris. |

---

## Kur kiekvienas kintamasis naudojamas

| Kintamasis | `docker-compose.yml` | `nginx.conf.template` | `keepalived.conf.*` | `init.sh` |
|---|---|---|---|---|
| `NODE_ROLE` | — | — | šablono pasirinkimas | hostname, validacija |
| `DATAPLANE_VIP` | jungčių susiejimas | — | `virtual_ipaddress` | validacija |
| `DATAPLANE_IP_PRIMARY` | — | — | `unicast_src_ip` / `unicast_peer` | validacija |
| `DATAPLANE_IP_BACKUP` | — | — | `unicast_src_ip` / `unicast_peer` | validacija |
| `PVWA_UPSTREAM_*` | — | `pvwa_servers` upstream | — | validacija |
| `PSM_UPSTREAM_*` | — | `psm_servers` upstream | — | validacija |
| `PSMP_UPSTREAM_*` | — | `psmp_servers` upstream | — | validacija |

---

## Pavyzdys: Produkcinis `.env`

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

## Svarbios pastabos

- Visi kintamieji yra **privalomi**. `init.sh` patikrina kiekvieną ir nutraukia, jei kuris nors tuščias.
- Reikšmės yra **tik IP adresai** — neįtraukite jungčių numerių (jungtys yra užkoduotos Nginx šablone).
- `.env` failas **nėra** įkeliamas į versijų kontrolę (jame yra aplinkos specifiniai duomenys). Tik `.env.sample` yra sekamas.
