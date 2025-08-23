#!/bin/bash
# /opt/prs-deployment/scripts/maintenance-status-monitor.sh
# Monitor maintenance job status and health for PRS on-premises deployment

set -euo pipefail

LOG_FILE="/var/log/prs-maintenance-monitor.log"
STATUS_FILE="/var/lib/prs/maintenance-status.json"

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

check_maintenance_jobs() {
    log_message "Checking maintenance job status"

    local current_time=$(date +%s)
    local daily_last_run=0
    local weekly_last_run=0
    local backup_last_run=0

    # Check daily maintenance
    if [ -f "/var/log/prs-maintenance.log" ]; then
        local daily_last_entry=$(grep "Daily maintenance automation completed" /var/log/prs-maintenance.log | tail -1 | cut -d' ' -f1-2)
        if [ -n "$daily_last_entry" ]; then
            daily_last_run=$(date -d "$daily_last_entry" +%s 2>/dev/null || echo 0)
        fi
    fi

    # Check backup status
    local latest_backup=$(ls -t /mnt/hdd/postgres-backups/daily/*.sql* 2>/dev/null | head -1)
    if [ -n "$latest_backup" ]; then
        backup_last_run=$(stat -c %Y "$latest_backup")
    fi

    # Check weekly maintenance
    if [ -f "/var/log/prs-maintenance.log" ]; then
        local weekly_last_entry=$(grep "Weekly maintenance automation completed" /var/log/prs-maintenance.log | tail -1 | cut -d' ' -f1-2)
        if [ -n "$weekly_last_entry" ]; then
            weekly_last_run=$(date -d "$weekly_last_entry" +%s 2>/dev/null || echo 0)
        fi
    fi

    # Calculate time differences (in hours)
    local daily_hours_ago=$(( (current_time - daily_last_run) / 3600 ))
    local backup_hours_ago=$(( (current_time - backup_last_run) / 3600 ))
    local weekly_hours_ago=$(( (current_time - weekly_last_run) / 3600 ))

    log_message "Maintenance status:"
    log_message "  Daily maintenance: ${daily_hours_ago}h ago"
    log_message "  Backup: ${backup_hours_ago}h ago"
    log_message "  Weekly maintenance: ${weekly_hours_ago}h ago"

    # Alert on overdue maintenance
    if [ "$daily_hours_ago" -gt 25 ]; then
        send_alert "Daily maintenance overdue (${daily_hours_ago}h ago)"
    fi

    if [ "$backup_hours_ago" -gt 25 ]; then
        send_alert "Database backup overdue (${backup_hours_ago}h ago)"
    fi

    if [ "$weekly_hours_ago" -gt 168 ]; then  # 7 days
        send_alert "Weekly maintenance overdue (${weekly_hours_ago}h ago)"
    fi
}

check_system_health() {
    log_message "Checking system health indicators"

    # Check disk space
    local ssd_usage=$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')
    local hdd_usage=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')
    local root_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

    log_message "Disk usage: SSD=${ssd_usage}%, HDD=${hdd_usage}%, Root=${root_usage}%"

    if [ "$ssd_usage" -gt 90 ]; then
        send_alert "Critical SSD usage: ${ssd_usage}%"
    elif [ "$ssd_usage" -gt 85 ]; then
        send_alert "High SSD usage: ${ssd_usage}%"
    fi

    if [ "$hdd_usage" -gt 95 ]; then
        send_alert "Critical HDD usage: ${hdd_usage}%"
    fi

    # Check service status
    local services=("prs-onprem-nginx" "prs-onprem-frontend" "prs-onprem-backend" "prs-onprem-postgres-timescale" "prs-onprem-redis")
    local failed_services=()

    for service in "${services[@]}"; do
        if ! docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
            failed_services+=("$service")
        fi
    done

    if [ ${#failed_services[@]} -gt 0 ]; then
        send_alert "Failed services: ${failed_services[*]}"
    fi

    # Check database connectivity
    if ! docker exec prs-onprem-postgres-timescale pg_isready -U "${POSTGRES_USER:-prs_user}" >/dev/null 2>&1; then
        send_alert "Database connectivity failed"
    fi
}

generate_status_report() {
    log_message "Generating maintenance status report"

    mkdir -p "$(dirname "$STATUS_FILE")"

    local current_time=$(date -Iseconds)
    local ssd_usage=$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')
    local hdd_usage=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')

    # Get service status
    local services_status=()
    local services=("prs-onprem-nginx" "prs-onprem-frontend" "prs-onprem-backend" "prs-onprem-postgres-timescale" "prs-onprem-redis")

    for service in "${services[@]}"; do
        if docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
            services_status+=("\"$service\": \"running\"")
        else
            services_status+=("\"$service\": \"stopped\"")
        fi
    done

    # Get latest backup info
    local latest_backup=$(ls -t /mnt/hdd/postgres-backups/daily/*.sql* 2>/dev/null | head -1)
    local backup_age_hours=0
    local backup_size="0"

    if [ -n "$latest_backup" ]; then
        local backup_timestamp=$(stat -c %Y "$latest_backup")
        backup_age_hours=$(( ($(date +%s) - backup_timestamp) / 3600 ))
        backup_size=$(stat -c%s "$latest_backup" | numfmt --to=iec)
    fi

    # Create JSON status report
    cat > "$STATUS_FILE" << EOF
{
    "timestamp": "$current_time",
    "system": {
        "disk_usage": {
            "ssd_percent": $ssd_usage,
            "hdd_percent": $hdd_usage
        },
        "uptime": "$(uptime -p)",
        "load_average": "$(uptime | awk -F'load average:' '{print $2}' | xargs)"
    },
    "services": {
        $(IFS=','; echo "${services_status[*]}")
    },
    "maintenance": {
        "last_backup_hours_ago": $backup_age_hours,
        "backup_size": "$backup_size",
        "database_healthy": $(docker exec prs-onprem-postgres-timescale pg_isready -U "${POSTGRES_USER:-prs_user}" >/dev/null 2>&1 && echo "true" || echo "false")
    }
}
EOF

    log_message "Status report generated: $STATUS_FILE"
}

send_alert() {
    local message="$1"
    local alert_file="/tmp/prs-maintenance-alert-$(echo "$message" | md5sum | cut -d' ' -f1)"
    local current_time=$(date +%s)

    # Rate limiting: don't send same alert within 4 hours
    if [ -f "$alert_file" ]; then
        local last_alert_time=$(cat "$alert_file")
        if [ $((current_time - last_alert_time)) -lt 14400 ]; then
            return 0
        fi
    fi

    echo "$current_time" > "$alert_file"

    log_message "MAINTENANCE ALERT: $message"

    # Send email alert
    if command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "PRS Maintenance Alert" "${ADMIN_EMAIL:-admin@prs.client-domain.com}"
    fi
}

main() {
    log_message "Starting maintenance status monitoring"

    check_maintenance_jobs
    check_system_health
    generate_status_report

    log_message "Maintenance status monitoring completed"
}

main "$@"
