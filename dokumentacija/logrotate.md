# Logrotate konfigūracija — `cyberark-nginx`

> **Paskirtis:** Rotuoja Nginx prieigos ir klaidų logus kasdien, saugodama 7 dienų suglaudintą istoriją, ir signalizuoja kontainerizuotam Nginx iš naujo atidaryti log failus po rotacijos.

---

## Pilnas šaltinis

```
# /etc/logrotate.d/cyberark-nginx
/home/pam/cyberARK-lb/nginx-data/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 101 101
    sharedscripts
    postrotate
        docker exec cyberark-lb sh -c "kill -USR1 \$(cat /var/run/nginx.pid)"
    endscript
}
```

---

## Direktyvų aprašymas

| Direktyva | Ką daro |
|---|---|
| `/home/pam/cyberARK-lb/nginx-data/logs/*.log` | **Kelio šablonas** — atitinka visus `.log` failus Nginx log kataloge. Pakoreguokite šį kelią, jei projektas klonuotas į kitą vietą. |
| `daily` | Rotuoti logus **kartą per dieną**. |
| `missingok` | Nerodyti klaidos, jei log failas neegzistuoja (pvz., pirmas paleidimas prieš bet kokį srautą). |
| `rotate 7` | Saugoti **7 rotuotus failus** (= 7 dienų istorija). Senesni failai ištrinami. |
| `compress` | Suspausti rotuotus failus su gzip (`.gz`). |
| `delaycompress` | Nespausti **naujausio** rotuoto failo. Tai išvengia failo suspaudimo, į kurį Nginx gali vis dar rašyti trumpo rotacijos lango metu. Failas suspaužiamas **kitame** rotacijos cikle. |
| `notifempty` | Praleisti rotaciją, jei log failas yra **tuščias**. |
| `create 0640 101 101` | Po rotacijos sukurti naują tuščią log failą su teisėmis `0640`, priklausantį UID:GID `101:101`. |
| `sharedscripts` | Vykdyti `postrotate` skriptą **vieną kartą** visiems atitiktiems failams (ne po kartą kiekvienam failui). |
| `postrotate ... endscript` | Po rotacijos siunčia `USR1` signalą Nginx master procesui konteinerio viduje. `USR1` nurodo Nginx **iš naujo atidaryti log failus** — tai yra Nginx maloningo log rotacijos signalas. Be šito Nginx toliau rašytų į seną (jau rotuotą) failo deskriptorių. |

---

## Kaip veikia `postrotate` signalas

```
docker exec cyberark-lb sh -c "kill -USR1 $(cat /var/run/nginx.pid)"
```

1. `docker exec cyberark-lb` — vykdo komandą veikiančio konteinerio `cyberark-lb` viduje
2. `cat /var/run/nginx.pid` — nuskaito Nginx master proceso PID iš tmpfs montavimo
3. `kill -USR1 <PID>` — siunčia USR1 signalą Nginx master procesui
4. Nginx master nurodo kiekvienam worker uždaryti ir iš naujo atidaryti log failus
5. Worker procesai pradeda rašyti į naujus (tuščius) log failus

---

## Pritaikymo pastabos

- **Log kelias**: Jei klonuojate repo į kitą katalogą nei `/home/pam/cyberARK-lb/`, atnaujinkite kelią šiame faile ir pakartotinai paleiskite `init.sh` (arba rankiniu būdu nukopijuokite į `/etc/logrotate.d/`).
- **Saugojimo trukmė**: Pakeiskite `rotate 7`, kad saugotumėte daugiau ar mažiau dienų logų.
- **Suspaudimas**: Pašalinkite `compress` ir `delaycompress`, jei norite nesuspaustų logų.
- **UID `create` direktyvoje**: `create 0640 101 101` eilutė naudoja UID 101 — galbūt norite atnaujinti tai į `10101`, kad atitiktų tikrąjį konteinerio vartotoją. Konteineris rašo logus kaip UID 10101, todėl nuosavybė turėtų sutapti.
