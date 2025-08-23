# Maintenance Scripts

## Overview

This guide covers all maintenance-related scripts in the PRS on-premises deployment, including automated maintenance procedures, system optimization, and preventive maintenance tasks.

## Core Maintenance Scripts

### Daily Maintenance Automation

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/daily-maintenance-automation.sh
# Comprehensive daily maintenance automation

set -euo pipefail

LOG_FILE="/var/log/prs-maintenance.log"
MAINTENANCE_LOCK="/var/run/prs-maintenance.lock"
EMAIL_REPORT="admin@your-domain.com"

# Maintenance configuration
VACUUM_THRESHOLD=1000        # Dead tuples threshold for vacuum
LOG_RETENTION_DAYS=7         # Log retention in days
TEMP_FILE_AGE_HOURS=24      # Temporary file cleanup age
BACKUP_VERIFICATION=true     # Enable backup verification

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
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
    ANALYZE notifications;
    ANALYZE audit_logs;
    ANALYZE requisitions;
    ANALYZE purchase_orders;
    ANALYZE users;
    ANALYZE departments;
    "
    
    # Check for tables needing vacuum
    local tables_needing_vacuum=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT tablename FROM pg_stat_user_tables 
    WHERE n_dead_tup > $VACUUM_THRESHOLD 
    AND n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0) > 0.1;
    " | xargs)
    
    if [ -n "$tables_needing_vacuum" ]; then
        log_message "Vacuuming tables: $tables_needing_vacuum"
        for table in $tables_needing_vacuum; do
            docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "VACUUM ANALYZE $table;"
        done
    else
        log_message "No tables require vacuuming"
    fi
    
    # Check database health
    local db_health=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
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
    local ssd_usage=$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')
    local hdd_usage=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')
    
    log_message "Storage usage - SSD: ${ssd_usage}%, HDD: ${hdd_usage}%"
    
    # Trigger data movement if SSD usage is high
    if [ "$ssd_usage" -gt 85 ]; then
        log_message "High SSD usage detected, triggering data movement"
        docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
        SELECT move_chunk(chunk_name, 'hdd_cold')
        FROM timescaledb_information.chunks 
        WHERE range_start < NOW() - INTERVAL '14 days'
        AND tablespace_name = 'ssd_hot'
        LIMIT 5;
        "
    fi
    
    # Clean temporary files
    log_message "Cleaning temporary files"
    find /tmp -type f -mtime +1 -delete 2>/dev/null || true
    find /var/tmp -type f -mtime +1 -delete 2>/dev/null || true
    
    # Clean old application logs
    log_message "Managing application logs"
    find /mnt/ssd/logs -name "*.log" -mtime +$LOG_RETENTION_DAYS -exec gzip {} \;
    find /mnt/ssd/logs -name "*.log.gz" -mtime +30 -delete
    
    # Docker system cleanup
    log_message "Cleaning Docker system"
    docker system prune -f --volumes
    
    # Check for large files
    local large_files=$(find /mnt/ssd -type f -size +1G 2>/dev/null | wc -l)
    if [ "$large_files" -gt 0 ]; then
        log_message "Found $large_files files larger than 1GB"
        find /mnt/ssd -type f -size +1G -exec ls -lh {} \; >> "$LOG_FILE"
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
        docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml restart backend
    fi
    
    # Check for failed background jobs
    local failed_jobs=$(docker exec prs-onprem-redis redis-cli -a "$REDIS_PASSWORD" llen "failed_jobs" 2>/dev/null || echo "0")
    if [ "$failed_jobs" -gt 0 ]; then
        log_message "WARNING: $failed_jobs failed background jobs detected"
    fi
    
    # Clear expired sessions
    log_message "Clearing expired sessions"
    docker exec prs-onprem-redis redis-cli -a "$REDIS_PASSWORD" eval "
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
    if [ -f "/opt/prs-deployment/02-docker-configuration/ssl/certificate.crt" ]; then
        local cert_expiry=$(openssl x509 -in /opt/prs-deployment/02-docker-configuration/ssl/certificate.crt -noout -enddate | cut -d= -f2)
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
    local inactive_users=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
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

