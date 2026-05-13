# `docker-compose.yml` — Nginx konteinerio apibrėžimas

> **Paskirtis:** Apibrėžia Nginx apkrovos balansuotojo konteinerį, jo jungčių susiejimus, tomus, saugumo apribojimus ir tinklo nustatymus.

---

## Pilnas šaltinis

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

## Direktyvų aprašymas

### Paslaugos apibrėžimas

| Direktyva | Ką daro |
|---|---|
| `image: nginx:1.30.0` | Naudoja **fiksuotą** Nginx versiją atkuriamumo užtikrinimui. Išvengia netikėtų pakeitimų naudojant `latest`. |
| `container_name: cyberark-lb` | Fiksuotas konteinerio pavadinimas. Naudojamas logrotate `postrotate` skripto `USR1` signalams siųsti log rotacijai. |
| `restart: unless-stopped` | Automatiškai perkrauna konteinerį po avarijos ar serverio perkrovimo, nebent jis buvo aiškiai sustabdytas su `docker stop`. |
| `user: "10101:10101"` | Paleidžia Nginx procesą kaip UID/GID 10101 (`nginx-lb` vartotojas, sukurtas `init.sh`). Išvengia veikimo kaip root konteinerio viduje. |
| `read_only: true` | Padaro konteinerio šakninę failų sistemą **tik skaitomą**. Nginx gali rašyti tik į aiškiai primontuotus tomus ir tmpfs. Tai saugumo sustiprinimo priemonė. |

### Jungčių susiejimai

```yaml
ports:
  - "${DATAPLANE_VIP}:443:8443"
  - "${DATAPLANE_VIP}:3389:3389"
  - "${DATAPLANE_VIP}:2222:2222"
```

| Susiejimas | Ką daro |
|---|---|
| `${DATAPLANE_VIP}:443:8443` | Susieja **VIP:443** serveryje su **8443** konteinerio viduje. Tik srautas, ateinantis per VIP, pasiekia Nginx — ne per mazgo tikrąjį IP. |
| `${DATAPLANE_VIP}:3389:3389` | PSM (RDP) — ta pati jungtis viduje ir išorėje. |
| `${DATAPLANE_VIP}:2222:2222` | PSMP (SSH) — rodomas per 2222, kad nekonfliktuotų su serverio SSH jungtimi 22. |

**Kodėl susieti su VIP?** Tai užtikrina, kad srautas aptarnaujamas tik tada, kai VIP yra vietinis. Backup mazge (kur VIP nėra) Docker vis tiek startuoja sėkmingai dėka `net.ipv4.ip_nonlocal_bind=1`, bet joks išorinis srautas jo nepasiekia iki failover.

### Tomai (Volumes)

```yaml
volumes:
  - ./nginx.conf:/etc/nginx/nginx.conf:ro
  - ./nginx-data/logs:/var/log/nginx
  - ./nginx-data/cache:/var/cache/nginx
```

| Montavimas | Ką daro |
|---|---|
| `nginx.conf:ro` | Primontuoja sugeneruotą konfigūraciją kaip **tik skaitomą**. Bet koks konfigūracijos pakeitimas reikalauja konteinerio perkrovimo (atliekama per `runUpdate.sh`). |
| `nginx-data/logs` | Rašomas tomas prieigos ir klaidų logams. Valdomas logrotate serveryje. |
| `nginx-data/cache` | Rašomas tomas Nginx vidinėms cache struktūroms. Reikalingas, nes šakninė failų sistema yra tik skaitoma. |

### tmpfs

```yaml
tmpfs:
  - /var/run:uid=10101,gid=10101
```

- Sukuria **atmintyje esančią failų sistemą** `/var/run` kataloge Nginx PID failui
- Priklauso UID 10101, kad ne-root Nginx procesas galėtų įrašyti savo PID
- Duomenys neišsaugomi per konteinerio perkrovimus (tinkama PID failui)

### Tinklas

```yaml
networks:
  dataplan:
    ipv4_address: 172.20.0.10
```

- Priskiria **statinį IP** (`172.20.0.10`) skirtame Docker bridge tinkle
- Keepalived sveikatos tikrinimas (`chk_lb`) tikrina būtent šį IP, kad patikrintų ar Nginx veikia
- `172.20.0.0/24` potinklis yra vidinis Docker'iui ir nekonfliktuoja su data-plane tinklu

---

## Saugumo sustiprinimo santrauka

| Funkcija | Nauda |
|---|---|
| `user: "10101:10101"` | Ne-root konteinerio procesas |
| `read_only: true` | Nekintama šakninė failų sistema |
| `tmpfs` katalogui `/var/run` | PID failas tik atmintyje |
| `:ro` konfigūracijos montavimas | Konfigūracija negali būti modifikuota iš konteinerio vidaus |
| Tik VIP jungčių susiejimas | Konteineris neklauso mazgo tikruoju IP |
