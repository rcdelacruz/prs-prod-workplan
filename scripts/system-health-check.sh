#!/bin/bash
# PRS Production Server - Enhanced System Health Check and Monitoring Script
# Comprehensive health monitoring with alerting and detailed analysis

set -euo pipefail

LOG_FILE="/var/log/prs-health-check.log"
HEALTH_REPORT="/tmp/prs-health-report-$(date +%Y%m%d_%H%M%S).txt"
ALERT_THRESHOLD_FILE="/etc/prs/alert-thresholds.conf"

# Default thresholds
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
DISK_THRESHOLD=90
LOAD_THRESHOLD_MULTIPLIER=1.5

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/02-docker-configuration/.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

# Load custom thresholds if available
if [ -f "$ALERT_THRESHOLD_FILE" ]; then
    source "$ALERT_THRESHOLD_FILE"
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

output() {
    echo "$1" | tee -a "$HEALTH_REPORT"
}

send_alert() {
    local severity="$1"
    local message="$2"

    log_message "ALERT [$severity] $message"

    if command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "PRS Health Alert: $severity" "${ADMIN_EMAIL:-admin@prs.client-domain.com}"
    fi
}

output "=== PRS Production Server Enhanced Health Check ==="
output "Timestamp: $(date)"
output "Hostname: $(hostname)"
output ""

# Enhanced system resource monitoring
check_system_resources() {
    output "=== Enhanced System Resources Analysis ==="

    # CPU Analysis
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d. -f1)
    local load_1min=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local load_5min=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $2}' | sed 's/,//')
    local load_15min=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $3}')
    local cpu_cores=$(nproc)
    local load_threshold=$(echo "$cpu_cores * $LOAD_THRESHOLD_MULTIPLIER" | bc)

    output "CPU Analysis:"
    output "  Current Usage: ${cpu_usage}%"
    output "  Load Average: $load_1min (1m), $load_5min (5m), $load_15min (15m)"
    output "  CPU Cores: $cpu_cores"
    output "  Load Threshold: $load_threshold"

    if [ "$cpu_usage" -gt "$CPU_THRESHOLD" ]; then
        output "  ⚠️  HIGH CPU USAGE: ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)"
        send_alert "WARNING" "High CPU usage: ${cpu_usage}%"
    else
        output "  ✅ CPU usage normal: ${cpu_usage}%"
    fi

    if (( $(echo "$load_1min > $load_threshold" | bc -l) )); then
        output "  ⚠️  HIGH LOAD AVERAGE: $load_1min (threshold: $load_threshold)"
        send_alert "WARNING" "High load average: $load_1min"
    else
        output "  ✅ Load average normal: $load_1min"
    fi

    # Memory Analysis
    local memory_total=$(free -b | grep Mem | awk '{print $2}')
    local memory_used=$(free -b | grep Mem | awk '{print $3}')
    local memory_available=$(free -b | grep Mem | awk '{print $7}')
    local memory_usage_percent=$(echo "scale=1; $memory_used * 100 / $memory_total" | bc)
    local swap_total=$(free -b | grep Swap | awk '{print $2}')
    local swap_used=$(free -b | grep Swap | awk '{print $3}')

    output ""
    output "Memory Analysis:"
    output "  Total: $(numfmt --to=iec $memory_total)"
    output "  Used: $(numfmt --to=iec $memory_used) (${memory_usage_percent}%)"
    output "  Available: $(numfmt --to=iec $memory_available)"

    if [ "$swap_total" -gt 0 ]; then
        local swap_usage_percent=$(echo "scale=1; $swap_used * 100 / $swap_total" | bc)
        output "  Swap Used: $(numfmt --to=iec $swap_used) (${swap_usage_percent}%)"

        if (( $(echo "$swap_usage_percent > 10" | bc -l) )); then
            output "  ⚠️  HIGH SWAP USAGE: ${swap_usage_percent}%"
            send_alert "WARNING" "High swap usage: ${swap_usage_percent}%"
        fi
    fi

    if (( $(echo "$memory_usage_percent > $MEMORY_THRESHOLD" | bc -l) )); then
        output "  ⚠️  HIGH MEMORY USAGE: ${memory_usage_percent}% (threshold: ${MEMORY_THRESHOLD}%)"
        send_alert "WARNING" "High memory usage: ${memory_usage_percent}%"
    else
        output "  ✅ Memory usage normal: ${memory_usage_percent}%"
    fi

    # Disk Analysis
    output ""
    output "Disk Analysis:"

    local filesystems=("/" "/mnt/hdd")
    for fs in "${filesystems[@]}"; do
        if mountpoint -q "$fs" 2>/dev/null || [ "$fs" = "/" ]; then
            local disk_usage=$(df "$fs" | awk 'NR==2 {print $5}' | sed 's/%//')
            local disk_total=$(df -h "$fs" | awk 'NR==2 {print $2}')
            local disk_used=$(df -h "$fs" | awk 'NR==2 {print $3}')
            local disk_available=$(df -h "$fs" | awk 'NR==2 {print $4}')

            output "  $fs: ${disk_used}/${disk_total} (${disk_usage}% used, ${disk_available} available)"

            if [ "$disk_usage" -gt "$DISK_THRESHOLD" ]; then
                output "    ⚠️  HIGH DISK USAGE: ${disk_usage}% (threshold: ${DISK_THRESHOLD}%)"
                send_alert "CRITICAL" "High disk usage on $fs: ${disk_usage}%"
            elif [ "$disk_usage" -gt 80 ]; then
                output "    ⚠️  Moderate disk usage: ${disk_usage}%"
            else
                output "    ✅ Disk usage normal: ${disk_usage}%"
            fi
        fi
    done

    output ""
}