performance_optimization() {
    log_message "Starting performance optimization"
    
    # Check and optimize TimescaleDB compression
    local uncompressed_chunks=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT count(*) FROM timescaledb_information.chunks 
    WHERE range_start < NOW() - INTERVAL '7 days'
    AND NOT is_compressed
    AND hypertable_name IN ('notifications', 'audit_logs');
    " | xargs)
    
    if [ "$uncompressed_chunks" -gt 0 ]; then
        log_message "Compressing $uncompressed_chunks old chunks"
        docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
        SELECT compress_chunk(chunk_name) 
        FROM timescaledb_information.chunks 
        WHERE range_start < NOW() - INTERVAL '7 days'
        AND NOT is_compressed
        AND hypertable_name IN ('notifications', 'audit_logs')
        LIMIT 10;
        "
    fi
    
    # Check query performance
    local slow_queries=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT count(*) FROM pg_stat_statements 
    WHERE mean_time > 1000 AND calls > 10;
    " | xargs)
    
    if [ "$slow_queries" -gt 5 ]; then
        log_message "WARNING: $slow_queries slow queries detected"
    fi
    
    # Check cache hit ratio
    local cache_hit_ratio=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT round(100.0 * sum(blks_hit) / nullif(sum(blks_hit) + sum(blks_read), 0), 2)
    FROM pg_stat_database WHERE datname = 'prs_production';
    " | xargs)
    
    log_message "Database cache hit ratio: ${cache_hit_ratio}%"
    
    if (( $(echo "$cache_hit_ratio < 95" | bc -l) )); then
        log_message "WARNING: Low cache hit ratio: ${cache_hit_ratio}%"
    fi
}

