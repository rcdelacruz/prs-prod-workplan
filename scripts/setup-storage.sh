#!/bin/bash
# PRS Production Server - Storage Setup Script
# Creates optimized directory structure for SSD/HDD dual storage

set -e

echo "Setting up PRS production storage directories..."

# Create SSD storage directories (performance-critical data)
sudo mkdir -p /mnt/ssd/{postgresql-data,postgresql-hot,redis-data,redis-persistence,nginx-cache,uploads,logs,prometheus-data,grafana-data,portainer-data}

# Create HDD storage directories (archival and backup data)
sudo mkdir -p /mnt/hdd/{app-logs-archive,worker-logs-archive,postgresql-cold,postgres-wal-archive,postgres-backups,redis-backups,prometheus-archive}

# Set appropriate ownership and permissions
sudo chown -R 999:999 /mnt/ssd/postgresql-data /mnt/ssd/postgresql-hot
sudo chown -R 999:999 /mnt/hdd/postgresql-cold /mnt/hdd/postgres-wal-archive /mnt/hdd/postgres-backups
sudo chown -R 999:999 /mnt/ssd/redis-data /mnt/ssd/redis-persistence /mnt/hdd/redis-backups
sudo chown -R 472:472 /mnt/ssd/grafana-data
sudo chown -R 65534:65534 /mnt/ssd/prometheus-data /mnt/hdd/prometheus-archive
sudo chown -R www-data:www-data /mnt/ssd/nginx-cache /mnt/ssd/uploads
sudo chown -R 1000:1000 /mnt/ssd/logs /mnt/hdd/app-logs-archive /mnt/hdd/worker-logs-archive
sudo chown -R root:root /mnt/ssd/portainer-data

# Set appropriate permissions
sudo chmod 700 /mnt/ssd/postgresql-data /mnt/ssd/postgresql-hot /mnt/hdd/postgresql-cold
sudo chmod 755 /mnt/ssd/redis-data /mnt/ssd/redis-persistence /mnt/hdd/redis-backups
sudo chmod 755 /mnt/ssd/nginx-cache /mnt/ssd/uploads /mnt/ssd/logs
sudo chmod 755 /mnt/hdd/app-logs-archive /mnt/hdd/worker-logs-archive
sudo chmod 755 /mnt/ssd/prometheus-data /mnt/hdd/prometheus-archive
sudo chmod 755 /mnt/ssd/grafana-data /mnt/ssd/portainer-data

echo "Storage directory structure created successfully!"
echo "SSD directories: /mnt/ssd/"
echo "HDD directories: /mnt/hdd/"
