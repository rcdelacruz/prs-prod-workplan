#!/bin/bash
# /opt/prs-deployment/scripts/daily-maintenance-automation.sh
# Comprehensive daily maintenance automation for PRS on-premises deployment

set -euo pipefail

LOG_FILE="/var/log/prs-maintenance.log"
MAINTENANCE_LOCK="/var/run/prs-maintenance.lock"
EMAIL_REPORT="${ADMIN_EMAIL:-admin@prs.client-domain.com}"

# Maintenance configuration
VACUUM_THRESHOLD=1000        # Dead tuples threshold for vacuum
LOG_RETENTION_DAYS=7         # Log retention in days
TEMP_FILE_AGE_HOURS=24      # Temporary file cleanup age
BACKUP_VERIFICATION=true     # Enable backup verification

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

acquire_lock() {
    if [ -f "$MAINTENANCE_LOCK" ]; then
        local lock_pid=$(cat "$MAINTENANCE_LOCK")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log_message "Maintenance already running (PID: $lock_pid)"
            exit 1
        else
            log_message "Removing stale lock file"
            rm -f "$MAINTENANCE_LOCK"
        fi
    fi

    echo $$ > "$MAINTENANCE_LOCK"
    trap 'rm -f "$MAINTENANCE_LOCK"; exit' INT TERM EXIT
}

database_maintenance() {
    log_message "Starting database maintenance"

    # Update table statistics
    log_message "Updating table statistics"
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "
    ANALYZE notifications;
    ANALYZE audit_logs;
    ANALYZE requisitions;
    ANALYZE purchase_orders;
    ANALYZE users;
    ANALYZE departments;
    "

    # Check for tables needing vacuum
    local tables_needing_vacuum=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "
    SELECT tablename FROM pg_stat_user_tables
    WHERE n_dead_tup > $VACUUM_THRESHOLD
    AND n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0) > 0.1;
    " | xargs)

    if [ -n "$tables_needing_vacuum" ]; then
        log_message "Vacuuming tables: $tables_needing_vacuum"
        for table in $tables_needing_vacuum; do
            docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "VACUUM ANALYZE $table;"
        done
    else
        log_message "No tables require vacuuming"
    fi

    # Check database health
    local db_health=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "
    SELECT
        CASE
            WHEN pg_is_in_recovery() THEN 'RECOVERY'
            WHEN EXISTS (SELECT 1 FROM pg_stat_activity WHERE state = 'active' AND query_start < now() - interval '1 hour') THEN 'SLOW_QUERIES'
            ELSE 'HEALTHY'
        END;
    " | xargs)

    log_message "Database health status: $db_health"

    if [ "$db_health" != "HEALTHY" ]; then
        log_message "WARNING: Database health issue detected: $db_health"
    fi
}

storage_maintenance() {
    log_message "Starting storage maintenance"

    # Check storage usage
    local ssd_usage=$(df ${STORAGE_HDD_PATH:-/mnt/hdd} | awk 'NR==2 {print $5}' | sed 's/%//')
    local hdd_usage=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')

    log_message "Storage usage - SSD: ${ssd_usage}%, HDD: ${hdd_usage}%"

    # Trigger data movement if SSD usage is high
    if [ "$ssd_usage" -gt 85 ]; then
        log_message "High SSD usage detected, triggering data movement"
        docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "
        SELECT move_chunk(chunk_name, 'pg_default')
        FROM timescaledb_information.chunks
        WHERE range_start < NOW() - INTERVAL '14 days'
        AND tablespace_name = 'pg_default'
        LIMIT 5;
        "
    fi

    # Clean temporary files
    log_message "Cleaning temporary files"
    find /tmp -type f -mtime +1 -delete 2>/dev/null || true
    find /var/tmp -type f -mtime +1 -delete 2>/dev/null || true

    # Clean old application logs
    log_message "Managing application logs"
    find ${STORAGE_HDD_PATH:-/mnt/hdd}/logs -name "*.log" -mtime +$LOG_RETENTION_DAYS -exec gzip {} \;
    find ${STORAGE_HDD_PATH:-/mnt/hdd}/logs -name "*.log.gz" -mtime +30 -delete

    # Docker system cleanup
    log_message "Cleaning Docker system"
    docker system prune -f --volumes

    # Check for large files
    local large_files=$(find ${STORAGE_HDD_PATH:-/mnt/hdd} -type f -size +1G 2>/dev/null | wc -l)
    if [ "$large_files" -gt 0 ]; then
        log_message "Found $large_files files larger than 1GB"
        find ${STORAGE_HDD_PATH:-/mnt/hdd} -type f -size +1G -exec ls -lh {} \; >> "$LOG_FILE"
    fi
}

