#!/bin/bash
# /opt/prs-deployment/scripts/backup-incremental.sh
# Incremental backup using WAL files for PRS on-premises deployment

set -euo pipefail

BACKUP_DIR="/mnt/hdd/postgres-backups/incremental"
WAL_ARCHIVE_DIR="/mnt/hdd/wal-archive"
RETENTION_DAYS=7
LOG_FILE="/var/log/prs-backup.log"

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

main() {
    local DATE=$(date +%Y%m%d_%H%M%S)
    local INCREMENTAL_FILE="$BACKUP_DIR/prs_incremental_backup_${DATE}.tar.gz"

    log_message "Starting incremental backup"

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Find WAL files since last full backup
    local LAST_FULL_BACKUP=$(ls -t /mnt/hdd/postgres-backups/daily/prs_full_backup_*.sql* 2>/dev/null | head -1)

    if [ -z "$LAST_FULL_BACKUP" ]; then
        log_message "No full backup found, running full backup first"
        "$SCRIPT_DIR/backup-full.sh"
        return 0
    fi

    log_message "Base backup: $LAST_FULL_BACKUP"

    # Create incremental backup with WAL files newer than last full backup
    log_message "Creating incremental backup: $INCREMENTAL_FILE"

    if find "$WAL_ARCHIVE_DIR" -name "*.wal" -newer "$LAST_FULL_BACKUP" -print0 | \
       tar --null -czf "$INCREMENTAL_FILE" --files-from=-; then
        log_message "Incremental backup completed successfully"
    else
        log_message "ERROR: Incremental backup failed"
        return 1
    fi

    # Generate checksum
    sha256sum "$INCREMENTAL_FILE" > "${INCREMENTAL_FILE}.sha256"

    # Cleanup old incremental backups
    find "$BACKUP_DIR" -name "prs_incremental_backup_*.tar.gz*" -mtime +$RETENTION_DAYS -delete

    local BACKUP_SIZE=$(stat -c%s "$INCREMENTAL_FILE")
    log_message "Incremental backup completed: $INCREMENTAL_FILE ($(numfmt --to=iec $BACKUP_SIZE))"
}

main "$@"
