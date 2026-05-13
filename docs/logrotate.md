# Logrotate Configuration — `cyberark-nginx`

> **Purpose:** Rotates the Nginx access and error logs daily, keeping 7 days of compressed history, and signals the containerised Nginx to reopen its log files after rotation.

---

## Full Source

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

## Directive-by-Directive Walkthrough

| Directive | What it does |
|---|---|
| `/home/pam/cyberARK-lb/nginx-data/logs/*.log` | **Path pattern** — matches all `.log` files in the Nginx log directory. Adjust this path if the project is cloned to a different location. |
| `daily` | Rotate logs **once per day**. |
| `missingok` | Don't report an error if the log file is missing (e.g., first run before any traffic). |
| `rotate 7` | Keep **7 rotated files** (= 7 days of history). Older files are deleted. |
| `compress` | Compress rotated files with gzip (`.gz`). |
| `delaycompress` | Don't compress the **most recent** rotated file. This avoids compressing a file that Nginx might still be writing to during the brief rotation window. The file is compressed on the **next** rotation cycle. |
| `notifempty` | Skip rotation if the log file is **empty**. |
| `create 0640 101 101` | After rotation, create a new empty log file with permissions `0640` owned by UID:GID `101:101`. |
| `sharedscripts` | Run the `postrotate` script **once** for all matched files (not once per file). |
| `postrotate ... endscript` | After rotating, send `USR1` to the Nginx master process inside the container. `USR1` tells Nginx to **reopen log files** — this is Nginx's graceful log rotation signal. Without this, Nginx would keep writing to the old (now rotated) file descriptor. |

---

## How the `postrotate` Signal Works

```
docker exec cyberark-lb sh -c "kill -USR1 $(cat /var/run/nginx.pid)"
```

1. `docker exec cyberark-lb` — runs a command inside the running container named `cyberark-lb`
2. `cat /var/run/nginx.pid` — reads the Nginx master process PID from the tmpfs mount
3. `kill -USR1 <PID>` — sends the USR1 signal to Nginx master
4. Nginx master tells each worker to close and reopen log files
5. Workers start writing to the new (empty) log files

---

## Customisation Notes

- **Log path**: If you clone the repo to a directory other than `/home/pam/cyberARK-lb/`, update the path in this file and re-run `init.sh` (or manually copy it to `/etc/logrotate.d/`).
- **Retention**: Change `rotate 7` to keep more or fewer days of logs.
- **Compression**: Remove `compress` and `delaycompress` if you want uncompressed logs.
- **UID in `create`**: The `create 0640 101 101` line uses UID 101 — you may want to update this to `10101` to match the actual container user. The container writes logs as UID 10101, so the ownership should match.
