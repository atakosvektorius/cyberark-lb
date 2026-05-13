# `nginx.conf.template` — Layer 4 TCP srautų konfigūracija

> **Paskirtis:** Apibrėžia Nginx kaip **Layer 4 (TCP) atvirkštinį proxy**, kuris balansuoja tris CyberArk paslaugas per du upstream serverius kiekvienai. Tai yra **šablonas** — `${VAR}` vietos žymekliai pakeičiami `envsubst` diegimo metu.

---

## Apžvalga

Ši konfigūracija naudoja Nginx `stream {}` modulį (ne `http {}`). Visas srautas tvarkomas kaip grynasis TCP; Nginx niekada nenutraukia TLS ir netikrina HTTP turinio.

| Paslauga | Vidinė klausymo jungtis | Išorinė jungtis (VIP) | Upstream jungtis | Balansavimo algoritmas |
|---|---|---|---|---|
| PVWA (HTTPS) | 8443 | 443 | 443 | `hash $remote_addr consistent` |
| PSM (RDP) | 3389 | 3389 | 3389 | `least_conn` |
| PSMP (SSH) | 2222 | 2222 | 22 | `least_conn` |

---

## Pagrindinių nustatymų blokas

```nginx
worker_processes auto;
worker_rlimit_nofile 65535;
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;
```

| Direktyva | Ką daro |
|---|---|
| `worker_processes auto` | Sukuria vieną worker procesą kiekvienam CPU branduoliui, maksimizuojant lygiagretumą. |
| `worker_rlimit_nofile 65535` | Padidina failų deskriptorių limitą vienam worker procesui. Kiekviena proxy TCP jungtis naudoja du failų deskriptorius (klientas ↔ nginx + nginx ↔ upstream). |
| `error_log ... notice` | Rašo įspėjimus ir aukštesnius pranešimus į primontuotą tomą. `notice` lygis fiksuoja jungčių klaidas be derinimo triukšmo. |
| `pid /var/run/nginx.pid` | Saugo pagrindinio proceso PID tmpfs montavime (žr. `docker-compose.yml`). Reikalingas maloningam perkrovimui per `kill -USR1`. |

---

## Events blokas

```nginx
events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}
```

| Direktyva | Ką daro |
|---|---|
| `worker_connections 4096` | Kiekvienas worker procesas gali apdoroti iki 4096 vienalaikių jungčių. Su `auto` worker procesais tai suteikia `branduoliai × 4096` bendrą talpą. |
| `use epoll` | Parenka Linux `epoll` įvykių pranešimo mechanizmą — efektyviausią dideliam jungčių skaičiui. |
| `multi_accept on` | Kai worker procesas pažadinamas, jis priima **visas** laukiančias jungtis iš karto, o ne po vieną, sumažinant konteksto perjungimus. |

---

## Stream blokas — Upstream apibrėžimai

### 1. PVWA (HTTPS/443) — `pvwa_servers`

```nginx
upstream pvwa_servers {
    hash $remote_addr consistent;
    server ${PVWA_UPSTREAM_1}:443 max_fails=2 fail_timeout=30s;
    server ${PVWA_UPSTREAM_2}:443 max_fails=2 fail_timeout=30s;
}
```

| Elementas | Ką daro |
|---|---|
| `hash $remote_addr consistent` | **Nuoseklus maišymas** (consistent hashing) pagal kliento šaltinio IP. Tas pats klientas visada pasiekia tą patį PVWA serverį, išsaugant HTTPS sesijos slapukus. `consistent` raktažodis naudoja ketama stiliaus maišymo žiedą, todėl serverių pridėjimas/pašalinimas perpaskirsto tik mažumą klientų. |
| `max_fails=2` | Po **2** iš eilės nepavykusių prisijungimo bandymų serveris pažymimas kaip neveikiantis. |
| `fail_timeout=30s` | Serveris lieka „neveikiantis" **30 sekundžių** prieš Nginx bandant prie jo jungčiai dar kartą. Tai taip pat apibrėžia langą, per kurį skaičiuojami `max_fails`. |

