#!/bin/bash
# /opt/prs-deployment/scripts/backup-full.sh
# Comprehensive database backup with verification for PRS on-premises deployment

set -euo pipefail

# Configuration
LOCAL_BACKUP_DIR="/mnt/hdd/postgres-backups/daily"
NAS_BACKUP_DIR="${NAS_MOUNT_PATH:-/mnt/nas}/postgres-backups/daily"
RETENTION_DAYS=30
NAS_RETENTION_DAYS=90
COMPRESSION_LEVEL=9
ENCRYPT_KEY="backup@prs.client-domain.com"
LOG_FILE="/var/log/prs-backup.log"

# NAS Configuration
NAS_ENABLED="${BACKUP_TO_NAS:-true}"
NAS_HOST="${NAS_HOST:-}"
NAS_SHARE="${NAS_SHARE:-backups}"
NAS_USERNAME="${NAS_USERNAME:-}"
NAS_PASSWORD="${NAS_PASSWORD:-}"
NAS_MOUNT_PATH="${NAS_MOUNT_PATH:-/mnt/nas}"

# Database connection settings (from docker-compose)
PGHOST="prs-onprem-postgres-timescale"
PGPORT="5432"
PGUSER="${POSTGRES_USER:-prs_user}"
PGDATABASE="${POSTGRES_DB:-prs_production}"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/02-docker-configuration/.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_message "ERROR: $1"
    exit 1
}

# NAS mounting function
mount_nas() {
    if [ "$NAS_ENABLED" != "true" ]; then
        log_message "NAS backup disabled, skipping NAS mount"
        return 0
    fi

    if [ -z "$NAS_HOST" ]; then
        log_message "WARNING: NAS_HOST not configured, skipping NAS backup"
        return 1
    fi

    log_message "Mounting NAS for backup storage"

    # Create mount point
    mkdir -p "$NAS_MOUNT_PATH"

    # Check if already mounted
    if mountpoint -q "$NAS_MOUNT_PATH"; then
        log_message "NAS already mounted at $NAS_MOUNT_PATH"
        return 0
    fi

    # Mount NAS (supports both CIFS/SMB and NFS)
    if [ -n "$NAS_USERNAME" ] && [ -n "$NAS_PASSWORD" ]; then
        # CIFS/SMB mount
        log_message "Mounting CIFS/SMB share: //$NAS_HOST/$NAS_SHARE"
        if ! mount -t cifs "//$NAS_HOST/$NAS_SHARE" "$NAS_MOUNT_PATH" \
            -o username="$NAS_USERNAME",password="$NAS_PASSWORD",uid=0,gid=0,file_mode=0600,dir_mode=0700; then
            log_message "ERROR: Failed to mount NAS via CIFS/SMB"
            return 1
        fi
    else
        # NFS mount
        log_message "Mounting NFS share: $NAS_HOST:/$NAS_SHARE"
        if ! mount -t nfs "$NAS_HOST:/$NAS_SHARE" "$NAS_MOUNT_PATH"; then
            log_message "ERROR: Failed to mount NAS via NFS"
            return 1
        fi
    fi

    log_message "NAS mounted successfully at $NAS_MOUNT_PATH"
    return 0
}

# NAS unmounting function
unmount_nas() {
    if [ "$NAS_ENABLED" != "true" ]; then
        return 0
    fi

    if mountpoint -q "$NAS_MOUNT_PATH"; then
        log_message "Unmounting NAS"
        umount "$NAS_MOUNT_PATH" || log_message "WARNING: Failed to unmount NAS"
    fi
}

# Copy backup to NAS
copy_to_nas() {
    local backup_file="$1"

    if [ "$NAS_ENABLED" != "true" ]; then
        log_message "NAS backup disabled, skipping NAS copy"
        return 0
    fi

    if ! mountpoint -q "$NAS_MOUNT_PATH"; then
        log_message "WARNING: NAS not mounted, skipping NAS copy"
        return 1
    fi

    log_message "Copying backup to NAS"

    # Create NAS backup directory
    mkdir -p "$NAS_BACKUP_DIR"

    # Copy backup file and checksum to NAS
    local backup_filename=$(basename "$backup_file")
    local nas_backup_file="$NAS_BACKUP_DIR/$backup_filename"

    if cp "$backup_file" "$nas_backup_file"; then
        log_message "Backup copied to NAS: $nas_backup_file"

        # Copy checksum file if it exists
        if [ -f "${backup_file}.sha256" ]; then
            cp "${backup_file}.sha256" "${nas_backup_file}.sha256"
            log_message "Checksum copied to NAS"
        fi

        # Verify NAS copy
        local local_size=$(stat -c%s "$backup_file")
        local nas_size=$(stat -c%s "$nas_backup_file")

        if [ "$local_size" -eq "$nas_size" ]; then
            log_message "NAS copy verified: $(numfmt --to=iec $nas_size)"
        else
            log_message "ERROR: NAS copy size mismatch"
            return 1
        fi
    else
        log_message "ERROR: Failed to copy backup to NAS"
        return 1
    fi

    return 0
}