application_maintenance() {
    log_message "Starting application maintenance"

    # Check application health
    local api_status=$(curl -s -o /dev/null -w "%{http_code}" https://localhost/api/health || echo "000")
    local frontend_status=$(curl -s -o /dev/null -w "%{http_code}" https://localhost/ || echo "000")

    log_message "Application status - API: $api_status, Frontend: $frontend_status"

    # Check for memory leaks
    local backend_memory=$(docker stats prs-onprem-backend --no-stream --format "{{.MemUsage}}" | cut -d'/' -f1 | sed 's/[^0-9.]//g')
    local frontend_memory=$(docker stats prs-onprem-frontend --no-stream --format "{{.MemUsage}}" | cut -d'/' -f1 | sed 's/[^0-9.]//g')

    log_message "Memory usage - Backend: ${backend_memory}MB, Frontend: ${frontend_memory}MB"

    # Restart services if memory usage is too high
    if (( $(echo "$backend_memory > 2000" | bc -l) )); then
        log_message "High backend memory usage, restarting service"
        docker-compose -f "$PROJECT_DIR/02-docker-configuration/docker-compose.onprem.yml" restart backend
    fi

    # Check for failed background jobs
    local failed_jobs=$(docker exec prs-onprem-redis redis-cli -a "${REDIS_PASSWORD:-}" llen "failed_jobs" 2>/dev/null || echo "0")
    if [ "$failed_jobs" -gt 0 ]; then
        log_message "WARNING: $failed_jobs failed background jobs detected"
    fi

    # Clear expired sessions
    log_message "Clearing expired sessions"
    docker exec prs-onprem-redis redis-cli -a "${REDIS_PASSWORD:-}" eval "
    local keys = redis.call('keys', 'session:*')
    local expired = 0
    for i=1,#keys do
        local ttl = redis.call('ttl', keys[i])
        if ttl == -1 then
            redis.call('del', keys[i])
            expired = expired + 1
        end
    end
    return expired
    " 0 2>/dev/null || echo "0"
}

security_maintenance() {
    log_message "Starting security maintenance"

    # Check for failed login attempts
    local failed_logins=$(grep "Failed password" /var/log/auth.log | grep "$(date +%Y-%m-%d)" | wc -l)
    log_message "Failed login attempts today: $failed_logins"

    if [ "$failed_logins" -gt 20 ]; then
        log_message "WARNING: High number of failed login attempts: $failed_logins"
    fi

    # Check SSL certificate expiration
    if [ -f "$PROJECT_DIR/02-docker-configuration/ssl/certificate.crt" ]; then
        local cert_expiry=$(openssl x509 -in "$PROJECT_DIR/02-docker-configuration/ssl/certificate.crt" -noout -enddate | cut -d= -f2)
        local expiry_epoch=$(date -d "$cert_expiry" +%s)
        local current_epoch=$(date +%s)
        local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))

        log_message "SSL certificate expires in $days_until_expiry days"

        if [ "$days_until_expiry" -lt 30 ]; then
            log_message "WARNING: SSL certificate expires in $days_until_expiry days"
        fi
    fi

    # Check for security updates
    local security_updates=$(apt list --upgradable 2>/dev/null | grep security | wc -l)
    if [ "$security_updates" -gt 0 ]; then
        log_message "Available security updates: $security_updates"
    fi

    # Audit user permissions
    local inactive_users=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "
    SELECT count(*) FROM users
    WHERE last_login_at < NOW() - INTERVAL '90 days'
    OR last_login_at IS NULL;
    " | xargs)

    if [ "$inactive_users" -gt 0 ]; then
        log_message "Inactive users (90+ days): $inactive_users"
    fi
}

backup_verification() {
    if [ "$BACKUP_VERIFICATION" = true ]; then
        log_message "Verifying recent backups"

        local latest_backup=$(ls -t /mnt/hdd/postgres-backups/daily/*.sql* 2>/dev/null | head -1)

        if [ -n "$latest_backup" ]; then
            local backup_age_hours=$(( ($(date +%s) - $(stat -c %Y "$latest_backup")) / 3600 ))
            log_message "Latest backup: $latest_backup (${backup_age_hours}h old)"

            if [ "$backup_age_hours" -gt 25 ]; then
                log_message "WARNING: Latest backup is older than 25 hours"
            fi

            # Verify backup integrity
            if [ -f "${latest_backup}.sha256" ]; then
                if sha256sum -c "${latest_backup}.sha256" >/dev/null 2>&1; then
                    log_message "Backup integrity verification passed"
                else
                    log_message "ERROR: Backup integrity verification failed"
                fi
            else
                log_message "WARNING: No checksum file for latest backup"
            fi
        else
            log_message "ERROR: No backup files found"
        fi
    fi
}

main() {
    acquire_lock

    log_message "Starting daily maintenance automation"

    database_maintenance
    storage_maintenance
    application_maintenance
    security_maintenance
    backup_verification

    log_message "Daily maintenance automation completed successfully"
}

main "$@"