# Enhanced Docker and application monitoring
check_docker_services() {
    output "=== Docker Services Analysis ==="

    if command -v docker &> /dev/null && docker info &> /dev/null; then
        # Check PRS services
        local prs_services=("prs-onprem-nginx" "prs-onprem-frontend" "prs-onprem-backend" "prs-onprem-postgres-timescale" "prs-onprem-redis")
        local failed_services=()

        output "PRS Service Status:"
        for service in "${prs_services[@]}"; do
            if docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
                local uptime=$(docker ps --filter "name=$service" --format "{{.RunningFor}}")
                local status=$(docker ps --filter "name=$service" --format "{{.Status}}")
                output "  ✅ $service: Running ($uptime)"

                # Check resource usage
                local memory_usage=$(docker stats "$service" --no-stream --format "{{.MemUsage}}" | cut -d'/' -f1)
                local cpu_usage=$(docker stats "$service" --no-stream --format "{{.CPUPerc}}")
                output "    Resources: CPU $cpu_usage, Memory $memory_usage"
            else
                output "  ❌ $service: NOT RUNNING"
                failed_services+=("$service")
            fi
        done

        if [ ${#failed_services[@]} -gt 0 ]; then
            send_alert "CRITICAL" "Failed services: ${failed_services[*]}"
        fi

        # Docker system resources
        output ""
        output "Docker System Resources:"
        docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}\t{{.Reclaimable}}" | while read -r line; do
            output "  $line"
        done

        # Check for unhealthy containers
        local unhealthy=$(docker ps --filter "health=unhealthy" --format "{{.Names}}")
        if [ -n "$unhealthy" ]; then
            output "  ⚠️  Unhealthy containers: $unhealthy"
            send_alert "WARNING" "Unhealthy containers detected: $unhealthy"
        fi

    else
        output "❌ Docker not available or not running"
        send_alert "CRITICAL" "Docker service not available"
    fi

    output ""
}

check_application_health() {
    output "=== Application Health Analysis ==="

    # Test API endpoints
    local endpoints=(
        "https://localhost/api/health"
        "https://localhost/"
    )

    for endpoint in "${endpoints[@]}"; do
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" -k "$endpoint" 2>/dev/null || echo "000")
        local response_time=$(curl -w "%{time_total}" -o /dev/null -s -k "$endpoint" 2>/dev/null || echo "0")

        if [ "$response_code" = "200" ]; then
            output "  ✅ $endpoint: OK (${response_time}s)"
        else
            output "  ❌ $endpoint: FAILED (HTTP $response_code)"
            send_alert "CRITICAL" "Application endpoint failed: $endpoint (HTTP $response_code)"
        fi
    done

    # Database connectivity
    if docker exec prs-onprem-postgres-timescale pg_isready -U "${POSTGRES_USER:-prs_user}" >/dev/null 2>&1; then
        local db_connections=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "0")
        output "  ✅ Database: Connected ($db_connections active connections)"

        if [ "$db_connections" -gt 100 ]; then
            output "    ⚠️  High connection count: $db_connections"
            send_alert "WARNING" "High database connection count: $db_connections"
        fi
    else
        output "  ❌ Database: Connection failed"
        send_alert "CRITICAL" "Database connection failed"
    fi

    # Redis connectivity
    if docker exec prs-onprem-redis redis-cli -a "${REDIS_PASSWORD:-}" ping >/dev/null 2>&1; then
        local redis_memory=$(docker exec prs-onprem-redis redis-cli -a "${REDIS_PASSWORD:-}" info memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r')
        output "  ✅ Redis: Connected (Memory: $redis_memory)"
    else
        output "  ❌ Redis: Connection failed"
        send_alert "CRITICAL" "Redis connection failed"
    fi

    output ""
}

check_network_security() {
    output "=== Network and Security Analysis ==="

    # Network connections
    output "Active Network Connections:"
    local important_ports=(80 443 22 5432 6379 9090 3001 8080 9000)
    for port in "${important_ports[@]}"; do
        local connections=$(ss -tuln | grep ":$port " | wc -l)
        if [ "$connections" -gt 0 ]; then
            output "  Port $port: $connections connections"
        fi
    done

    # Check for suspicious network activity
    local failed_ssh=$(grep "Failed password" /var/log/auth.log 2>/dev/null | grep "$(date +%Y-%m-%d)" | wc -l)
    if [ "$failed_ssh" -gt 10 ]; then
        output "  ⚠️  High failed SSH attempts today: $failed_ssh"
        send_alert "WARNING" "High failed SSH attempts: $failed_ssh"
    else
        output "  ✅ SSH security normal: $failed_ssh failed attempts today"
    fi

    # SSL certificate check
    if [ -f "$PROJECT_DIR/02-docker-configuration/ssl/certificate.crt" ]; then
        local cert_expiry=$(openssl x509 -in "$PROJECT_DIR/02-docker-configuration/ssl/certificate.crt" -noout -enddate | cut -d= -f2)
        local expiry_epoch=$(date -d "$cert_expiry" +%s)
        local current_epoch=$(date +%s)
        local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))

        if [ "$days_until_expiry" -lt 30 ]; then
            output "  ⚠️  SSL certificate expires in $days_until_expiry days"
            send_alert "WARNING" "SSL certificate expires in $days_until_expiry days"
        else
            output "  ✅ SSL certificate valid for $days_until_expiry days"
        fi
    fi

    output ""
}

