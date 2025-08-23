# Routine Maintenance

## Overview

This guide covers routine maintenance procedures for the PRS on-premises deployment to ensure optimal performance, reliability, and security through regular preventive maintenance tasks.

## Maintenance Schedule Overview

### Daily Tasks (Automated)
- **System Health Checks** - Monitor system resources and service status
- **Database Backups** - Full daily backups with verification
- **Log Rotation** - Manage log file sizes and retention
- **Performance Monitoring** - Track key performance indicators
- **Security Scans** - Basic security health checks

### Weekly Tasks (Semi-automated)
- **Database Maintenance** - VACUUM, ANALYZE, and index optimization
- **Storage Cleanup** - Remove temporary files and compress old logs
- **Security Updates** - Apply critical security patches
- **Performance Review** - Analyze performance trends
- **Backup Verification** - Test backup restoration procedures

### Monthly Tasks (Manual)
- **Comprehensive System Review** - Full system health assessment
- **Capacity Planning** - Storage and performance capacity analysis
- **Security Audit** - Complete security configuration review
- **Documentation Updates** - Update procedures and configurations
- **Disaster Recovery Testing** - Test complete recovery procedures

## Daily Maintenance Procedures

### Automated Daily Tasks

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/daily-routine-maintenance.sh

set -euo pipefail

LOG_FILE="/var/log/prs-maintenance.log"
DATE=$(date +%Y%m%d_%H%M%S)

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "Starting daily routine maintenance"

# 1. System Health Check
log_message "Running system health check"
/opt/prs-deployment/scripts/system-health-check.sh all > /tmp/daily-health-$DATE.log

# Check for critical issues
if grep -q "ERROR" /tmp/daily-health-$DATE.log; then
    log_message "CRITICAL: Health check found errors"
    grep "ERROR" /tmp/daily-health-$DATE.log | mail -s "PRS Critical Health Issues" admin@your-domain.com
fi

# 2. Database Statistics Update
log_message "Updating database statistics"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
ANALYZE notifications;
ANALYZE audit_logs;
ANALYZE requisitions;
ANALYZE purchase_orders;
"

# 3. Check Database Performance
log_message "Checking database performance"
SLOW_QUERIES=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
SELECT count(*) FROM pg_stat_statements 
WHERE mean_time > 1000 AND calls > 10;
" | xargs)

if [ "$SLOW_QUERIES" -gt 5 ]; then
    log_message "WARNING: $SLOW_QUERIES slow queries detected"
fi

# 4. Storage Monitoring
log_message "Monitoring storage usage"
SSD_USAGE=$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')
HDD_USAGE=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')

log_message "Storage usage - SSD: ${SSD_USAGE}%, HDD: ${HDD_USAGE}%"

# Trigger data movement if SSD usage is high
if [ "$SSD_USAGE" -gt 85 ]; then
    log_message "High SSD usage, triggering data movement"
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
    SELECT move_chunk(chunk_name, 'hdd_cold')
    FROM timescaledb_information.chunks 
    WHERE range_start < NOW() - INTERVAL '14 days'
    AND tablespace_name = 'ssd_hot'
    LIMIT 5;
    "
fi

# 5. Log File Management
log_message "Managing log files"
# Compress logs older than 1 day
find /mnt/ssd/logs -name "*.log" -mtime +1 -exec gzip {} \;

# Move compressed logs older than 7 days to HDD
find /mnt/ssd/logs -name "*.log.gz" -mtime +7 -exec mv {} /mnt/hdd/logs/ \;

# Remove logs older than 90 days
find /mnt/hdd/logs -name "*.log.gz" -mtime +90 -delete

# 6. Container Health Check
log_message "Checking container health"
UNHEALTHY_CONTAINERS=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" | wc -l)

if [ "$UNHEALTHY_CONTAINERS" -gt 0 ]; then
    log_message "WARNING: $UNHEALTHY_CONTAINERS unhealthy containers"
    docker ps --filter "health=unhealthy" --format "table {{.Names}}\t{{.Status}}"
fi

# 7. Security Check
log_message "Running basic security check"
# Check for failed login attempts
FAILED_LOGINS=$(grep "Failed password" /var/log/auth.log | grep "$(date +%Y-%m-%d)" | wc -l)
if [ "$FAILED_LOGINS" -gt 20 ]; then
    log_message "WARNING: High number of failed login attempts: $FAILED_LOGINS"
