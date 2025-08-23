#!/bin/bash
# PRS Production Server - Enhanced Backup and Maintenance Script
# Comprehensive backup and maintenance automation for production deployment

set -euo pipefail

BACKUP_BASE_DIR="/mnt/hdd"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/prs-maintenance.log"

# Enhanced configuration
POSTGRES_BACKUP_DIR="$BACKUP_BASE_DIR/postgres-backups/daily"
REDIS_BACKUP_DIR="$BACKUP_BASE_DIR/redis-backups"
APP_BACKUP_DIR="$BACKUP_BASE_DIR/app-backups"
RETENTION_DAYS=30
WEEKLY_RETENTION_DAYS=90

# NAS Configuration
NAS_ENABLED="${BACKUP_TO_NAS:-true}"
NAS_HOST="${NAS_HOST:-}"
NAS_SHARE="${NAS_SHARE:-backups}"
NAS_USERNAME="${NAS_USERNAME:-}"
NAS_PASSWORD="${NAS_PASSWORD:-}"
NAS_MOUNT_PATH="${NAS_MOUNT_PATH:-/mnt/nas}"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/02-docker-configuration/.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

log "Starting PRS maintenance and backup routine"

# Enhanced database backup
enhanced_database_backup() {
    log "Starting enhanced database backup with NAS integration"

    # Mount NAS if enabled
    if [ "$NAS_ENABLED" = "true" ] && [ -n "$NAS_HOST" ]; then
        log "Mounting NAS for backup storage"
        mkdir -p "$NAS_MOUNT_PATH"

        if ! mountpoint -q "$NAS_MOUNT_PATH"; then
            if [ -n "$NAS_USERNAME" ] && [ -n "$NAS_PASSWORD" ]; then
                mount -t cifs "//$NAS_HOST/$NAS_SHARE" "$NAS_MOUNT_PATH" \
                    -o username="$NAS_USERNAME",password="$NAS_PASSWORD",uid=0,gid=0,file_mode=0600,dir_mode=0700 || \
                    log "WARNING: Failed to mount NAS, continuing with local backup only"
            else
                mount -t nfs "$NAS_HOST:/$NAS_SHARE" "$NAS_MOUNT_PATH" || \
                    log "WARNING: Failed to mount NAS, continuing with local backup only"
            fi
        fi
    fi

    # Create backup directories
    mkdir -p "$POSTGRES_BACKUP_DIR"

    if docker ps | grep -q prs-onprem-postgres-timescale; then
        log "Creating comprehensive PostgreSQL database backup"

        # Pre-backup checks
        if ! docker exec prs-onprem-postgres-timescale pg_isready -U "${POSTGRES_USER:-prs_user}"; then
            error_exit "Database not ready for backup"
        fi

        # Check available space (require 2GB free)
        local available_space=$(df "$POSTGRES_BACKUP_DIR" | awk 'NR==2 {print $4}')
        if [ "$available_space" -lt 2000000 ]; then
            error_exit "Insufficient disk space for backup"
        fi

        # Create backup with verification
        local backup_file="$POSTGRES_BACKUP_DIR/prs_db_backup_$DATE.sql"

        if docker exec prs-onprem-postgres-timescale pg_dump \
            -U "${POSTGRES_USER:-prs_user}" \
            -d "${POSTGRES_DB:-prs_production}" \
            --verbose \
            --format=custom \
            --compress=9 \
            --no-owner \
            --no-privileges \
            > "$backup_file"; then

            # Verify backup size
            local backup_size=$(stat -c%s "$backup_file")
            if [ "$backup_size" -lt 100000 ]; then  # At least 100KB
                error_exit "Backup file too small, possible corruption"
            fi

            # Compress and generate checksum
            gzip "$backup_file"
            sha256sum "${backup_file}.gz" > "${backup_file}.gz.sha256"

            log "PostgreSQL backup completed: $(numfmt --to=iec $backup_size) compressed"

            # Copy to NAS if available
            if [ "$NAS_ENABLED" = "true" ] && mountpoint -q "$NAS_MOUNT_PATH"; then
                local nas_postgres_dir="$NAS_MOUNT_PATH/postgres-backups/daily"
                mkdir -p "$nas_postgres_dir"

                if cp "${backup_file}.gz" "$nas_postgres_dir/" && cp "${backup_file}.gz.sha256" "$nas_postgres_dir/"; then
                    log "Database backup copied to NAS successfully"
                else
                    log "WARNING: Failed to copy database backup to NAS"
                fi
            fi
        else
            error_exit "Database backup failed"
        fi

        # Cleanup old local backups with enhanced retention
        find "$POSTGRES_BACKUP_DIR" -name "prs_db_backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete
        log "Cleaned up old local database backups (retention: $RETENTION_DAYS days)"

        # Cleanup old NAS backups
        if [ "$NAS_ENABLED" = "true" ] && mountpoint -q "$NAS_MOUNT_PATH"; then
            local nas_postgres_dir="$NAS_MOUNT_PATH/postgres-backups/daily"
            find "$nas_postgres_dir" -name "prs_db_backup_*.sql.gz" -mtime +$WEEKLY_RETENTION_DAYS -delete 2>/dev/null || true
            log "Cleaned up old NAS database backups (retention: $WEEKLY_RETENTION_DAYS days)"
        fi
    else
        log "WARNING: PostgreSQL container not running, skipping database backup"
    fi
}

