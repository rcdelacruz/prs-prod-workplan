#!/bin/bash
# /opt/prs-deployment/scripts/backup-application-data.sh
# Backup application files and uploads for PRS on-premises deployment

set -euo pipefail

LOCAL_BACKUP_DIR="/mnt/hdd/app-backups"
NAS_BACKUP_DIR="${NAS_MOUNT_PATH:-/mnt/nas}/app-backups"
RETENTION_DAYS=14
NAS_RETENTION_DAYS=60
LOG_FILE="/var/log/prs-backup.log"

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

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# NAS mounting function
mount_nas() {
    if [ "$NAS_ENABLED" != "true" ]; then
        return 0
    fi

    if [ -z "$NAS_HOST" ]; then
        log_message "WARNING: NAS_HOST not configured, skipping NAS backup"
        return 1
    fi

    mkdir -p "$NAS_MOUNT_PATH"

    if mountpoint -q "$NAS_MOUNT_PATH"; then
        return 0
    fi

    if [ -n "$NAS_USERNAME" ] && [ -n "$NAS_PASSWORD" ]; then
        mount -t cifs "//$NAS_HOST/$NAS_SHARE" "$NAS_MOUNT_PATH" \
            -o username="$NAS_USERNAME",password="$NAS_PASSWORD",uid=0,gid=0,file_mode=0600,dir_mode=0700
    else
        mount -t nfs "$NAS_HOST:/$NAS_SHARE" "$NAS_MOUNT_PATH"
    fi
}

# Copy application backup to NAS
copy_app_backup_to_nas() {
    local app_backup_dir="$1"

    if [ "$NAS_ENABLED" != "true" ] || ! mountpoint -q "$NAS_MOUNT_PATH"; then
        return 0
    fi

    log_message "Copying application backup to NAS"

    local backup_date=$(basename "$app_backup_dir")
    local nas_backup_dir="$NAS_BACKUP_DIR/$backup_date"

    if cp -r "$app_backup_dir" "$NAS_BACKUP_DIR/"; then
        log_message "Application backup copied to NAS: $nas_backup_dir"

        # Verify copy
        local local_size=$(du -sb "$app_backup_dir" | cut -f1)
        local nas_size=$(du -sb "$nas_backup_dir" | cut -f1)

        if [ "$local_size" -eq "$nas_size" ]; then
            log_message "NAS copy verified: $(numfmt --to=iec $nas_size)"
        else
            log_message "WARNING: NAS copy size mismatch"
        fi
    else
        log_message "ERROR: Failed to copy application backup to NAS"
    fi
}

main() {
    local DATE=$(date +%Y%m%d_%H%M%S)
    local APP_BACKUP_DIR="$LOCAL_BACKUP_DIR/$DATE"

    log_message "Starting application data backup with NAS integration"

    # Mount NAS if enabled
    if [ "$NAS_ENABLED" = "true" ]; then
        mount_nas || log_message "WARNING: NAS mount failed, continuing with local backup only"
    fi

    # Create local backup directory
    mkdir -p "$APP_BACKUP_DIR"

    # Backup uploads directory
    log_message "Backing up uploads directory"
    if [ -d "/mnt/ssd/uploads" ]; then
        tar -czf "$APP_BACKUP_DIR/uploads.tar.gz" -C /mnt/ssd uploads/
        log_message "Uploads backup completed"
    fi

    # Backup configuration
    log_message "Backing up configuration"
    tar -czf "$APP_BACKUP_DIR/configuration.tar.gz" \
        -C /opt/prs-deployment 02-docker-configuration/

    # Backup SSL certificates
    log_message "Backing up SSL certificates"
    if [ -d "/opt/prs-deployment/02-docker-configuration/ssl" ]; then
        tar -czf "$APP_BACKUP_DIR/ssl-certificates.tar.gz" \
            -C /opt/prs-deployment/02-docker-configuration ssl/
    fi

    # Backup logs (recent only)
    log_message "Backing up recent logs"
    find /mnt/ssd/logs -name "*.log" -mtime -7 | \
    tar -czf "$APP_BACKUP_DIR/recent-logs.tar.gz" --files-from=-

    # Generate manifest
    cat > "$APP_BACKUP_DIR/manifest.txt" << EOF
PRS Application Data Backup
Date: $(date)
Hostname: $(hostname)
Backup Contents:
- uploads.tar.gz: User uploaded files
- configuration.tar.gz: Docker configuration
- ssl-certificates.tar.gz: SSL certificates
- recent-logs.tar.gz: Application logs (7 days)

Backup Size: $(du -sh "$APP_BACKUP_DIR" | cut -f1)
EOF

    # Copy to NAS
    if [ "$NAS_ENABLED" = "true" ]; then
        copy_app_backup_to_nas "$APP_BACKUP_DIR" || log_message "WARNING: NAS copy failed"
    fi

    # Cleanup old local backups
    find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type d -name "20*" -mtime +$RETENTION_DAYS -exec rm -rf {} \;

    # Cleanup old NAS backups
    if [ "$NAS_ENABLED" = "true" ] && mountpoint -q "$NAS_MOUNT_PATH"; then
        log_message "Cleaning up old NAS application backups (retention: $NAS_RETENTION_DAYS days)"
        find "$NAS_BACKUP_DIR" -maxdepth 1 -type d -name "20*" -mtime +$NAS_RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true
    fi

    # Unmount NAS
    if [ "$NAS_ENABLED" = "true" ] && mountpoint -q "$NAS_MOUNT_PATH"; then
        umount "$NAS_MOUNT_PATH" || log_message "WARNING: Failed to unmount NAS"
    fi

    log_message "Application data backup completed: $APP_BACKUP_DIR"
}

main "$@"