fi

# Check SSL certificate expiration
CERT_DAYS=$(openssl x509 -in /opt/prs-deployment/02-docker-configuration/ssl/certificate.crt -noout -checkend $((30*24*3600)) && echo "OK" || echo "EXPIRING")
if [ "$CERT_DAYS" = "EXPIRING" ]; then
    log_message "WARNING: SSL certificate expires within 30 days"
fi

log_message "Daily routine maintenance completed"

# Generate daily summary
cat > /tmp/daily-summary-$DATE.txt << EOF
PRS Daily Maintenance Summary - $(date)
========================================

System Status:
- SSD Usage: ${SSD_USAGE}%
- HDD Usage: ${HDD_USAGE}%
- Slow Queries: $SLOW_QUERIES
- Unhealthy Containers: $UNHEALTHY_CONTAINERS
- Failed Logins: $FAILED_LOGINS
- SSL Certificate: $CERT_DAYS

Health Check: See /tmp/daily-health-$DATE.log

Next Actions:
$(if [ "$SSD_USAGE" -gt 85 ]; then echo "- Monitor SSD usage closely"; fi)
$(if [ "$SLOW_QUERIES" -gt 5 ]; then echo "- Review slow queries"; fi)
$(if [ "$UNHEALTHY_CONTAINERS" -gt 0 ]; then echo "- Investigate unhealthy containers"; fi)
EOF

# Email summary if configured
if command -v mail >/dev/null 2>&1; then
    mail -s "PRS Daily Maintenance Summary" admin@your-domain.com < /tmp/daily-summary-$DATE.txt
fi
```

### Daily Checklist

```bash
#!/bin/bash
# Daily maintenance checklist

echo "PRS Daily Maintenance Checklist - $(date)"
echo "=========================================="

# System Resources
echo "1. System Resources:"
echo "   CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')% usage"
echo "   Memory: $(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')% usage"
echo "   SSD: $(df /mnt/ssd | awk 'NR==2 {print $5}') usage"
echo "   HDD: $(df /mnt/hdd | awk 'NR==2 {print $5}') usage"

# Service Status
echo -e "\n2. Service Status:"
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml ps --format "table {{.Service}}\t{{.State}}\t{{.Status}}"

# Database Health
echo -e "\n3. Database Health:"
DB_CONNECTIONS=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT count(*) FROM pg_stat_activity;" | xargs)
echo "   Active Connections: $DB_CONNECTIONS"

CACHE_HIT=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
SELECT round(100.0 * sum(blks_hit) / nullif(sum(blks_hit) + sum(blks_read), 0), 2)
FROM pg_stat_database WHERE datname = 'prs_production';" | xargs)
echo "   Cache Hit Ratio: ${CACHE_HIT}%"

# Application Health
echo -e "\n4. Application Health:"
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://localhost/api/health)
echo "   API Status: $API_STATUS"

