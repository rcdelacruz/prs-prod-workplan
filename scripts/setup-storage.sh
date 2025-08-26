#!/bin/bash
# PRS Production Server - Storage Setup Script
# Creates optimized directory structure for HDD-only storage (simplified configuration)

set -e

# Load environment for storage path
if [ -f ".env" ]; then
    source .env
fi

HDD_PATH="${STORAGE_HDD_PATH:-/mnt/hdd}"

echo "Setting up PRS production storage directories (HDD-only configuration)..."
echo "Using HDD path: $HDD_PATH"

# Create HDD storage directories (all data on HDD for simplicity)
sudo mkdir -p "$HDD_PATH"/{postgresql-data,postgres-wal-archive,postgres-backups,redis-data,redis-backups,nginx-cache,uploads,logs,app-logs-archive,worker-logs-archive,prometheus-data,prometheus-archive,grafana-data,portainer-data,backups,archives}

# Set appropriate ownership and permissions
sudo chown -R 999:999 "$HDD_PATH"/postgresql-data "$HDD_PATH"/postgres-wal-archive "$HDD_PATH"/postgres-backups
sudo chown -R 999:999 "$HDD_PATH"/redis-data "$HDD_PATH"/redis-backups
sudo chown -R 472:472 "$HDD_PATH"/grafana-data
sudo chown -R 65534:65534 "$HDD_PATH"/prometheus-data "$HDD_PATH"/prometheus-archive
sudo chown -R www-data:www-data "$HDD_PATH"/nginx-cache "$HDD_PATH"/uploads
sudo chown -R 1000:1000 "$HDD_PATH"/logs "$HDD_PATH"/app-logs-archive "$HDD_PATH"/worker-logs-archive
sudo chown -R root:root "$HDD_PATH"/portainer-data "$HDD_PATH"/backups "$HDD_PATH"/archives

# Set appropriate permissions
sudo chmod 700 "$HDD_PATH"/postgresql-data
sudo chmod 755 "$HDD_PATH"/redis-data "$HDD_PATH"/redis-backups
sudo chmod 755 "$HDD_PATH"/nginx-cache "$HDD_PATH"/uploads "$HDD_PATH"/logs
sudo chmod 755 "$HDD_PATH"/app-logs-archive "$HDD_PATH"/worker-logs-archive
sudo chmod 755 "$HDD_PATH"/prometheus-data "$HDD_PATH"/prometheus-archive
sudo chmod 755 "$HDD_PATH"/grafana-data "$HDD_PATH"/portainer-data
sudo chmod 755 "$HDD_PATH"/postgres-wal-archive "$HDD_PATH"/postgres-backups
sudo chmod 755 "$HDD_PATH"/backups "$HDD_PATH"/archives

echo "Storage directory structure created successfully!"
echo "HDD directories: $HDD_PATH/"
echo ""
echo "Benefits of HDD-only configuration:"
echo "- Simplified management (single storage tier)"
echo "- Lower cost per GB"
echo "- Easy expansion"
echo "- Adequate performance for most workloads"
