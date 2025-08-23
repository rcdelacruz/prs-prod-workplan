#!/bin/bash
# PRS Production Server - Backup and Maintenance Script

set -e

BACKUP_BASE_DIR="/mnt/hdd"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/prs-maintenance.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE"
}

log "Starting PRS maintenance and backup routine"

# Database backup
if docker ps | grep -q prs-onprem-postgres; then
    log "Creating PostgreSQL database backup"
    docker exec prs-onprem-postgres-timescale pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" | \
        gzip > "$BACKUP_BASE_DIR/postgres-backups/prs_db_backup_$DATE.sql.gz"
    
    # Keep only last 7 days of backups
    find "$BACKUP_BASE_DIR/postgres-backups" -name "prs_db_backup_*.sql.gz" -mtime +7 -delete
    log "PostgreSQL backup completed"
fi

# Redis backup
if docker ps | grep -q prs-onprem-redis; then
    log "Creating Redis backup"
    docker exec prs-onprem-redis redis-cli -a "$REDIS_PASSWORD" --rdb "/data/backups/redis_backup_$DATE.rdb" --no-auth-warning
    find "$BACKUP_BASE_DIR/redis-backups" -name "redis_backup_*.rdb" -mtime +7 -delete
    log "Redis backup completed"
fi

# Archive old logs
log "Archiving old log files"
find /mnt/ssd/logs -name "*.log" -mtime +1 -exec gzip {} \;
find /mnt/ssd/logs -name "*.gz" -mtime +7 -exec mv {} /mnt/hdd/app-logs-archive/ \;

# Docker cleanup
log "Cleaning up Docker resources"
docker system prune -f --volumes
docker image prune -a -f --filter "until=168h"

# System cleanup
log "Performing system cleanup"
sudo apt-get autoremove -y
sudo apt-get autoclean

# Update system packages (if needed)
if [ "$1" = "--update-packages" ]; then
    log "Updating system packages"
    sudo apt-get update && sudo apt-get upgrade -y
fi

# Optimize database (weekly)
WEEK_DAY=$(date +%u)
if [ "$WEEK_DAY" = "7" ] && docker ps | grep -q prs-onprem-postgres; then
    log "Running weekly database optimization"
    docker exec prs-onprem-postgres-timescale psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "VACUUM ANALYZE;"
    docker exec prs-onprem-postgres-timescale psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "REINDEX DATABASE $POSTGRES_DB;"
fi

log "Maintenance routine completed successfully"