RESPONSE_TIME=$(curl -w "%{time_total}" -o /dev/null -s https://localhost/api/health)
echo "   API Response Time: ${RESPONSE_TIME}s"

# Recent Errors
echo -e "\n5. Recent Errors (24h):"
ERROR_COUNT=$(docker logs prs-onprem-backend --since 24h 2>&1 | grep -i error | wc -l)
echo "   Backend Errors: $ERROR_COUNT"

# Backup Status
echo -e "\n6. Backup Status:"
LATEST_BACKUP=$(ls -t /mnt/hdd/postgres-backups/daily/*.sql* 2>/dev/null | head -1)
if [ -n "$LATEST_BACKUP" ]; then
    BACKUP_AGE=$(( ($(date +%s) - $(stat -c %Y "$LATEST_BACKUP")) / 3600 ))
    echo "   Latest Backup: ${BACKUP_AGE}h ago"
else
    echo "   Latest Backup: NOT FOUND"
fi

echo -e "\nDaily checklist completed."
```

## Weekly Maintenance Procedures

### Weekly Maintenance Script

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/weekly-routine-maintenance.sh

set -euo pipefail

LOG_FILE="/var/log/prs-maintenance.log"
WEEK_NUMBER=$(date +%V)

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "Starting weekly routine maintenance (Week $WEEK_NUMBER)"

# 1. Database Maintenance
log_message "Performing database maintenance"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SET maintenance_work_mem = '1GB';
VACUUM (ANALYZE, VERBOSE) notifications;
VACUUM (ANALYZE, VERBOSE) audit_logs;
VACUUM (ANALYZE, VERBOSE) requisitions;
VACUUM (ANALYZE, VERBOSE) purchase_orders;
"

# 2. Index Maintenance
log_message "Checking index usage"
UNUSED_INDEXES=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
SELECT count(*) FROM pg_stat_user_indexes 
WHERE idx_scan = 0 AND pg_relation_size(indexrelid) > 1024*1024;
" | xargs)

log_message "Found $UNUSED_INDEXES unused indexes"

# 3. Storage Cleanup
log_message "Performing storage cleanup"
# Clean Docker system
docker system prune -f

# Clean temporary files
find /tmp -type f -mtime +7 -delete 2>/dev/null || true
find /var/tmp -type f -mtime +7 -delete 2>/dev/null || true

# Compress old application logs
find /mnt/ssd/logs -name "*.log" -mtime +3 -exec gzip {} \;

# 4. TimescaleDB Optimization
log_message "Optimizing TimescaleDB"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT compress_chunk(chunk_name) 
FROM timescaledb_information.chunks 
WHERE range_start < NOW() - INTERVAL '7 days'
AND NOT is_compressed
AND hypertable_name IN ('notifications', 'audit_logs')
LIMIT 10;
"

# 5. Security Updates Check
log_message "Checking for security updates"
SECURITY_UPDATES=$(apt list --upgradable 2>/dev/null | grep -c security || echo "0")
log_message "Available security updates: $SECURITY_UPDATES"

if [ "$SECURITY_UPDATES" -gt 0 ]; then
    log_message "Security updates available - manual review required"
    apt list --upgradable 2>/dev/null | grep security > /tmp/security-updates.txt
    
    if command -v mail >/dev/null 2>&1; then
        mail -s "PRS Security Updates Available" admin@your-domain.com < /tmp/security-updates.txt
    fi
fi

# 6. Performance Analysis
log_message "Analyzing performance trends"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT 
    'Top 5 Slow Queries (7 days)' as analysis;

SELECT 
    left(query, 80) as query_snippet,
    calls,
    round(mean_time::numeric, 2) as avg_time_ms,
    round(total_time::numeric, 2) as total_time_ms
FROM pg_stat_statements 
WHERE calls > 100
ORDER BY total_time DESC 
LIMIT 5;
" > /tmp/weekly-performance-analysis.txt

# 7. Backup Verification
log_message "Verifying backup integrity"
LATEST_BACKUP=$(ls -t /mnt/hdd/postgres-backups/daily/*.sql* 2>/dev/null | head -1)
if [ -n "$LATEST_BACKUP" ]; then
    if [ -f "${LATEST_BACKUP}.sha256" ]; then
        if sha256sum -c "${LATEST_BACKUP}.sha256" >/dev/null 2>&1; then
            log_message "Backup integrity verification passed"
        else
            log_message "ERROR: Backup integrity verification failed"
        fi
    else
        log_message "WARNING: No checksum file for latest backup"
    fi
fi

# 8. Generate Weekly Report
REPORT_FILE="/tmp/weekly-maintenance-report-week$WEEK_NUMBER.txt"
cat > "$REPORT_FILE" << EOF
PRS Weekly Maintenance Report - Week $WEEK_NUMBER
Generated: $(date)
================================================

Database Maintenance:
- VACUUM ANALYZE completed for main tables
- Found $UNUSED_INDEXES unused indexes
- TimescaleDB compression updated

Storage Management:
- Docker system cleanup completed
- Temporary files cleaned
- Log compression updated

Security:
- $SECURITY_UPDATES security updates available
- SSL certificate status: $(openssl x509 -in /opt/prs-deployment/02-docker-configuration/ssl/certificate.crt -noout -checkend $((30*24*3600)) && echo "Valid" || echo "Expiring soon")

Performance:
$(cat /tmp/weekly-performance-analysis.txt)

System Health:
- SSD Usage: $(df /mnt/ssd | awk 'NR==2 {print $5}')
- HDD Usage: $(df /mnt/hdd | awk 'NR==2 {print $5}')
- Memory Usage: $(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')%
- Load Average: $(uptime | awk -F'load average:' '{print $2}')

Recommendations:
$(if [ "$UNUSED_INDEXES" -gt 3 ]; then echo "- Review and remove unused indexes"; fi)
$(if [ "$SECURITY_UPDATES" -gt 0 ]; then echo "- Apply security updates during next maintenance window"; fi)
$(if [ "$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')" -gt 80 ]; then echo "- Monitor SSD usage and consider data archival"; fi)
EOF

log_message "Weekly maintenance report generated: $REPORT_FILE"

# Email report
if command -v mail >/dev/null 2>&1; then
    mail -s "PRS Weekly Maintenance Report - Week $WEEK_NUMBER" admin@your-domain.com < "$REPORT_FILE"
fi

log_message "Weekly routine maintenance completed"
```

## Monthly Maintenance Procedures

### Monthly Comprehensive Review

```bash
#!/bin/bash
# Monthly comprehensive maintenance

MONTH=$(date +%Y%m)
REPORT_FILE="/tmp/monthly-maintenance-report-$MONTH.txt"

echo "PRS Monthly Maintenance Report - $MONTH" > "$REPORT_FILE"
echo "=======================================" >> "$REPORT_FILE"
echo "Generated: $(date)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# System Overview
echo "SYSTEM OVERVIEW" >> "$REPORT_FILE"
echo "---------------" >> "$REPORT_FILE"
echo "Hostname: $(hostname)" >> "$REPORT_FILE"
echo "OS Version: $(lsb_release -d | cut -f2)" >> "$REPORT_FILE"
echo "Kernel: $(uname -r)" >> "$REPORT_FILE"
echo "Uptime: $(uptime -p)" >> "$REPORT_FILE"
echo "Docker Version: $(docker --version)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Capacity Analysis
echo "CAPACITY ANALYSIS" >> "$REPORT_FILE"
echo "-----------------" >> "$REPORT_FILE"
echo "Storage Usage:" >> "$REPORT_FILE"
df -h /mnt/ssd /mnt/hdd >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "Database Size Growth:" >> "$REPORT_FILE"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT 
    'Total Database Size: ' || pg_size_pretty(pg_database_size('prs_production'))
UNION ALL
SELECT 
    'Largest Tables:'
UNION ALL
SELECT 
    '  ' || tablename || ': ' || pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 5;
" >> "$REPORT_FILE"

# Performance Summary
echo "" >> "$REPORT_FILE"
echo "PERFORMANCE SUMMARY" >> "$REPORT_FILE"
echo "-------------------" >> "$REPORT_FILE"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT 
    'Cache Hit Ratio: ' || round(100.0 * sum(blks_hit) / nullif(sum(blks_hit) + sum(blks_read), 0), 2) || '%'
FROM pg_stat_database 
WHERE datname = 'prs_production'
UNION ALL
SELECT 
    'Active Connections: ' || count(*)::text
FROM pg_stat_activity
UNION ALL
SELECT 
    'Slow Queries (>1s): ' || count(*)::text
FROM pg_stat_statements 
WHERE mean_time > 1000;
" >> "$REPORT_FILE"

# Security Review
echo "" >> "$REPORT_FILE"
echo "SECURITY REVIEW" >> "$REPORT_FILE"
echo "---------------" >> "$REPORT_FILE"
echo "SSL Certificate:" >> "$REPORT_FILE"
openssl x509 -in /opt/prs-deployment/02-docker-configuration/ssl/certificate.crt -noout -dates >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"
echo "Failed Login Attempts (30 days):" >> "$REPORT_FILE"
grep "Failed password" /var/log/auth.log | grep "$(date +%Y-%m)" | wc -l >> "$REPORT_FILE"

# Recommendations
echo "" >> "$REPORT_FILE"
echo "RECOMMENDATIONS" >> "$REPORT_FILE"
echo "---------------" >> "$REPORT_FILE"

SSD_USAGE=$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$SSD_USAGE" -gt 75 ]; then
    echo "- Consider SSD capacity expansion (current: ${SSD_USAGE}%)" >> "$REPORT_FILE"
fi

SECURITY_UPDATES=$(apt list --upgradable 2>/dev/null | grep -c security || echo "0")
if [ "$SECURITY_UPDATES" -gt 0 ]; then
    echo "- Apply $SECURITY_UPDATES pending security updates" >> "$REPORT_FILE"
fi

echo "- Review and update documentation" >> "$REPORT_FILE"
echo "- Test disaster recovery procedures" >> "$REPORT_FILE"
echo "- Review user access permissions" >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"
echo "Report completed: $(date)" >> "$REPORT_FILE"

# Email monthly report
if command -v mail >/dev/null 2>&1; then
    mail -s "PRS Monthly Maintenance Report - $MONTH" admin@your-domain.com < "$REPORT_FILE"
fi

echo "Monthly maintenance report generated: $REPORT_FILE"
```

## Maintenance Automation

### Cron Schedule Setup

```bash
#!/bin/bash
# Setup comprehensive maintenance schedule

(crontab -l 2>/dev/null; cat << 'EOF'
# PRS Routine Maintenance Schedule

# Daily maintenance at 1:00 AM
0 1 * * * /opt/prs-deployment/scripts/daily-routine-maintenance.sh

# Weekly maintenance on Sunday at 2:00 AM
0 2 * * 0 /opt/prs-deployment/scripts/weekly-routine-maintenance.sh

# Monthly maintenance on first Sunday at 3:00 AM
0 3 1-7 * 0 /opt/prs-deployment/scripts/monthly-comprehensive-review.sh

# Health checks every 5 minutes
*/5 * * * * /opt/prs-deployment/scripts/system-health-check.sh >/dev/null 2>&1

# Performance monitoring every hour
0 * * * * /opt/prs-deployment/scripts/performance-monitor.sh

# Log rotation daily at 6:00 AM
0 6 * * * /opt/prs-deployment/scripts/log-rotation.sh
EOF
) | crontab -

echo "Maintenance schedule configured successfully"
crontab -l
```

### Maintenance Status Dashboard

```bash
#!/bin/bash
# Maintenance status dashboard

echo "PRS Maintenance Status Dashboard"
echo "================================"
echo "Generated: $(date)"
echo ""

# Last maintenance runs
echo "LAST MAINTENANCE RUNS:"
echo "----------------------"
if [ -f /var/log/prs-maintenance.log ]; then
    echo "Daily: $(grep "daily routine maintenance completed" /var/log/prs-maintenance.log | tail -1 | cut -d' ' -f1-2)"
    echo "Weekly: $(grep "weekly routine maintenance completed" /var/log/prs-maintenance.log | tail -1 | cut -d' ' -f1-2)"
    echo "Monthly: $(grep "monthly.*completed" /var/log/prs-maintenance.log | tail -1 | cut -d' ' -f1-2)"
else
    echo "No maintenance log found"
fi

echo ""

# Current system status
echo "CURRENT SYSTEM STATUS:"
echo "----------------------"
echo "Uptime: $(uptime -p)"
echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
echo "Memory: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
echo "SSD: $(df -h /mnt/ssd | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
echo "HDD: $(df -h /mnt/hdd | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"

echo ""

# Service status
echo "SERVICE STATUS:"
echo "---------------"
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml ps --format "table {{.Service}}\t{{.State}}"

echo ""

# Next scheduled maintenance
echo "NEXT SCHEDULED MAINTENANCE:"
echo "---------------------------"
echo "Daily: Tomorrow at 1:00 AM"
echo "Weekly: Next Sunday at 2:00 AM"
echo "Monthly: First Sunday of next month at 3:00 AM"
```

---

!!! success "Routine Maintenance Configured"
    Your PRS deployment now has comprehensive routine maintenance procedures with automated daily, weekly, and monthly tasks to ensure optimal system health.

!!! tip "Maintenance Windows"
    Schedule intensive maintenance tasks during low-usage periods and always notify users of planned maintenance activities.

!!! warning "Monitoring Required"
    Always monitor maintenance job execution and review logs regularly to ensure all tasks complete successfully and identify any issues early.