**Kodėl nuoseklus maišymas PVWA?** PVWA yra žiniatinklio programa, naudojanti sesijos slapukus. Jei klientas būtų nukreipiamas tarp skirtingų serverių, jo sesija būtų prarasta. Nuoseklus maišymas užtikrina „minkštą" sesijos priskyrimą be programos lygio inspekcijos.

### 2. PSM (RDP/3389) — `psm_servers`

```nginx
upstream psm_servers {
    least_conn;
    server ${PSM_UPSTREAM_1}:3389 max_fails=2 fail_timeout=30s;
    server ${PSM_UPSTREAM_2}:3389 max_fails=2 fail_timeout=30s;
}
```

| Elementas | Ką daro |
|---|---|
| `least_conn` | Nukreipia kiekvieną naują jungtį į serverį su **mažiausiai aktyvių jungčių**. Idealus ilgalaikėms RDP sesijoms, kur jungties trukmė labai skiriasi. |

### 3. PSMP (SSH/22) — `psmp_servers`

```nginx
upstream psmp_servers {
    least_conn;
    server ${PSMP_UPSTREAM_1}:22 max_fails=2 fail_timeout=30s;
    server ${PSMP_UPSTREAM_2}:22 max_fails=2 fail_timeout=30s;
}
```

Tas pats algoritmas kaip PSM — `least_conn` yra optimalus ilgalaikėms SSH sesijoms.

---

## Stream blokas — Server (klausytojas) apibrėžimai

### PVWA klausytojas

```nginx
server {
    listen 8443;
    proxy_pass pvwa_servers;
    proxy_connect_timeout 3s;
    proxy_timeout 120s;
}
```

| Direktyva | Ką daro |
|---|---|
| `listen 8443` | Prisiriša prie 8443 jungties konteinerio viduje. Docker susieja `VIP:443 → 8443` (žr. `docker-compose.yml`). |
| `proxy_pass pvwa_servers` | Persiunčia TCP srautą į `pvwa_servers` upstream grupę. |
| `proxy_connect_timeout 3s` | Jei upstream nepriima TCP jungties per **3 sekundes**, Nginx bando kitą serverį. Greitas failover. |
| `proxy_timeout 120s` | Jei jokių duomenų nepersiunčiama abiem kryptimis **2 minutes**, jungtis uždaroma. Žiniatinklio srautas paprastai trumpalaikis, todėl 2 minutės yra dosni riba. |

### PSM klausytojas

```nginx
server {
    listen 3389 so_keepalive=60s:15s:3;
    proxy_pass psm_servers;
    proxy_socket_keepalive on;
    proxy_connect_timeout 3s;
    proxy_timeout 2h;
}
```

| Direktyva | Ką daro |
|---|---|
| `listen 3389 so_keepalive=60s:15s:3` | Įjungia **OS lygio TCP keepalive** kliento sąsajos lizde: 60 s neaktyvumo prieš pirmą zondą, zondas kas 15 s, nutraukimas po 3 praleistų zondų. Tai aptinka neveikiančius klientus (pvz., nešiojamojo dangtis uždarytas). |
| `proxy_socket_keepalive on` | Įjungia TCP keepalive ir **upstream** jungtims, aptinkant neveikiančius PSM serverius. |
| `proxy_timeout 2h` | RDP sesijos gali būti neaktyvios ilgus laikotarpius; **2 valandos** tai atliepia. |

### PSMP klausytojas

```nginx
server {
    listen 2222 so_keepalive=60s:15s:3;
    proxy_pass psmp_servers;
    proxy_socket_keepalive on;
    proxy_connect_timeout 3s;
    proxy_timeout 2h;
}
```

Identiška PSM. SSH sesijos taip pat yra ilgalaikės ir naudojasi tokiais pačiais keepalive ir timeout nustatymais.

> **Pastaba:** PSMP klauso jungties **2222** (ne 22), kad nekonfliktuotų su serverio SSH demonu. Docker susieja `VIP:2222 → container:2222`, o Nginx tada proxy'ina į tikrus PSMP serverius per jungtį 22.