generate_maintenance_report() {
    local report_file="/tmp/daily-maintenance-report-$(date +%Y%m%d).txt"
    
    cat > "$report_file" << EOF
PRS Daily Maintenance Report
============================
Date: $(date)
Hostname: $(hostname)

SYSTEM STATUS
-------------
- CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')%
- Memory Usage: $(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')%
- SSD Usage: $(df /mnt/ssd | awk 'NR==2 {print $5}')
- HDD Usage: $(df /mnt/hdd | awk 'NR==2 {print $5}')
- Load Average: $(uptime | awk -F'load average:' '{print $2}')

DATABASE STATUS
---------------
- Database Size: $(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT pg_size_pretty(pg_database_size('prs_production'));" | xargs)
- Active Connections: $(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT count(*) FROM pg_stat_activity;" | xargs)
- Cache Hit Ratio: $(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT round(100.0 * sum(blks_hit) / nullif(sum(blks_hit) + sum(blks_read), 0), 2) FROM pg_stat_database WHERE datname = 'prs_production';" | xargs)%

APPLICATION STATUS
------------------
- API Status: $(curl -s -o /dev/null -w "%{http_code}" https://localhost/api/health || echo "ERROR")
- Frontend Status: $(curl -s -o /dev/null -w "%{http_code}" https://localhost/ || echo "ERROR")
- Active Sessions: $(docker exec prs-onprem-redis redis-cli -a "$REDIS_PASSWORD" eval "return #redis.call('keys', 'session:*')" 0 2>/dev/null || echo "N/A")

MAINTENANCE ACTIONS
-------------------
$(tail -50 "$LOG_FILE" | grep "$(date +%Y-%m-%d)")

RECOMMENDATIONS
---------------
$(if [ "$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')" -gt 80 ]; then echo "- Monitor SSD usage closely"; fi)
$(if [ "$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT count(*) FROM pg_stat_statements WHERE mean_time > 1000 AND calls > 10;" | xargs)" -gt 5 ]; then echo "- Review slow queries"; fi)
$(if [ "$(grep "Failed password" /var/log/auth.log | grep "$(date +%Y-%m-%d)" | wc -l)" -gt 20 ]; then echo "- Investigate failed login attempts"; fi)
EOF
    
    log_message "Maintenance report generated: $report_file"
    
    # Email report if configured
    if command -v mail >/dev/null 2>&1 && [ -n "$EMAIL_REPORT" ]; then
        mail -s "PRS Daily Maintenance Report" "$EMAIL_REPORT" < "$report_file"
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
    performance_optimization
    
    generate_maintenance_report
    
    log_message "Daily maintenance automation completed successfully"
}

main "$@"
```

### Weekly Maintenance Automation

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/weekly-maintenance-automation.sh
# Comprehensive weekly maintenance automation

set -euo pipefail

LOG_FILE="/var/log/prs-maintenance.log"
WEEK_NUMBER=$(date +%V)

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

comprehensive_database_maintenance() {
    log_message "Starting comprehensive database maintenance"
    
    # Full VACUUM ANALYZE
    log_message "Performing full VACUUM ANALYZE"
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
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
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
    REINDEX TABLE users;
    REINDEX TABLE departments;
    REINDEX TABLE categories;
    REINDEX TABLE vendors;
    "
    
    # Update TimescaleDB compression
    log_message "Updating TimescaleDB compression"
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
    SELECT compress_chunk(chunk_name) 
    FROM timescaledb_information.chunks 
    WHERE range_start < NOW() - INTERVAL '7 days'
    AND NOT is_compressed
    AND hypertable_name IN ('notifications', 'audit_logs')
    LIMIT 20;
    "
    
    # Check for unused indexes
    log_message "Checking for unused indexes"
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
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
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
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
    local suspicious_activities=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
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
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
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
    local compression_stats=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT 
        round(
            AVG((before_compression_total_bytes::numeric - after_compression_total_bytes::numeric) 
            / before_compression_total_bytes::numeric * 100), 2
        )
    FROM timescaledb_information.compressed_hypertable_stats;
    " | xargs)
    
    log_message "Average compression ratio: ${compression_stats}%"
    
    # Check storage growth
    local db_size_gb=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT ROUND(pg_database_size('prs_production') / 1024.0 / 1024.0 / 1024.0, 2);
    " | xargs)
    
    log_message "Current database size: ${db_size_gb}GB"
}

generate_weekly_report() {
    local report_file="/tmp/weekly-maintenance-report-week$WEEK_NUMBER.txt"
    
    cat > "$report_file" << EOF
PRS Weekly Maintenance Report - Week $WEEK_NUMBER
=================================================
Generated: $(date)

MAINTENANCE SUMMARY
-------------------
- Database maintenance: VACUUM ANALYZE completed
- System optimization: Package cleanup and Docker optimization
- Security audit: $(apt list --upgradable 2>/dev/null | grep security | wc -l) security updates available
- Performance analysis: Completed query and compression analysis

SYSTEM HEALTH
--------------
- Database Size: $(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT pg_size_pretty(pg_database_size('prs_production'));" | xargs)
- Compression Ratio: $(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT round(AVG((before_compression_total_bytes::numeric - after_compression_total_bytes::numeric) / before_compression_total_bytes::numeric * 100), 2) FROM timescaledb_information.compressed_hypertable_stats;" | xargs)%
- SSD Usage: $(df /mnt/ssd | awk 'NR==2 {print $5}')
- HDD Usage: $(df /mnt/hdd | awk 'NR==2 {print $5}')

PERFORMANCE METRICS
-------------------
$(cat /tmp/performance-analysis-week$WEEK_NUMBER.log)

SECURITY STATUS
---------------
$(if [ -f /tmp/security-updates-week$WEEK_NUMBER.txt ]; then echo "Security updates available:"; cat /tmp/security-updates-week$WEEK_NUMBER.txt; else echo "No security updates available"; fi)

RECOMMENDATIONS
---------------
$(if [ "$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')" -gt 80 ]; then echo "- Consider SSD capacity expansion"; fi)
$(if [ "$(apt list --upgradable 2>/dev/null | grep security | wc -l)" -gt 0 ]; then echo "- Apply available security updates"; fi)
$(if [ "$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT count(*) FROM pg_stat_user_indexes WHERE idx_scan = 0 AND pg_relation_size(indexrelid) > 1024*1024;" | xargs)" -gt 3 ]; then echo "- Review and remove unused indexes"; fi)
EOF
    
    log_message "Weekly maintenance report generated: $report_file"
    
    # Email report if configured
    if command -v mail >/dev/null 2>&1; then
        mail -s "PRS Weekly Maintenance Report - Week $WEEK_NUMBER" admin@your-domain.com < "$report_file"
    fi
}

main() {
    log_message "Starting weekly maintenance automation (Week $WEEK_NUMBER)"
    
    comprehensive_database_maintenance
    system_optimization
    security_audit
    performance_analysis
    
    generate_weekly_report
    
    log_message "Weekly maintenance automation completed successfully"
}

main "$@"
```

### Maintenance Status Monitor

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/maintenance-status-monitor.sh
# Monitor maintenance job status and health

set -euo pipefail

LOG_FILE="/var/log/prs-maintenance.log"
STATUS_FILE="/var/run/prs-maintenance-status"

check_maintenance_status() {
    echo "PRS Maintenance Status Monitor"
    echo "=============================="
    echo "Generated: $(date)"
    echo ""
    
    # Check last maintenance runs
    echo "LAST MAINTENANCE RUNS:"
    echo "----------------------"
    if [ -f "$LOG_FILE" ]; then
        echo "Daily: $(grep "daily maintenance.*completed" "$LOG_FILE" | tail -1 | cut -d' ' -f1-2 || echo "Never")"
        echo "Weekly: $(grep "weekly maintenance.*completed" "$LOG_FILE" | tail -1 | cut -d' ' -f1-2 || echo "Never")"
        echo "Monthly: $(grep "monthly.*completed" "$LOG_FILE" | tail -1 | cut -d' ' -f1-2 || echo "Never")"
    else
        echo "No maintenance log found"
    fi
    
    echo ""
    
    # Check for maintenance errors
    echo "RECENT MAINTENANCE ISSUES:"
    echo "--------------------------"
    if [ -f "$LOG_FILE" ]; then
        local error_count=$(grep -c "ERROR\|WARNING" "$LOG_FILE" | tail -100 || echo "0")
        echo "Errors/Warnings (last 100 entries): $error_count"
        
        if [ "$error_count" -gt 0 ]; then
            echo "Recent issues:"
            grep "ERROR\|WARNING" "$LOG_FILE" | tail -5
        fi
    fi
    
    echo ""
    
    # Check maintenance job schedule
    echo "SCHEDULED MAINTENANCE JOBS:"
    echo "---------------------------"
    crontab -l | grep prs-deployment || echo "No maintenance jobs scheduled"
    
    echo ""
    
    # Check system health
    echo "CURRENT SYSTEM STATUS:"
    echo "----------------------"
    echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')%"
    echo "Memory: $(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')%"
    echo "SSD: $(df /mnt/ssd | awk 'NR==2 {print $5}')"
    echo "HDD: $(df /mnt/hdd | awk 'NR==2 {print $5}')"
    
    # Save status
    cat > "$STATUS_FILE" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "daily_maintenance": "$(grep "daily maintenance.*completed" "$LOG_FILE" | tail -1 | cut -d' ' -f1-2 || echo "Never")",
    "weekly_maintenance": "$(grep "weekly maintenance.*completed" "$LOG_FILE" | tail -1 | cut -d' ' -f1-2 || echo "Never")",
    "error_count": "$(grep -c "ERROR\|WARNING" "$LOG_FILE" | tail -100 || echo "0")",
    "cpu_usage": "$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')",
    "memory_usage": "$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')",
    "ssd_usage": "$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')",
    "hdd_usage": "$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')"
}
EOF
}

check_maintenance_status
```

---

!!! success "Maintenance Scripts Ready"
    Your PRS deployment now has comprehensive maintenance scripts covering daily automation, weekly optimization, and status monitoring for complete system maintenance.

!!! tip "Automation Setup"
    Use cron to schedule these maintenance scripts for automated system care and optimization.

!!! warning "Monitoring Required"
    Always monitor maintenance script execution and review logs regularly to ensure all maintenance tasks complete successfully.
