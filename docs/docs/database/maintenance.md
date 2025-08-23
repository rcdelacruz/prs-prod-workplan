# Database Maintenance

## Overview

This guide covers comprehensive database maintenance procedures for the PRS on-premises deployment, including routine maintenance, performance optimization, and preventive care.

## Maintenance Schedule

### Daily Maintenance (Automated)

| Task | Time | Duration | Purpose |
|------|------|----------|---------|
| **Statistics Update** | 01:00 | 5 min | Query optimization |
| **Full Backup** | 02:00 | 30 min | Data protection |
| **WAL Archive Cleanup** | 03:00 | 5 min | Storage management |
| **Performance Check** | 04:00 | 5 min | Health monitoring |
| **Log Rotation** | 05:00 | 2 min | Log management |

### Weekly Maintenance (Semi-automated)

| Task | Day | Duration | Purpose |
|------|-----|----------|---------|
| **VACUUM ANALYZE** | Sunday 01:00 | 60 min | Table optimization |
| **Index Maintenance** | Sunday 02:30 | 30 min | Index optimization |
| **Compression Review** | Sunday 03:00 | 15 min | Storage optimization |
| **Security Audit** | Sunday 03:30 | 15 min | Security review |

### Monthly Maintenance (Manual)

| Task | Schedule | Duration | Purpose |
|------|----------|----------|---------|
| **Full REINDEX** | 1st Sunday 02:00 | 2 hours | Index rebuilding |
| **Capacity Planning** | 2nd Sunday | 30 min | Growth analysis |
| **Performance Review** | 3rd Sunday | 45 min | Optimization review |
| **Disaster Recovery Test** | 4th Sunday | 60 min | Recovery validation |

## Daily Maintenance Procedures

### Automated Daily Tasks

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/daily-maintenance.sh

set -euo pipefail

LOG_FILE="/var/log/prs-maintenance.log"
DATE=$(date +%Y%m%d_%H%M%S)

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "Starting daily database maintenance"

# 1. Update table statistics
log_message "Updating table statistics"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
ANALYZE notifications;
ANALYZE audit_logs;
ANALYZE requisitions;
ANALYZE purchase_orders;
ANALYZE users;
ANALYZE departments;
"

# 2. Check database health
log_message "Checking database health"
HEALTH_CHECK=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
SELECT 
    CASE 
        WHEN pg_is_in_recovery() THEN 'RECOVERY'
        WHEN EXISTS (SELECT 1 FROM pg_stat_activity WHERE state = 'active' AND query_start < now() - interval '1 hour') THEN 'SLOW_QUERIES'
        ELSE 'HEALTHY'
    END;
" | xargs)

log_message "Database health status: $HEALTH_CHECK"

# 3. Monitor table bloat
log_message "Checking table bloat"
BLOATED_TABLES=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
SELECT COUNT(*) FROM pg_stat_user_tables 
WHERE n_dead_tup > 1000 
AND n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0) > 0.1;
" | xargs)

if [ "$BLOATED_TABLES" -gt 0 ]; then
    log_message "WARNING: $BLOATED_TABLES tables have significant bloat"
    # Schedule vacuum for bloated tables
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
    SELECT 'VACUUM ' || schemaname || '.' || tablename || ';' as vacuum_cmd
    FROM pg_stat_user_tables 
    WHERE n_dead_tup > 1000 
    AND n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0) > 0.1;
    " | grep VACUUM | while read cmd; do
        log_message "Executing: $cmd"
        docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "$cmd"
    done
fi

# 4. Check connection count
ACTIVE_CONNECTIONS=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
SELECT count(*) FROM pg_stat_activity WHERE state = 'active';
" | xargs)

log_message "Active connections: $ACTIVE_CONNECTIONS"

if [ "$ACTIVE_CONNECTIONS" -gt 100 ]; then
    log_message "WARNING: High connection count detected"
fi

# 5. Monitor disk usage
SSD_USAGE=$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')
HDD_USAGE=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')

log_message "Storage usage - SSD: ${SSD_USAGE}%, HDD: ${HDD_USAGE}%"

if [ "$SSD_USAGE" -gt 85 ]; then
    log_message "WARNING: SSD usage high (${SSD_USAGE}%)"
    # Trigger data movement
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
    SELECT move_chunk(chunk_name, 'hdd_cold')
    FROM timescaledb_information.chunks 
    WHERE range_start < NOW() - INTERVAL '14 days'
    AND tablespace_name = 'ssd_hot'
    LIMIT 5;
    "
