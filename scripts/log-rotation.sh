#!/bin/bash
# /opt/prs-deployment/scripts/log-rotation.sh
# Log management and rotation for PRS on-premises deployment

set -euo pipefail

LOG_FILE="/var/log/prs-log-rotation.log"
APP_LOG_DIR="${STORAGE_HDD_PATH:-/mnt/hdd}/logs"
SYSTEM_LOG_DIR="/var/log"

# Retention policies (days)
APP_LOG_RETENTION=30
SYSTEM_LOG_RETENTION=90
COMPRESSED_LOG_RETENTION=365

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

rotate_application_logs() {
    log_message "Rotating application logs"

    if [ ! -d "$APP_LOG_DIR" ]; then
        log_message "Application log directory not found: $APP_LOG_DIR"
        return 1
    fi

    # Rotate and compress logs older than 1 day
    find "$APP_LOG_DIR" -name "*.log" -mtime +1 -exec gzip {} \;
    local compressed_count=$(find "$APP_LOG_DIR" -name "*.log" -mtime +1 | wc -l)
    log_message "Compressed $compressed_count application log files"

    # Remove old compressed logs
    local removed_count=$(find "$APP_LOG_DIR" -name "*.log.gz" -mtime +$APP_LOG_RETENTION -delete -print | wc -l)
    log_message "Removed $removed_count old compressed application logs"

    # Handle large log files (>100MB)
    local large_logs=$(find "$APP_LOG_DIR" -name "*.log" -size +100M)
    if [ -n "$large_logs" ]; then
        log_message "Found large log files:"
        echo "$large_logs" | while read -r logfile; do
            log_message "  $(basename "$logfile"): $(stat -c%s "$logfile" | numfmt --to=iec)"

            # Truncate large active log files
            if [[ "$logfile" == *"current"* ]] || [[ "$logfile" == *"$(date +%Y%m%d)"* ]]; then
                log_message "Truncating large active log: $logfile"
                tail -n 10000 "$logfile" > "${logfile}.tmp"
                mv "${logfile}.tmp" "$logfile"
            fi
        done
    fi
}

rotate_docker_logs() {
    log_message "Managing Docker container logs"

    # Get Docker log sizes
    local services=("prs-onprem-nginx" "prs-onprem-frontend" "prs-onprem-backend" "prs-onprem-postgres-timescale" "prs-onprem-redis")

    for service in "${services[@]}"; do
        if docker ps --filter "name=$service" --format "{{.Names}}" | grep -q "$service"; then
            local log_path=$(docker inspect "$service" --format='{{.LogPath}}' 2>/dev/null || echo "")
            if [ -n "$log_path" ] && [ -f "$log_path" ]; then
                local log_size=$(stat -c%s "$log_path" | numfmt --to=iec)
                log_message "$service log size: $log_size"

                # Rotate if log is larger than 100MB
                if [ $(stat -c%s "$log_path") -gt 104857600 ]; then
                    log_message "Rotating large Docker log for $service"
                    docker logs "$service" --tail 1000 > "/tmp/${service}-$(date +%Y%m%d).log"
                    echo "" > "$log_path"  # Truncate log
                fi
            fi
        fi
    done
}

rotate_system_logs() {
    log_message "Managing system logs"

    # Compress old system logs
    find "$SYSTEM_LOG_DIR" -name "*.log" -mtime +7 -not -name "prs-*" -exec gzip {} \;

    # Remove very old compressed system logs
    local removed_system=$(find "$SYSTEM_LOG_DIR" -name "*.log.gz" -mtime +$SYSTEM_LOG_RETENTION -delete -print | wc -l)
    log_message "Removed $removed_system old system log files"

    # Manage auth logs
    if [ -f "/var/log/auth.log" ]; then
        local auth_size=$(stat -c%s "/var/log/auth.log" | numfmt --to=iec)
        log_message "Auth log size: $auth_size"

        if [ $(stat -c%s "/var/log/auth.log") -gt 52428800 ]; then  # 50MB
            log_message "Rotating large auth.log"
            cp /var/log/auth.log "/var/log/auth.log.$(date +%Y%m%d)"
            gzip "/var/log/auth.log.$(date +%Y%m%d)"
            echo "" > /var/log/auth.log
        fi
    fi

    # Manage syslog
    if [ -f "/var/log/syslog" ]; then
        local syslog_size=$(stat -c%s "/var/log/syslog" | numfmt --to=iec)
        log_message "Syslog size: $syslog_size"

        if [ $(stat -c%s "/var/log/syslog") -gt 52428800 ]; then  # 50MB
            log_message "Rotating large syslog"
            cp /var/log/syslog "/var/log/syslog.$(date +%Y%m%d)"
            gzip "/var/log/syslog.$(date +%Y%m%d)"
            echo "" > /var/log/syslog
        fi
    fi
}