# Enhanced Redis backup
enhanced_redis_backup() {
    log "Starting enhanced Redis backup"

    mkdir -p "$REDIS_BACKUP_DIR"

    if docker ps | grep -q prs-onprem-redis; then
        log "Creating Redis backup"

        # Create Redis backup
        if docker exec prs-onprem-redis redis-cli -a "${REDIS_PASSWORD:-}" --rdb "/data/redis_backup_$DATE.rdb" --no-auth-warning; then

            # Copy backup from container
            docker cp "prs-onprem-redis:/data/redis_backup_$DATE.rdb" "$REDIS_BACKUP_DIR/"

            # Compress and verify
            gzip "$REDIS_BACKUP_DIR/redis_backup_$DATE.rdb"
            local backup_size=$(stat -c%s "$REDIS_BACKUP_DIR/redis_backup_$DATE.rdb.gz")

            log "Redis backup completed: $(numfmt --to=iec $backup_size)"
        else
            log "WARNING: Redis backup failed"
        fi

        # Cleanup old Redis backups
        find "$REDIS_BACKUP_DIR" -name "redis_backup_*.rdb.gz" -mtime +$RETENTION_DAYS -delete
    else
        log "WARNING: Redis container not running, skipping Redis backup"
    fi
}

# Application data backup
enhanced_application_backup() {
    log "Starting application data backup"

    local app_backup_date_dir="$APP_BACKUP_DIR/$DATE"
    mkdir -p "$app_backup_date_dir"

    # Backup uploads directory
    if [ -d "/mnt/ssd/uploads" ]; then
        log "Backing up uploads directory"
        tar -czf "$app_backup_date_dir/uploads.tar.gz" -C /mnt/ssd uploads/
    fi

    # Backup configuration
    log "Backing up configuration files"
    tar -czf "$app_backup_date_dir/configuration.tar.gz" \
        -C "$PROJECT_DIR" 02-docker-configuration/

    # Backup SSL certificates
    if [ -d "$PROJECT_DIR/02-docker-configuration/ssl" ]; then
        log "Backing up SSL certificates"
        tar -czf "$app_backup_date_dir/ssl-certificates.tar.gz" \
            -C "$PROJECT_DIR/02-docker-configuration" ssl/
    fi

    # Backup recent logs
    log "Backing up recent application logs"
    find /mnt/ssd/logs -name "*.log" -mtime -7 2>/dev/null | \
    tar -czf "$app_backup_date_dir/recent-logs.tar.gz" --files-from=- 2>/dev/null || true

    # Generate backup manifest
    cat > "$app_backup_date_dir/manifest.txt" << EOF
PRS Application Data Backup
Date: $(date)
Hostname: $(hostname)
Backup Contents:
- uploads.tar.gz: User uploaded files
- configuration.tar.gz: Docker configuration
- ssl-certificates.tar.gz: SSL certificates
- recent-logs.tar.gz: Application logs (7 days)

Total Size: $(du -sh "$app_backup_date_dir" | cut -f1)
EOF

    # Cleanup old application backups
    find "$APP_BACKUP_DIR" -maxdepth 1 -type d -name "20*" -mtime +$RETENTION_DAYS -exec rm -rf {} \;

    log "Application data backup completed: $app_backup_date_dir"
}