fi

log_message "Daily maintenance completed"
```

### Statistics Maintenance

```sql
-- Comprehensive statistics update
ANALYZE VERBOSE notifications;
ANALYZE VERBOSE audit_logs;
ANALYZE VERBOSE requisitions;
ANALYZE VERBOSE purchase_orders;

-- Update statistics for specific columns with high cardinality
ALTER TABLE notifications ALTER COLUMN user_id SET STATISTICS 1000;
ALTER TABLE requisitions ALTER COLUMN department_id SET STATISTICS 1000;
ALTER TABLE audit_logs ALTER COLUMN action SET STATISTICS 500;

-- Re-analyze after statistics target changes
ANALYZE notifications (user_id);
ANALYZE requisitions (department_id);
ANALYZE audit_logs (action);

-- Check statistics freshness
SELECT 
    schemaname,
    tablename,
    last_analyze,
    last_autoanalyze,
    n_mod_since_analyze
FROM pg_stat_user_tables
WHERE last_analyze < NOW() - INTERVAL '1 day'
   OR n_mod_since_analyze > 1000
ORDER BY n_mod_since_analyze DESC;
```

## Weekly Maintenance Procedures

### Vacuum and Analyze

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/weekly-maintenance.sh

set -euo pipefail

LOG_FILE="/var/log/prs-maintenance.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "Starting weekly database maintenance"

# 1. Comprehensive VACUUM ANALYZE
log_message "Starting VACUUM ANALYZE"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SET maintenance_work_mem = '1GB';
VACUUM (ANALYZE, VERBOSE) notifications;
VACUUM (ANALYZE, VERBOSE) audit_logs;
VACUUM (ANALYZE, VERBOSE) requisitions;
VACUUM (ANALYZE, VERBOSE) purchase_orders;
VACUUM (ANALYZE, VERBOSE) users;
VACUUM (ANALYZE, VERBOSE) departments;
"

# 2. Check for unused indexes
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
  AND pg_relation_size(indexrelid) > 1024*1024  -- Larger than 1MB
ORDER BY pg_relation_size(indexrelid) DESC;
"

# 3. Reindex small tables
log_message "Reindexing small tables"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
REINDEX TABLE users;
REINDEX TABLE departments;
REINDEX TABLE categories;
REINDEX TABLE vendors;
"

# 4. Update TimescaleDB compression
log_message "Updating TimescaleDB compression"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT compress_chunk(chunk_name) 
FROM timescaledb_information.chunks 
WHERE range_start < NOW() - INTERVAL '7 days'
AND NOT is_compressed
AND hypertable_name IN ('notifications', 'audit_logs')
LIMIT 10;
"

# 5. Check compression effectiveness
COMPRESSION_STATS=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
SELECT 
    round(
        AVG((before_compression_total_bytes::numeric - after_compression_total_bytes::numeric) 
        / before_compression_total_bytes::numeric * 100), 2
    )
FROM timescaledb_information.compressed_hypertable_stats;
" | xargs)

log_message "Average compression ratio: ${COMPRESSION_STATS}%"

log_message "Weekly maintenance completed"
```

### Index Maintenance

```sql
-- Check index bloat
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE pg_relation_size(indexrelid) > 100*1024*1024  -- Larger than 100MB
ORDER BY pg_relation_size(indexrelid) DESC;

-- Rebuild indexes with low usage
REINDEX INDEX CONCURRENTLY idx_notifications_user_time;
REINDEX INDEX CONCURRENTLY idx_requisitions_dept_status_time;
REINDEX INDEX CONCURRENTLY idx_audit_logs_user_action_time;

-- Check for duplicate indexes
SELECT 
    a.schemaname,
    a.tablename,
    a.indexname as index1,
    b.indexname as index2,
    a.indexdef,
    b.indexdef
FROM pg_indexes a
JOIN pg_indexes b ON a.tablename = b.tablename 
    AND a.schemaname = b.schemaname
    AND a.indexname < b.indexname
WHERE a.indexdef = b.indexdef;
```

## Monthly Maintenance Procedures

### Full Database Maintenance

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/monthly-maintenance.sh

set -euo pipefail

LOG_FILE="/var/log/prs-maintenance.log"
MAINTENANCE_WINDOW="4 hours"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "Starting monthly database maintenance (${MAINTENANCE_WINDOW} window)"

