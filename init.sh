#!/bin/env bash

set -e

# Load environment variables
set -a
source "$(dirname "$0")/.env"
set +a

# installing docker:
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# install keepalived
sudo apt install -y keepalived
sudo useradd -r -s /sbin/nologin keepalived_script 2>/dev/null || true

# Create a dedicated user for the nginx container (avoids UID 101 collision with messagebus)
sudo useradd -r -u 10101 -s /sbin/nologin nginx-lb 2>/dev/null || true

# Validate .env variables
for var in NODE_ROLE DATAPLANE_VIP DATAPLANE_IP_PRIMARY DATAPLANE_IP_BACKUP \
           PVWA_UPSTREAM_1 PVWA_UPSTREAM_2 PSM_UPSTREAM_1 PSM_UPSTREAM_2 \
           PSMP_UPSTREAM_1 PSMP_UPSTREAM_2; do
    if [ -z "${!var}" ]; then
        echo "ERROR: $var is not set in .env"
        exit 1
    fi
done

# Set hostname based on node role
case "$NODE_ROLE" in
  primary) sudo hostnamectl set-hostname cyberark-lb-primary ;;
  backup)  sudo hostnamectl set-hostname cyberark-lb-backup  ;;
  *)
    echo "ERROR: NODE_ROLE must be 'primary' or 'backup' in .env"
    exit 1
    ;;
esac

# preparing directories:
mkdir -p $(pwd)/nginx-data/logs $(pwd)/nginx-data/cache
sudo chown -R 10101:10101 $(pwd)/nginx-data

# Allow Docker to bind to the VIP even if this node is currently the BACKUP
sudo sysctl -w net.ipv4.ip_nonlocal_bind=1
echo "net.ipv4.ip_nonlocal_bind=1" | sudo tee -a /etc/sysctl.conf > /dev/null

# Render configs and start services
"$(dirname "$0")/runUpdate.sh"