cleanup_old_logs() {
    log_message "Cleaning up very old logs"

    # Remove very old compressed logs
    local removed_compressed=$(find "$APP_LOG_DIR" "$SYSTEM_LOG_DIR" -name "*.log.gz" -mtime +$COMPRESSED_LOG_RETENTION -delete -print 2>/dev/null | wc -l)
    log_message "Removed $removed_compressed very old compressed logs"

    # Clean up temporary log files
    find /tmp -name "*-$(date -d '7 days ago' +%Y%m%d).log" -delete 2>/dev/null || true
    find /tmp -name "*.log" -mtime +7 -delete 2>/dev/null || true
}

generate_log_report() {
    log_message "Generating log usage report"

    local report_file="/tmp/log-usage-report-$(date +%Y%m%d).txt"

    cat > "$report_file" << EOF
PRS Log Usage Report
Generated: $(date)

APPLICATION LOGS ($APP_LOG_DIR):
$(du -sh "$APP_LOG_DIR" 2>/dev/null || echo "Directory not found")

Top 10 largest application log files:
$(find "$APP_LOG_DIR" -type f -name "*.log*" -exec ls -lh {} \; 2>/dev/null | sort -k5 -hr | head -10 || echo "No log files found")

SYSTEM LOGS ($SYSTEM_LOG_DIR):
$(du -sh "$SYSTEM_LOG_DIR" 2>/dev/null || echo "Directory not found")

PRS-specific logs:
$(find "$SYSTEM_LOG_DIR" -name "prs-*.log" -exec ls -lh {} \; 2>/dev/null || echo "No PRS logs found")

DOCKER LOGS:
EOF

    # Add Docker log information
    local services=("prs-onprem-nginx" "prs-onprem-frontend" "prs-onprem-backend" "prs-onprem-postgres-timescale" "prs-onprem-redis")

    for service in "${services[@]}"; do
        if docker ps --filter "name=$service" --format "{{.Names}}" | grep -q "$service"; then
            local log_path=$(docker inspect "$service" --format='{{.LogPath}}' 2>/dev/null || echo "")
            if [ -n "$log_path" ] && [ -f "$log_path" ]; then
                local log_size=$(stat -c%s "$log_path" | numfmt --to=iec)
                echo "$service: $log_size" >> "$report_file"
            fi
        fi
    done

    cat >> "$report_file" << EOF

DISK USAGE SUMMARY:
Total log storage: $(du -sh "$APP_LOG_DIR" "$SYSTEM_LOG_DIR" 2>/dev/null | awk '{sum+=$1} END {print sum "B"}' || echo "Unknown")

RECOMMENDATIONS:
EOF

    # Add recommendations based on usage
    local app_usage_mb=$(du -sm "$APP_LOG_DIR" 2>/dev/null | cut -f1 || echo 0)
    if [ "$app_usage_mb" -gt 1000 ]; then
        echo "- Application logs are using ${app_usage_mb}MB, consider more aggressive rotation" >> "$report_file"
    fi

    local large_files=$(find "$APP_LOG_DIR" -name "*.log" -size +50M 2>/dev/null | wc -l)
    if [ "$large_files" -gt 0 ]; then
        echo "- Found $large_files large log files (>50MB), consider immediate rotation" >> "$report_file"
    fi

    log_message "Log usage report generated: $report_file"
}

main() {
    log_message "Starting log rotation and management"

    rotate_application_logs
    rotate_docker_logs
    rotate_system_logs
    cleanup_old_logs
    generate_log_report

    log_message "Log rotation and management completed"
}

main "$@"