check_system_logs() {
    output "=== System Logs Analysis ==="

    # Recent errors
    local recent_errors=$(journalctl --since "1 hour ago" -p err --no-pager -q | wc -l)
    output "Recent errors (last hour): $recent_errors"

    if [ "$recent_errors" -gt 10 ]; then
        output "  ⚠️  High error count in system logs"
        send_alert "WARNING" "High error count in system logs: $recent_errors"
    fi

    # Docker service logs
    local services=("prs-onprem-backend" "prs-onprem-frontend" "prs-onprem-nginx")
    for service in "${services[@]}"; do
        if docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
            local error_count=$(docker logs "$service" --since 1h 2>&1 | grep -i error | wc -l)
            output "  $service errors (last hour): $error_count"

            if [ "$error_count" -gt 5 ]; then
                output "    ⚠️  High error count in $service"
                send_alert "WARNING" "High error count in $service: $error_count"
            fi
        fi
    done

    output ""
}

generate_recommendations() {
    output "=== Health Recommendations ==="

    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d. -f1)
    local memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    # SSD usage check removed - using HDD-only configuration

    if [ "$cpu_usage" -gt 80 ]; then
        output "  🔧 High CPU usage ($cpu_usage%) - Consider optimizing applications or scaling"
    fi

    if [ "$memory_usage" -gt 85 ]; then
        output "  🔧 High memory usage ($memory_usage%) - Monitor for memory leaks or add more RAM"
    fi

    if [ "$ssd_usage" -gt 80 ]; then
        output "  🔧 High SSD usage ($ssd_usage%) - Consider cleanup or storage expansion"
    fi

    # Check backup status
    local latest_backup=$(ls -t /mnt/hdd/postgres-backups/daily/*.sql* 2>/dev/null | head -1)
    if [ -n "$latest_backup" ]; then
        local backup_age_hours=$(( ($(date +%s) - $(stat -c %Y "$latest_backup")) / 3600 ))
        if [ "$backup_age_hours" -gt 25 ]; then
            output "  🔧 Latest backup is $backup_age_hours hours old - Check backup automation"
        fi
    else
        output "  🔧 No recent backups found - Verify backup system"
    fi

    # Check for available updates
    local security_updates=$(apt list --upgradable 2>/dev/null | grep security | wc -l)
    if [ "$security_updates" -gt 0 ]; then
        output "  🔧 $security_updates security updates available - Schedule maintenance"
    fi

    output ""
}

main() {
    log_message "Starting enhanced health check"

    # Execute all health checks
    check_system_resources
    check_docker_services
    check_application_health
    check_network_security
    check_system_logs
    generate_recommendations

    output "✅ Enhanced health check completed"
    output "Report saved to: $HEALTH_REPORT"
    output "=== End Enhanced Health Check ==="

    log_message "Health check completed, report: $HEALTH_REPORT"

    # Email report if configured
    if command -v mail >/dev/null 2>&1; then
        mail -s "PRS Health Check Report" "${ADMIN_EMAIL:-admin@prs.client-domain.com}" < "$HEALTH_REPORT"
    fi
}

# Execute main function
main "$@"
