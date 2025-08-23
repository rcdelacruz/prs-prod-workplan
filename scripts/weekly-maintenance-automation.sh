#!/bin/bash
# /opt/prs-deployment/scripts/weekly-maintenance-automation.sh
# Comprehensive weekly maintenance automation for PRS on-premises deployment

set -euo pipefail

LOG_FILE="/var/log/prs-maintenance.log"
WEEK_NUMBER=$(date +%V)

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

comprehensive_database_maintenance() {
    log_message "Starting comprehensive database maintenance"

    # Full VACUUM ANALYZE
    log_message "Performing full VACUUM ANALYZE"
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "
    SET maintenance_work_mem = '1GB';
    VACUUM (ANALYZE, VERBOSE) notifications;
    VACUUM (ANALYZE, VERBOSE) audit_logs;
    VACUUM (ANALYZE, VERBOSE) requisitions;
    VACUUM (ANALYZE, VERBOSE) purchase_orders;
    VACUUM (ANALYZE, VERBOSE) users;
    VACUUM (ANALYZE, VERBOSE) departments;
    "

    # Reindex small tables
    log_message "Reindexing small tables"
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "
    REINDEX TABLE users;
    REINDEX TABLE departments;
    REINDEX TABLE categories;
    REINDEX TABLE vendors;
    "

    # Update TimescaleDB compression
    log_message "Updating TimescaleDB compression"
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "
    SELECT compress_chunk(chunk_name)
    FROM timescaledb_information.chunks
    WHERE range_start < NOW() - INTERVAL '7 days'
    AND NOT is_compressed
    AND hypertable_name IN ('notifications', 'audit_logs')
    LIMIT 20;
    "

    # Check for unused indexes
    log_message "Checking for unused indexes"
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "
    SELECT
        schemaname,
        tablename,
        indexname,
        pg_size_pretty(pg_relation_size(indexrelid)) as size,
        idx_scan
    FROM pg_stat_user_indexes
    WHERE idx_scan = 0
      AND pg_relation_size(indexrelid) > 1024*1024
    ORDER BY pg_relation_size(indexrelid) DESC;
    " > /tmp/unused-indexes-week$WEEK_NUMBER.log
}

system_optimization() {
    log_message "Starting system optimization"

    # Clean package cache
    apt-get clean
    apt-get autoremove -y

    # Update locate database
    if command -v updatedb >/dev/null 2>&1; then
        updatedb
    fi

    # Optimize system logs
    journalctl --vacuum-time=30d

    # Check for system updates
    apt update
    local available_updates=$(apt list --upgradable 2>/dev/null | wc -l)
    log_message "Available system updates: $available_updates"

    # Optimize Docker
    docker system prune -af --volumes
    docker image prune -af

    # Check disk fragmentation (if ext4)
    if mount | grep -q "ext4"; then
        log_message "Checking filesystem fragmentation"
        e4defrag -c /mnt/ssd > /tmp/ssd-fragmentation.log 2>&1 || true
        e4defrag -c /mnt/hdd > /tmp/hdd-fragmentation.log 2>&1 || true
    fi
}

security_audit() {
    log_message "Starting weekly security audit"

    # Check for security updates
    local security_updates=$(apt list --upgradable 2>/dev/null | grep security | wc -l)
    log_message "Available security updates: $security_updates"

    if [ "$security_updates" -gt 0 ]; then
        log_message "Security updates available - manual review required"
        apt list --upgradable 2>/dev/null | grep security > /tmp/security-updates-week$WEEK_NUMBER.txt
    fi

    # Check user access patterns
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "
    SELECT
        u.username,
        u.role,
        u.last_login_at,
        COUNT(al.id) as actions_this_week
    FROM users u
    LEFT JOIN audit_logs al ON u.id = al.user_id
        AND al.created_at >= NOW() - INTERVAL '7 days'
    GROUP BY u.id, u.username, u.role, u.last_login_at
    ORDER BY actions_this_week DESC;
    " > /tmp/user-activity-week$WEEK_NUMBER.log

    # Check for suspicious activities
    local suspicious_activities=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "
    SELECT count(*) FROM audit_logs
    WHERE created_at >= NOW() - INTERVAL '7 days'
    AND action IN ('delete', 'bulk_delete', 'admin_override');
    " | xargs)

    if [ "$suspicious_activities" -gt 10 ]; then
        log_message "WARNING: High number of sensitive actions this week: $suspicious_activities"
    fi
}

performance_analysis() {
    log_message "Starting performance analysis"

    # Analyze query performance
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "
    SELECT
        'Top 10 Slow Queries (This Week)' as analysis;

    SELECT
        left(query, 80) as query_snippet,
        calls,
        round(mean_time::numeric, 2) as avg_time_ms,
        round(total_time::numeric, 2) as total_time_ms
    FROM pg_stat_statements
    WHERE calls > 100
    ORDER BY total_time DESC
    LIMIT 10;
    " > /tmp/performance-analysis-week$WEEK_NUMBER.log

    # Check compression effectiveness
    local compression_stats=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "
    SELECT
        round(
            AVG((before_compression_total_bytes::numeric - after_compression_total_bytes::numeric)
            / before_compression_total_bytes::numeric * 100), 2
        )
    FROM timescaledb_information.compressed_hypertable_stats;
    " | xargs)

    log_message "Average compression ratio: ${compression_stats}%"

    # Check storage growth
    local db_size_gb=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "
    SELECT ROUND(pg_database_size('${POSTGRES_DB:-prs_production}') / 1024.0 / 1024.0 / 1024.0, 2);
    " | xargs)

    log_message "Current database size: ${db_size_gb}GB"
}

main() {
    log_message "Starting weekly maintenance automation (Week $WEEK_NUMBER)"

    comprehensive_database_maintenance
    system_optimization
    security_audit
    performance_analysis

    log_message "Weekly maintenance automation completed successfully"
}

main "$@"
