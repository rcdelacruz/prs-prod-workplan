#!/bin/bash
# /opt/prs-deployment/scripts/generate-monitoring-report.sh
# Generate comprehensive monitoring report for PRS on-premises deployment

set -euo pipefail

LOG_FILE="/var/log/prs-monitoring.log"
REPORT_DIR="/tmp/prs-reports"
DATE=$(date +%Y%m%d)

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

generate_system_report() {
    cat << EOF
SYSTEM STATUS REPORT
====================
Generated: $(date)
Hostname: $(hostname)

SYSTEM RESOURCES
----------------
CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')%
Memory Usage: $(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')%
Load Average: $(uptime | awk -F'load average:' '{print $2}')

STORAGE USAGE
-------------
SSD (/mnt/ssd): $(df -h /mnt/ssd | awk 'NR==2 {print $5 " used (" $3 "/" $2 ")"}')
HDD (/mnt/hdd): $(df -h /mnt/hdd | awk 'NR==2 {print $5 " used (" $3 "/" $2 ")"}')
Root (/): $(df -h / | awk 'NR==2 {print $5 " used (" $3 "/" $2 ")"}')

NETWORK STATUS
--------------
$(ip addr show | grep -E "inet.*eth0" | awk '{print "IP Address: " $2}')
$(ss -tuln | grep -E "(80|443|5432|6379)" | wc -l) active network connections

UPTIME
------
$(uptime)

EOF
}

generate_service_report() {
    cat << EOF
SERVICE STATUS REPORT
=====================

DOCKER SERVICES
---------------
$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" 2>/dev/null || echo "Docker not available")

SERVICE HEALTH CHECKS
---------------------
EOF

    # Check each service endpoint
    local services=("nginx" "frontend" "backend" "postgres" "redis" "grafana" "prometheus")
    for service in "${services[@]}"; do
        if docker ps --filter "name=prs-onprem-$service" --filter "status=running" | grep -q "prs-onprem-$service"; then
            echo "✓ prs-onprem-$service: RUNNING"
        else
            echo "✗ prs-onprem-$service: STOPPED"
        fi
    done

    cat << EOF

APPLICATION ENDPOINTS
---------------------
EOF

    # Test application endpoints
    local endpoints=("https://localhost/" "https://localhost/api/health")
    for endpoint in "${endpoints[@]}"; do
        local status=$(curl -s -o /dev/null -w "%{http_code}" "$endpoint" 2>/dev/null || echo "000")
        local time=$(curl -w "%{time_total}" -o /dev/null -s "$endpoint" 2>/dev/null || echo "0")
        if [ "$status" = "200" ]; then
            echo "✓ $endpoint: OK (${time}s)"
        else
            echo "✗ $endpoint: FAILED (HTTP $status)"
        fi
    done

    echo ""
}

generate_database_report() {
    cat << EOF
DATABASE STATUS REPORT
======================

DATABASE METRICS
----------------
EOF

    if docker exec prs-onprem-postgres-timescale pg_isready -U "${POSTGRES_USER:-prs_user}" >/dev/null 2>&1; then
        local db_size=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB:-prs_production}'));" | xargs)
        local connections=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "SELECT count(*) FROM pg_stat_activity;" | xargs)
        local cache_hit=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "SELECT round(100.0 * sum(blks_hit) / nullif(sum(blks_hit) + sum(blks_read), 0), 2) FROM pg_stat_database WHERE datname = '${POSTGRES_DB:-prs_production}';" | xargs)

        echo "Database Size: $db_size"
        echo "Active Connections: $connections"
        echo "Cache Hit Ratio: ${cache_hit}%"
        echo "Database Status: HEALTHY"
    else
        echo "Database Status: UNAVAILABLE"
    fi

    cat << EOF