# Enhanced maintenance functions
enhanced_log_management() {
    log "Starting enhanced log management"

    # Create archive directory
    mkdir -p /mnt/hdd/app-logs-archive

    # Archive and compress old logs
    find /mnt/ssd/logs -name "*.log" -mtime +1 -exec gzip {} \;
    find /mnt/ssd/logs -name "*.log.gz" -mtime +7 -exec mv {} /mnt/hdd/app-logs-archive/ \;

    # Clean very old archived logs
    find /mnt/hdd/app-logs-archive -name "*.log.gz" -mtime +$WEEKLY_RETENTION_DAYS -delete

    log "Log management completed"
}

enhanced_docker_cleanup() {
    log "Starting enhanced Docker cleanup"

    # Get disk usage before cleanup
    local before_usage=$(docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}" | grep "Total" | awk '{print $3}')

    # Comprehensive Docker cleanup
    docker system prune -f --volumes
    docker image prune -af --filter "until=168h"
    docker container prune -f
    docker network prune -f

    # Get disk usage after cleanup
    local after_usage=$(docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}" | grep "Total" | awk '{print $3}')

    log "Docker cleanup completed: $before_usage -> $after_usage"
}

enhanced_system_maintenance() {
    log "Starting enhanced system maintenance"

    # System cleanup
    apt-get autoremove -y
    apt-get autoclean

    # Clear temporary files
    find /tmp -type f -mtime +7 -delete 2>/dev/null || true
    find /var/tmp -type f -mtime +7 -delete 2>/dev/null || true

    # Update package database
    apt-get update

    # Check for security updates
    local security_updates=$(apt list --upgradable 2>/dev/null | grep security | wc -l)
    if [ "$security_updates" -gt 0 ]; then
        log "WARNING: $security_updates security updates available"
    fi

    log "System maintenance completed"
}

enhanced_database_optimization() {
    log "Starting database optimization"

    if docker ps | grep -q prs-onprem-postgres-timescale; then
        # Daily light maintenance
        log "Running daily database maintenance"
        docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "ANALYZE;"

        # Weekly comprehensive maintenance
        local week_day=$(date +%u)
        if [ "$week_day" = "7" ]; then
            log "Running weekly database optimization"
            docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "
            SET maintenance_work_mem = '1GB';
            VACUUM ANALYZE;
            "

            # TimescaleDB specific maintenance
            docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "
            SELECT compress_chunk(chunk_name)
            FROM timescaledb_information.chunks
            WHERE range_start < NOW() - INTERVAL '7 days'
            AND NOT is_compressed
            LIMIT 10;
            "
        fi

        log "Database optimization completed"
    else
        log "WARNING: PostgreSQL container not running, skipping database optimization"
    fi
}

# Main execution
main() {
    # Execute all backup and maintenance functions
    enhanced_database_backup
    enhanced_redis_backup
    enhanced_application_backup
    enhanced_log_management
    enhanced_docker_cleanup
    enhanced_system_maintenance
    enhanced_database_optimization

    # Update packages if requested
    if [ "${1:-}" = "--update-packages" ]; then
        log "Updating system packages"
        apt-get update && apt-get upgrade -y
    fi

    log "Enhanced maintenance routine completed successfully"

    # Unmount NAS
    if [ "$NAS_ENABLED" = "true" ] && mountpoint -q "$NAS_MOUNT_PATH"; then
        umount "$NAS_MOUNT_PATH" || log "WARNING: Failed to unmount NAS"
        log "NAS unmounted"
    fi

    # Send completion notification
    if command -v mail >/dev/null 2>&1; then
        local backup_status="Local backups completed"
        if [ "$NAS_ENABLED" = "true" ]; then
            backup_status="Local and NAS backups completed"
        fi

        echo "PRS maintenance completed successfully at $(date). Backup status: $backup_status" | \
        mail -s "PRS Maintenance Complete" "${ADMIN_EMAIL:-admin@prs.client-domain.com}"
    fi
}

# Execute main function
main "$@"
