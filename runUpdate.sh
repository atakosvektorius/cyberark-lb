#!/bin/env bash

# preparing directories:
mkdir -p $(pwd)/nginx-data/logs $(pwd)/nginx-data/cache
sudo chown -R 10101:10101 $(pwd)/nginx-data

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load environment variables
set -a
source "$SCRIPT_DIR/.env"
set +a

# Re-render nginx.conf from template
envsubst '${PVWA_UPSTREAM_1} ${PVWA_UPSTREAM_2} ${PSM_UPSTREAM_1} ${PSM_UPSTREAM_2} ${PSMP_UPSTREAM_1} ${PSMP_UPSTREAM_2}' \
    < "$SCRIPT_DIR/nginx.conf.template" > "$SCRIPT_DIR/nginx.conf"
echo "✓ nginx.conf rendered from template"

# Re-render keepalived.conf based on NODE_ROLE
case "$NODE_ROLE" in
  primary)
    envsubst '${DATAPLANE_VIP} ${DATAPLANE_IP_PRIMARY} ${DATAPLANE_IP_BACKUP}' \
        < "$SCRIPT_DIR/keepalived.conf.primary" | sudo tee /etc/keepalived/keepalived.conf > /dev/null
    ;;
  backup)
    envsubst '${DATAPLANE_VIP} ${DATAPLANE_IP_PRIMARY} ${DATAPLANE_IP_BACKUP}' \
        < "$SCRIPT_DIR/keepalived.conf.backup" | sudo tee /etc/keepalived/keepalived.conf > /dev/null
    ;;
  *)
    echo "ERROR: NODE_ROLE must be 'primary' or 'backup' in .env"
    exit 1
    ;;
esac
echo "✓ keepalived.conf rendered ($NODE_ROLE)"

# Restart keepalived to pick up new config
sudo systemctl restart keepalived
echo "✓ keepalived restarted"

# Recreate nginx container with new config
sudo docker compose down && sudo docker compose up -d
echo "✓ docker compose restarted"
