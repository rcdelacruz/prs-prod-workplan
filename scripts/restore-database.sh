#!/bin/bash
# /opt/prs-deployment/scripts/restore-database.sh
# Restore database from backup for PRS on-premises deployment

set -euo pipefail

BACKUP_FILE="$1"
TARGET_DB="${2:-prs_production}"
LOG_FILE="/var/log/prs-restore.log"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/02-docker-configuration/.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup-file> [target-database]"
    echo "Available backups:"
    ls -la ${STORAGE_HDD_PATH:-/mnt/hdd}/postgres-backups/daily/
    exit 1
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

main() {
    log_message "Starting database restoration"
    log_message "Backup file: $BACKUP_FILE"
    log_message "Target database: $TARGET_DB"

    # Verify backup file exists
    if [ ! -f "$BACKUP_FILE" ]; then
        log_message "ERROR: Backup file not found: $BACKUP_FILE"
        exit 1
    fi

    # Verify checksum if available
    if [ -f "${BACKUP_FILE}.sha256" ]; then
        log_message "Verifying backup integrity"
        if sha256sum -c "${BACKUP_FILE}.sha256"; then
            log_message "Backup integrity verified"
        else
            log_message "ERROR: Backup integrity check failed"
            exit 1
        fi
    fi

    # Stop application services
    log_message "Stopping application services"
    docker-compose -f "$PROJECT_DIR/02-docker-configuration/docker-compose.onprem.yml" \
        stop frontend backend worker

    # Wait for connections to close
    sleep 10

    # Terminate existing connections
    log_message "Terminating existing database connections"
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -c "
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = '$TARGET_DB' AND pid <> pg_backend_pid();
    "

    # Drop and recreate database
    log_message "Recreating target database"
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -c "DROP DATABASE IF EXISTS $TARGET_DB;"
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -c "CREATE DATABASE $TARGET_DB;"

    # Restore database
    log_message "Restoring database from backup"

    if [[ "$BACKUP_FILE" == *.gpg ]]; then
        # Decrypt and restore
        log_message "Decrypting and restoring encrypted backup"
        gpg --quiet --decrypt "$BACKUP_FILE" | \
        gunzip | \
        docker exec -i prs-onprem-postgres-timescale pg_restore \
            -U "${POSTGRES_USER:-prs_user}" -d "$TARGET_DB" --clean --if-exists --verbose
    elif [[ "$BACKUP_FILE" == *.gz ]]; then
        # Decompress and restore
        log_message "Decompressing and restoring backup"
        gunzip -c "$BACKUP_FILE" | \
        docker exec -i prs-onprem-postgres-timescale pg_restore \
            -U "${POSTGRES_USER:-prs_user}" -d "$TARGET_DB" --clean --if-exists --verbose
    else
        # Direct restore
        log_message "Restoring uncompressed backup"
        docker exec -i prs-onprem-postgres-timescale pg_restore \
            -U "${POSTGRES_USER:-prs_user}" -d "$TARGET_DB" --clean --if-exists --verbose < "$BACKUP_FILE"
    fi

    if [ $? -eq 0 ]; then
        log_message "Database restoration completed successfully"
    else
        log_message "ERROR: Database restoration failed"
        exit 1
    fi

    # Verify restoration
    log_message "Verifying restoration"
    TABLE_COUNT=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "$TARGET_DB" -t -c "
    SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';
    " | xargs)

    log_message "Restored $TABLE_COUNT tables"

    if [ "$TABLE_COUNT" -gt 10 ]; then
        log_message "Restoration verification passed"
    else
        log_message "WARNING: Low table count, possible incomplete restoration"
    fi

    # Restart application services
    log_message "Restarting application services"
    docker-compose -f "$PROJECT_DIR/02-docker-configuration/docker-compose.onprem.yml" \
        start frontend backend worker

    log_message "Database restoration process completed"
}

main "$@"