TIMESCALEDB STATUS
------------------
EOF

    if docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "SELECT 1;" >/dev/null 2>&1; then
        local chunks=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "SELECT count(*) FROM timescaledb_information.chunks;" | xargs)
        local compressed=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "SELECT count(*) FROM timescaledb_information.chunks WHERE is_compressed = true;" | xargs)

        echo "Total Chunks: $chunks"
        echo "Compressed Chunks: $compressed"
        if [ "$chunks" -gt 0 ]; then
            local compression_ratio=$(echo "scale=2; $compressed * 100 / $chunks" | bc)
            echo "Compression Ratio: ${compression_ratio}%"
        fi
    else
        echo "TimescaleDB: UNAVAILABLE"
    fi

    echo ""
}

generate_performance_report() {
    cat << EOF
PERFORMANCE METRICS REPORT
==========================

RECENT ALERTS
-------------
EOF

    # Check for recent alerts in logs
    if [ -f "$LOG_FILE" ]; then
        local recent_alerts=$(grep "ALERT\|WARNING\|ERROR" "$LOG_FILE" | tail -10)
        if [ -n "$recent_alerts" ]; then
            echo "$recent_alerts"
        else
            echo "No recent alerts found"
        fi
    else
        echo "No monitoring log available"
    fi

    cat << EOF

BACKUP STATUS
-------------
EOF

    # Check backup status
    local latest_backup=$(ls -t /mnt/hdd/postgres-backups/daily/*.sql* 2>/dev/null | head -1)
    if [ -n "$latest_backup" ]; then
        local backup_age_hours=$(( ($(date +%s) - $(stat -c %Y "$latest_backup")) / 3600 ))
        local backup_size=$(stat -c%s "$latest_backup" | numfmt --to=iec)
        echo "Latest Backup: $(basename "$latest_backup")"
        echo "Backup Age: ${backup_age_hours} hours"
        echo "Backup Size: $backup_size"
    else
        echo "No backups found"
    fi

    cat << EOF

STORAGE TRENDS
--------------
EOF

    # Storage usage trends
    echo "SSD Usage Trend: $(df /mnt/ssd | awk 'NR==2 {print $5}')"
    echo "HDD Usage Trend: $(df /mnt/hdd | awk 'NR==2 {print $5}')"

    # Check for large files
    local large_files=$(find /mnt/ssd -type f -size +100M 2>/dev/null | wc -l)
    echo "Large Files (>100MB): $large_files"

    echo ""
}

main() {
    log_message "Generating monitoring report"

    # Create report directory
    mkdir -p "$REPORT_DIR"

    local report_file="$REPORT_DIR/prs-monitoring-report-$DATE.txt"

    # Generate comprehensive report
    {
        generate_system_report
        generate_service_report
        generate_database_report
        generate_performance_report

        cat << EOF
RECOMMENDATIONS
===============
EOF

        # Generate recommendations based on current status
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d. -f1)
        local memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
        local ssd_usage=$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')

        if [ "$cpu_usage" -gt 80 ]; then
            echo "- High CPU usage detected ($cpu_usage%) - consider optimizing or scaling"
        fi

        if [ "$memory_usage" -gt 85 ]; then
            echo "- High memory usage detected ($memory_usage%) - monitor for memory leaks"
        fi

        if [ "$ssd_usage" -gt 80 ]; then
            echo "- High SSD usage detected ($ssd_usage%) - consider cleanup or expansion"
        fi

        # Check if all services are running
        local stopped_services=$(docker ps -a --filter "name=prs-onprem" --filter "status=exited" --format "{{.Names}}" | wc -l)
        if [ "$stopped_services" -gt 0 ]; then
            echo "- Some services are stopped - investigate and restart if needed"
        fi

        echo ""
        echo "Report generated at: $(date)"
        echo "Next report scheduled for: $(date -d '+1 day')"

    } > "$report_file"

    log_message "Monitoring report generated: $report_file"

    # Email report if configured
    if command -v mail >/dev/null 2>&1; then
        mail -s "PRS Daily Monitoring Report" "${ADMIN_EMAIL:-admin@prs.client-domain.com}" < "$report_file"
        log_message "Monitoring report emailed"
    fi

    # Cleanup old reports (keep last 30 days)
    find "$REPORT_DIR" -name "prs-monitoring-report-*.txt" -mtime +30 -delete
}

main "$@"
