#!/bin/bash
# /opt/prs-deployment/scripts/verify-backups.sh
# Verify backup integrity and completeness for PRS on-premises deployment

set -euo pipefail

BACKUP_DIR="/mnt/hdd/postgres-backups/daily"
LOG_FILE="/var/log/prs-backup-verification.log"

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

test_restore() {
    local backup_file="$1"
    local test_db="prs_backup_test_$(date +%s)"

    # Create test database
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -c "CREATE DATABASE $test_db;" >/dev/null 2>&1

    # Attempt restoration
    if [[ "$backup_file" == *.gpg ]]; then
        gpg --quiet --decrypt "$backup_file" | gunzip | \
        docker exec -i prs-onprem-postgres-timescale pg_restore -U "${POSTGRES_USER:-prs_user}" -d "$test_db" >/dev/null 2>&1
    elif [[ "$backup_file" == *.gz ]]; then
        gunzip -c "$backup_file" | \
        docker exec -i prs-onprem-postgres-timescale pg_restore -U "${POSTGRES_USER:-prs_user}" -d "$test_db" >/dev/null 2>&1
    else
        docker exec -i prs-onprem-postgres-timescale pg_restore -U "${POSTGRES_USER:-prs_user}" -d "$test_db" < "$backup_file" >/dev/null 2>&1
    fi

    local result=$?

    # Cleanup test database
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -c "DROP DATABASE $test_db;" >/dev/null 2>&1

    return $result
}

main() {
    log_message "Starting backup verification"

    local VERIFIED=0
    local FAILED=0

    # Check all backups from last 7 days
    for backup in $(find "$BACKUP_DIR" -name "prs_full_backup_*.sql*" -mtime -7); do
        log_message "Verifying backup: $backup"

        # Check file size
        local SIZE=$(stat -c%s "$backup")
        if [ "$SIZE" -lt 1000000 ]; then
            log_message "ERROR: Backup file too small: $backup"
            ((FAILED++))
            continue
        fi

        # Check checksum if available
        if [ -f "${backup}.sha256" ]; then
            if sha256sum -c "${backup}.sha256" >/dev/null 2>&1; then
                log_message "Checksum verification passed: $backup"
            else
                log_message "ERROR: Checksum verification failed: $backup"
                ((FAILED++))
                continue
            fi
        fi

        # Test restoration to temporary database
        log_message "Testing restoration: $backup"
        if test_restore "$backup"; then
            log_message "Restoration test passed: $backup"
            ((VERIFIED++))
        else
            log_message "ERROR: Restoration test failed: $backup"
            ((FAILED++))
        fi
    done

    log_message "Backup verification completed: $VERIFIED verified, $FAILED failed"

    if [ "$FAILED" -gt 0 ]; then
        echo "Backup verification found $FAILED failed backups" | \
        mail -s "PRS Backup Verification Alert" "${ADMIN_EMAIL:-admin@prs.client-domain.com}"
    fi
}

main "$@"