# Main backup function
main() {
    local DATE=$(date +%Y%m%d_%H%M%S)
    local BACKUP_FILE="$LOCAL_BACKUP_DIR/prs_full_backup_${DATE}.sql"

    log_message "Starting full database backup with NAS integration"

    # Mount NAS if enabled
    if [ "$NAS_ENABLED" = "true" ]; then
        mount_nas || log_message "WARNING: NAS mount failed, continuing with local backup only"
    fi

    # Create local backup directory
    mkdir -p "$LOCAL_BACKUP_DIR" || error_exit "Failed to create local backup directory"

    # Pre-backup checks
    log_message "Performing pre-backup checks"

    # Check database connectivity
    if ! docker exec prs-onprem-postgres-timescale pg_isready -U "$PGUSER"; then
        error_exit "Database not ready"
    fi

    # Check available space (require 5GB free)
    local AVAILABLE_SPACE=$(df "$LOCAL_BACKUP_DIR" | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 5000000 ]; then
        error_exit "Insufficient disk space for backup"
    fi

    # Check NAS space if enabled
    if [ "$NAS_ENABLED" = "true" ] && mountpoint -q "$NAS_MOUNT_PATH"; then
        local NAS_AVAILABLE_SPACE=$(df "$NAS_MOUNT_PATH" | awk 'NR==2 {print $4}')
        if [ "$NAS_AVAILABLE_SPACE" -lt 10000000 ]; then  # Require 10GB free on NAS
            log_message "WARNING: Low NAS disk space: $(numfmt --to=iec $((NAS_AVAILABLE_SPACE * 1024)))"
        fi
    fi

    # Create backup
    log_message "Creating database backup: $BACKUP_FILE"
    if ! docker exec prs-onprem-postgres-timescale pg_dump \
        -U "$PGUSER" \
        -d "$PGDATABASE" \
        --verbose \
        --format=custom \
        --compress=9 \
        --no-owner \
        --no-privileges \
        > "$BACKUP_FILE"; then
        error_exit "Database backup failed"
    fi

    # Verify backup size
    local BACKUP_SIZE=$(stat -c%s "$BACKUP_FILE")
    if [ "$BACKUP_SIZE" -lt 1000000 ]; then  # At least 1MB
        error_exit "Backup file too small, possible corruption"
    fi

    # Compress backup
    log_message "Compressing backup"
    gzip -"$COMPRESSION_LEVEL" "$BACKUP_FILE"
    BACKUP_FILE="${BACKUP_FILE}.gz"

    # Generate checksum
    log_message "Generating checksum"
    sha256sum "$BACKUP_FILE" > "${BACKUP_FILE}.sha256"

    # Encrypt backup (if GPG key available)
    if command -v gpg >/dev/null 2>&1 && gpg --list-keys "$ENCRYPT_KEY" >/dev/null 2>&1; then
        log_message "Encrypting backup"
        gpg --trust-model always --encrypt -r "$ENCRYPT_KEY" "$BACKUP_FILE"
        rm "$BACKUP_FILE"
        BACKUP_FILE="${BACKUP_FILE}.gpg"
    fi

    # Final verification
    local FINAL_SIZE=$(stat -c%s "$BACKUP_FILE")
    log_message "Local backup completed: $BACKUP_FILE ($(numfmt --to=iec $FINAL_SIZE))"

    # Copy to NAS
    if [ "$NAS_ENABLED" = "true" ]; then
        copy_to_nas "$BACKUP_FILE" || log_message "WARNING: NAS copy failed"
    fi

    # Cleanup old local backups
    log_message "Cleaning up old local backups (retention: $RETENTION_DAYS days)"
    find "$LOCAL_BACKUP_DIR" -name "prs_full_backup_*.sql*" -mtime +$RETENTION_DAYS -delete

    # Cleanup old NAS backups
    if [ "$NAS_ENABLED" = "true" ] && mountpoint -q "$NAS_MOUNT_PATH"; then
        log_message "Cleaning up old NAS backups (retention: $NAS_RETENTION_DAYS days)"
        find "$NAS_BACKUP_DIR" -name "prs_full_backup_*.sql*" -mtime +$NAS_RETENTION_DAYS -delete 2>/dev/null || true
    fi

    # Send notification
    if command -v mail >/dev/null 2>&1; then
        local backup_status="Local backup completed"
        if [ "$NAS_ENABLED" = "true" ] && mountpoint -q "$NAS_MOUNT_PATH"; then
            backup_status="Local and NAS backup completed"
        fi

        echo "PRS Database backup completed successfully at $(date). Status: $backup_status" | \
        mail -s "PRS Database Backup Success" "${ADMIN_EMAIL:-admin@prs.client-domain.com}"
    fi

    # Unmount NAS
    unmount_nas

    log_message "Full backup process completed successfully"
}

# Execute main function
main "$@"