# 1. Create maintenance notification
log_message "Creating maintenance notification"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
INSERT INTO system_notifications (message, type, created_at) 
VALUES ('Database maintenance in progress. Performance may be affected.', 'maintenance', NOW());
"

# 2. Full REINDEX (during maintenance window)
log_message "Starting full REINDEX"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SET maintenance_work_mem = '2GB';
REINDEX (VERBOSE) DATABASE prs_production;
"

# 3. Update all table statistics with high detail
log_message "Updating detailed statistics"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
ALTER TABLE notifications ALTER COLUMN user_id SET STATISTICS 1000;
ALTER TABLE notifications ALTER COLUMN type SET STATISTICS 500;
ALTER TABLE requisitions ALTER COLUMN department_id SET STATISTICS 1000;
ALTER TABLE requisitions ALTER COLUMN status SET STATISTICS 500;
ALTER TABLE audit_logs ALTER COLUMN user_id SET STATISTICS 1000;
ALTER TABLE audit_logs ALTER COLUMN action SET STATISTICS 500;

ANALYZE VERBOSE;
"

# 4. Comprehensive compression update
log_message "Comprehensive compression update"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT compress_chunk(chunk_name) 
FROM timescaledb_information.chunks 
WHERE range_start < NOW() - INTERVAL '30 days'
AND NOT is_compressed;
"

# 5. Data movement optimization
log_message "Optimizing data movement"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT move_chunk(chunk_name, 'hdd_cold')
FROM timescaledb_information.chunks 
WHERE range_start < NOW() - INTERVAL '30 days'
AND tablespace_name = 'ssd_hot';
"

# 6. Generate maintenance report
log_message "Generating maintenance report"
REPORT_FILE="/tmp/monthly-maintenance-report-$(date +%Y%m).txt"

cat > "$REPORT_FILE" << EOF
Monthly Database Maintenance Report
Generated: $(date)

Database Size:
$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "SELECT pg_size_pretty(pg_database_size('prs_production'));")

Table Sizes:
$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
")

Compression Statistics:
$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT 
    hypertable_name,
    pg_size_pretty(before_compression_total_bytes) as before_compression,
    pg_size_pretty(after_compression_total_bytes) as after_compression,
    round(
        (before_compression_total_bytes::numeric - after_compression_total_bytes::numeric) 
        / before_compression_total_bytes::numeric * 100, 2
    ) as compression_ratio_percent
FROM timescaledb_information.compressed_hypertable_stats;
")

Storage Distribution:
$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT 
    tablespace_name,
    COUNT(*) as chunk_count,
    pg_size_pretty(SUM(chunk_size)) as total_size
FROM timescaledb_information.chunks
GROUP BY tablespace_name;
")
EOF

log_message "Maintenance report generated: $REPORT_FILE"

# 7. Clear maintenance notification
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
DELETE FROM system_notifications WHERE type = 'maintenance';
"

log_message "Monthly maintenance completed"

# Send report via email
if command -v mail >/dev/null 2>&1; then
    mail -s "Monthly Database Maintenance Report" admin@your-domain.com < "$REPORT_FILE"
