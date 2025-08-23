#!/bin/bash
# /opt/prs-deployment/scripts/restore-point-in-time.sh
# Point-in-time recovery using WAL files for PRS on-premises deployment

set -euo pipefail

RECOVERY_TIME="$1"
RECOVERY_DIR="/tmp/prs-recovery-$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/prs-restore.log"
WAL_ARCHIVE_DIR="/mnt/hdd/wal-archive"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/02-docker-configuration/.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

if [ -z "$RECOVERY_TIME" ]; then
    echo "Usage: $0 'YYYY-MM-DD HH:MM:SS'"
    echo "Example: $0 '2024-08-22 14:30:00'"
    exit 1
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log_message "ERROR: $1"
    exit 1
}

main() {
    log_message "Starting point-in-time recovery to: $RECOVERY_TIME"

    # Create recovery directory
    mkdir -p "$RECOVERY_DIR"

    # Find the latest full backup before recovery time
    local RECOVERY_EPOCH=$(date -d "$RECOVERY_TIME" +%s)
    local BASE_BACKUP=""

    for backup in $(ls -t /mnt/hdd/postgres-backups/daily/prs_full_backup_*.sql* 2>/dev/null); do
        local BACKUP_TIME=$(stat -c %Y "$backup")
        if [ "$BACKUP_TIME" -lt "$RECOVERY_EPOCH" ]; then
            BASE_BACKUP="$backup"
            break
        fi
    done

    if [ -z "$BASE_BACKUP" ]; then
        error_exit "No suitable base backup found before recovery time"
    fi

    log_message "Using base backup: $BASE_BACKUP"

    # Stop application services
    log_message "Stopping application services"
    docker-compose -f "$PROJECT_DIR/02-docker-configuration/docker-compose.onprem.yml" \
        stop frontend backend worker

    # Stop database
    log_message "Stopping database"
    docker-compose -f "$PROJECT_DIR/02-docker-configuration/docker-compose.onprem.yml" \
        stop postgres

    # Create recovery configuration
    log_message "Setting up recovery configuration"

    # Restore base backup to recovery directory
    log_message "Restoring base backup"
    if [[ "$BASE_BACKUP" == *.gpg ]]; then
        gpg --quiet --decrypt "$BASE_BACKUP" | gunzip | \
        docker run --rm -i -v "$RECOVERY_DIR:/recovery" timescale/timescaledb:latest-pg15 \
        pg_restore --clean --if-exists --verbose -d template1
    elif [[ "$BASE_BACKUP" == *.gz ]]; then
        gunzip -c "$BASE_BACKUP" | \
        docker run --rm -i -v "$RECOVERY_DIR:/recovery" timescale/timescaledb:latest-pg15 \
        pg_restore --clean --if-exists --verbose -d template1
    else
        docker run --rm -i -v "$RECOVERY_DIR:/recovery" timescale/timescaledb:latest-pg15 \
        pg_restore --clean --if-exists --verbose -d template1 < "$BASE_BACKUP"
    fi

    # Create recovery.conf for point-in-time recovery
    cat > "$RECOVERY_DIR/recovery.conf" << EOF
restore_command = 'cp $WAL_ARCHIVE_DIR/%f %p'
recovery_target_time = '$RECOVERY_TIME'
recovery_target_timeline = 'latest'
EOF

    log_message "Point-in-time recovery setup completed"
    log_message "Manual intervention required:"
    log_message "1. Copy recovery data to PostgreSQL data directory"
    log_message "2. Start PostgreSQL with recovery.conf"
    log_message "3. Verify recovery completion"
    log_message "Recovery directory: $RECOVERY_DIR"
}

main "$@"
