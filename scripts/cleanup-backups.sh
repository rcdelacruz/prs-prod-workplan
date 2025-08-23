#!/bin/bash
# /opt/prs-deployment/scripts/cleanup-backups.sh
# Clean up old backups based on retention policies for PRS on-premises deployment

set -euo pipefail

LOG_FILE="/var/log/prs-backup-cleanup.log"

# Retention policies (days)
DAILY_RETENTION=30
INCREMENTAL_RETENTION=7
APP_BACKUP_RETENTION=14
WAL_RETENTION=7

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
    log_message "Starting backup cleanup"

    # Clean daily backups
    log_message "Cleaning daily backups (retention: $DAILY_RETENTION days)"
    DELETED=$(find /mnt/hdd/postgres-backups/daily -name "prs_full_backup_*" -mtime +$DAILY_RETENTION -delete -print | wc -l)
    log_message "Deleted $DELETED old daily backups"

    # Clean incremental backups
    log_message "Cleaning incremental backups (retention: $INCREMENTAL_RETENTION days)"
    DELETED=$(find /mnt/hdd/postgres-backups/incremental -name "prs_incremental_backup_*" -mtime +$INCREMENTAL_RETENTION -delete -print | wc -l)
    log_message "Deleted $DELETED old incremental backups"

    # Clean application backups
    log_message "Cleaning application backups (retention: $APP_BACKUP_RETENTION days)"
    DELETED=$(find /mnt/hdd/app-backups -maxdepth 1 -type d -name "20*" -mtime +$APP_BACKUP_RETENTION -exec rm -rf {} \; -print | wc -l)
    log_message "Deleted $DELETED old application backup directories"

    # Clean WAL archives
    log_message "Cleaning WAL archives (retention: $WAL_RETENTION days)"
    DELETED=$(find /mnt/hdd/wal-archive -name "*.wal" -mtime +$WAL_RETENTION -delete -print | wc -l)
    log_message "Deleted $DELETED old WAL files"

    # Report storage savings
    log_message "Backup cleanup completed"

    # Check remaining storage
    BACKUP_USAGE=$(du -sh /mnt/hdd/postgres-backups | cut -f1)
    WAL_USAGE=$(du -sh /mnt/hdd/wal-archive | cut -f1)
    APP_USAGE=$(du -sh /mnt/hdd/app-backups | cut -f1)

    log_message "Current backup storage usage:"
    log_message "  Database backups: $BACKUP_USAGE"
    log_message "  WAL archives: $WAL_USAGE"
    log_message "  Application backups: $APP_USAGE"
}

main "$@"