fi
```

## Performance Monitoring and Tuning

### Performance Metrics Collection

```sql
-- Create performance monitoring function
CREATE OR REPLACE FUNCTION collect_performance_metrics()
RETURNS TABLE (
    metric_name text,
    metric_value text,
    collected_at timestamp
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        'database_size'::text,
        pg_size_pretty(pg_database_size('prs_production')),
        NOW()
    UNION ALL
    SELECT 
        'active_connections'::text,
        COUNT(*)::text,
        NOW()
    FROM pg_stat_activity 
    WHERE state = 'active'
    UNION ALL
    SELECT 
        'cache_hit_ratio'::text,
        round(100.0 * sum(blks_hit) / nullif(sum(blks_hit) + sum(blks_read), 0), 2)::text || '%',
        NOW()
    FROM pg_stat_database
    WHERE datname = 'prs_production'
    UNION ALL
    SELECT 
        'transactions_per_second'::text,
        round(sum(xact_commit + xact_rollback) / extract(epoch from (now() - stats_reset)), 2)::text,
        NOW()
    FROM pg_stat_database
    WHERE datname = 'prs_production';
END;
$$ LANGUAGE plpgsql;

-- Collect metrics
SELECT * FROM collect_performance_metrics();
```

### Automated Performance Tuning

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/auto-tune-performance.sh

LOG_FILE="/var/log/prs-maintenance.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check and adjust work_mem based on query patterns
COMPLEX_QUERIES=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
SELECT COUNT(*) FROM pg_stat_statements 
WHERE query LIKE '%ORDER BY%' 
   OR query LIKE '%GROUP BY%' 
   OR query LIKE '%JOIN%'
AND calls > 100;
" | xargs)

if [ "$COMPLEX_QUERIES" -gt 50 ]; then
    log_message "High number of complex queries detected, increasing work_mem"
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
    ALTER SYSTEM SET work_mem = '64MB';
    SELECT pg_reload_conf();
    "
fi

# Check and adjust shared_buffers based on cache hit ratio
CACHE_HIT_RATIO=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
SELECT round(100.0 * sum(blks_hit) / nullif(sum(blks_hit) + sum(blks_read), 0), 2)
FROM pg_stat_database WHERE datname = 'prs_production';
" | xargs)

if (( $(echo "$CACHE_HIT_RATIO < 95" | bc -l) )); then
    log_message "Low cache hit ratio ($CACHE_HIT_RATIO%), considering shared_buffers increase"
    # Note: This requires restart, so just log for manual review
fi

# Optimize autovacuum settings based on table activity
HIGH_ACTIVITY_TABLES=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
SELECT COUNT(*) FROM pg_stat_user_tables 
WHERE n_tup_ins + n_tup_upd + n_tup_del > 10000;
" | xargs)

if [ "$HIGH_ACTIVITY_TABLES" -gt 5 ]; then
    log_message "High table activity detected, adjusting autovacuum settings"
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
    ALTER SYSTEM SET autovacuum_naptime = '30s';
    ALTER SYSTEM SET autovacuum_vacuum_threshold = 25;
    ALTER SYSTEM SET autovacuum_analyze_threshold = 25;
    SELECT pg_reload_conf();
    "
fi
```

## Maintenance Automation

### Cron Schedule Setup

```bash
# Setup comprehensive maintenance schedule
(crontab -l 2>/dev/null; cat << 'EOF'
# PRS Database Maintenance Schedule

# Daily maintenance at 1:00 AM
0 1 * * * /opt/prs-deployment/scripts/daily-maintenance.sh

# Weekly maintenance on Sunday at 1:00 AM
0 1 * * 0 /opt/prs-deployment/scripts/weekly-maintenance.sh

# Monthly maintenance on first Sunday at 2:00 AM
0 2 1-7 * 0 /opt/prs-deployment/scripts/monthly-maintenance.sh

# Performance monitoring every 4 hours
0 */4 * * * /opt/prs-deployment/scripts/auto-tune-performance.sh

# Log rotation daily at 6:00 AM
0 6 * * * /opt/prs-deployment/scripts/rotate-logs.sh
EOF
) | crontab -
```

### Maintenance Monitoring

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/maintenance-monitor.sh

MAINTENANCE_LOG="/var/log/prs-maintenance.log"
ALERT_EMAIL="admin@your-domain.com"

# Check if maintenance completed successfully
if ! grep -q "maintenance completed" "$MAINTENANCE_LOG" | tail -1; then
    echo "Database maintenance may have failed. Check logs." | \
    mail -s "Maintenance Alert" "$ALERT_EMAIL"
fi

# Check for maintenance warnings
WARNING_COUNT=$(grep -c "WARNING" "$MAINTENANCE_LOG" | tail -100)
if [ "$WARNING_COUNT" -gt 5 ]; then
    echo "High number of maintenance warnings detected: $WARNING_COUNT" | \
    mail -s "Maintenance Warnings" "$ALERT_EMAIL"
fi

# Generate maintenance summary
LAST_MAINTENANCE=$(grep "maintenance completed" "$MAINTENANCE_LOG" | tail -1)
echo "Last successful maintenance: $LAST_MAINTENANCE"
```

---

!!! success "Maintenance Configured"
    Your PRS database now has comprehensive automated maintenance procedures to ensure optimal performance and reliability.

!!! tip "Maintenance Windows"
    Schedule intensive maintenance tasks during low-usage periods to minimize impact on users.

!!! warning "Monitoring Required"
    Always monitor maintenance job execution and review logs regularly to ensure all tasks complete successfully.
