#!/bin/bash
# /opt/prs-deployment/scripts/system-performance-monitor.sh
# Comprehensive system performance monitoring for PRS on-premises deployment

set -euo pipefail

METRICS_FILE="/var/lib/node_exporter/textfile_collector/prs-metrics.prom"
LOG_FILE="/var/log/prs-monitoring.log"
ALERT_THRESHOLD_FILE="/etc/prs/alert-thresholds.conf"

# Default alert thresholds
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
DISK_THRESHOLD=90
RESPONSE_TIME_THRESHOLD=2000
CONNECTION_THRESHOLD=120

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

collect_system_metrics() {
    local timestamp=$(date +%s)

    # CPU metrics
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    local load_1min=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local load_5min=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $2}' | sed 's/,//')
    local load_15min=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $3}')

    # Memory metrics
    local memory_total=$(free -b | grep Mem | awk '{print $2}')
    local memory_used=$(free -b | grep Mem | awk '{print $3}')
    local memory_free=$(free -b | grep Mem | awk '{print $4}')
    local memory_available=$(free -b | grep Mem | awk '{print $7}')
    local memory_usage_percent=$(echo "scale=2; $memory_used * 100 / $memory_total" | bc)

    # Disk metrics
    local ssd_total=$(df -B1 /mnt/ssd | awk 'NR==2 {print $2}')
    local ssd_used=$(df -B1 /mnt/ssd | awk 'NR==2 {print $3}')
    local ssd_available=$(df -B1 /mnt/ssd | awk 'NR==2 {print $4}')
    local ssd_usage_percent=$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')

    local hdd_total=$(df -B1 /mnt/hdd | awk 'NR==2 {print $2}')
    local hdd_used=$(df -B1 /mnt/hdd | awk 'NR==2 {print $3}')
    local hdd_available=$(df -B1 /mnt/hdd | awk 'NR==2 {print $4}')
    local hdd_usage_percent=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')

    # Network metrics
    local network_rx_bytes=$(cat /proc/net/dev | grep eth0 | awk '{print $2}')
    local network_tx_bytes=$(cat /proc/net/dev | grep eth0 | awk '{print $10}')

    # Write Prometheus metrics
    mkdir -p "$(dirname "$METRICS_FILE")"
    cat > "$METRICS_FILE" << EOF
# HELP prs_cpu_usage_percent CPU usage percentage
# TYPE prs_cpu_usage_percent gauge
prs_cpu_usage_percent $cpu_usage

# HELP prs_load_average System load average
# TYPE prs_load_average gauge
prs_load_average{period="1m"} $load_1min
prs_load_average{period="5m"} $load_5min
prs_load_average{period="15m"} $load_15min

# HELP prs_memory_bytes Memory usage in bytes
# TYPE prs_memory_bytes gauge
prs_memory_bytes{type="total"} $memory_total
prs_memory_bytes{type="used"} $memory_used
prs_memory_bytes{type="free"} $memory_free
prs_memory_bytes{type="available"} $memory_available

# HELP prs_memory_usage_percent Memory usage percentage
# TYPE prs_memory_usage_percent gauge
prs_memory_usage_percent $memory_usage_percent

# HELP prs_disk_bytes Disk usage in bytes
# TYPE prs_disk_bytes gauge
prs_disk_bytes{device="ssd",type="total"} $ssd_total
prs_disk_bytes{device="ssd",type="used"} $ssd_used
prs_disk_bytes{device="ssd",type="available"} $ssd_available
prs_disk_bytes{device="hdd",type="total"} $hdd_total
prs_disk_bytes{device="hdd",type="used"} $hdd_used
prs_disk_bytes{device="hdd",type="available"} $hdd_available

# HELP prs_disk_usage_percent Disk usage percentage
# TYPE prs_disk_usage_percent gauge
prs_disk_usage_percent{device="ssd"} $ssd_usage_percent
prs_disk_usage_percent{device="hdd"} $hdd_usage_percent

# HELP prs_network_bytes Network traffic in bytes
# TYPE prs_network_bytes counter
prs_network_bytes{direction="rx"} $network_rx_bytes
prs_network_bytes{direction="tx"} $network_tx_bytes
EOF

    log_message "System metrics collected: CPU=${cpu_usage}%, Memory=${memory_usage_percent}%, SSD=${ssd_usage_percent}%, HDD=${hdd_usage_percent}%"
}

collect_application_metrics() {
    # Database metrics
    local db_connections=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "0")
    local db_size_bytes=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "SELECT pg_database_size('${POSTGRES_DB:-prs_production}');" 2>/dev/null | xargs || echo "0")
    local cache_hit_ratio=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "SELECT round(100.0 * sum(blks_hit) / nullif(sum(blks_hit) + sum(blks_read), 0), 2) FROM pg_stat_database WHERE datname = '${POSTGRES_DB:-prs_production}';" 2>/dev/null | xargs || echo "0")

    # Redis metrics
    local redis_connected_clients=$(docker exec prs-onprem-redis redis-cli -a "${REDIS_PASSWORD:-}" info clients 2>/dev/null | grep connected_clients | cut -d: -f2 | tr -d '\r' || echo "0")
    local redis_used_memory=$(docker exec prs-onprem-redis redis-cli -a "${REDIS_PASSWORD:-}" info memory 2>/dev/null | grep used_memory: | cut -d: -f2 | tr -d '\r' || echo "0")

    # Application metrics
    local active_sessions=$(docker exec prs-onprem-redis redis-cli -a "${REDIS_PASSWORD:-}" eval "return #redis.call('keys', 'session:*')" 0 2>/dev/null || echo "0")

    # API response time test
    local api_response_time=$(curl -w "%{time_total}" -o /dev/null -s https://localhost/api/health 2>/dev/null || echo "0")
    local api_response_time_ms=$(echo "$api_response_time * 1000" | bc)

    # Service status
    local services=("prs-onprem-nginx" "prs-onprem-frontend" "prs-onprem-backend" "prs-onprem-postgres-timescale" "prs-onprem-redis")

    # Append application metrics to Prometheus file
    cat >> "$METRICS_FILE" << EOF

# HELP prs_database_connections Active database connections
# TYPE prs_database_connections gauge
prs_database_connections $db_connections

# HELP prs_database_size_bytes Database size in bytes
# TYPE prs_database_size_bytes gauge
prs_database_size_bytes $db_size_bytes

# HELP prs_database_cache_hit_ratio Database cache hit ratio percentage
# TYPE prs_database_cache_hit_ratio gauge
prs_database_cache_hit_ratio $cache_hit_ratio

# HELP prs_redis_connected_clients Redis connected clients
# TYPE prs_redis_connected_clients gauge
prs_redis_connected_clients $redis_connected_clients

# HELP prs_redis_used_memory_bytes Redis memory usage in bytes
# TYPE prs_redis_used_memory_bytes gauge
prs_redis_used_memory_bytes $redis_used_memory

# HELP prs_active_sessions Active user sessions
# TYPE prs_active_sessions gauge
prs_active_sessions $active_sessions

# HELP prs_api_response_time_ms API response time in milliseconds
# TYPE prs_api_response_time_ms gauge
prs_api_response_time_ms $api_response_time_ms
EOF

    # Service status metrics
    for service in "${services[@]}"; do
        if docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
            echo "prs_service_up{service=\"$service\"} 1" >> "$METRICS_FILE"
        else
            echo "prs_service_up{service=\"$service\"} 0" >> "$METRICS_FILE"
        fi
    done

    log_message "Application metrics collected: DB_Conn=$db_connections, Sessions=$active_sessions, API_Time=${api_response_time_ms}ms"
}

check_alerts() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d. -f1)
    local memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    local ssd_usage=$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')
    local hdd_usage=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')
    local db_connections=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "0")
    local api_response_time_ms=$(curl -w "%{time_total}" -o /dev/null -s https://localhost/api/health 2>/dev/null | awk '{print $1 * 1000}' || echo "0")

    # Check thresholds and send alerts
    if [ "$cpu_usage" -gt "$CPU_THRESHOLD" ]; then
        send_alert "WARNING" "High CPU usage: ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)"
    fi

    if [ "$memory_usage" -gt "$MEMORY_THRESHOLD" ]; then
        send_alert "WARNING" "High memory usage: ${memory_usage}% (threshold: ${MEMORY_THRESHOLD}%)"
    fi

    if [ "$ssd_usage" -gt "$DISK_THRESHOLD" ]; then
        send_alert "CRITICAL" "High SSD usage: ${ssd_usage}% (threshold: ${DISK_THRESHOLD}%)"
    fi

    if [ "$hdd_usage" -gt "$DISK_THRESHOLD" ]; then
        send_alert "WARNING" "High HDD usage: ${hdd_usage}% (threshold: ${DISK_THRESHOLD}%)"
    fi

    if [ "$db_connections" -gt "$CONNECTION_THRESHOLD" ]; then
        send_alert "WARNING" "High database connections: $db_connections (threshold: $CONNECTION_THRESHOLD)"
    fi

    if (( $(echo "$api_response_time_ms > $RESPONSE_TIME_THRESHOLD" | bc -l) )); then
        send_alert "WARNING" "Slow API response: ${api_response_time_ms}ms (threshold: ${RESPONSE_TIME_THRESHOLD}ms)"
    fi
}

send_alert() {
    local severity="$1"
    local message="$2"
    local alert_file="/tmp/prs-last-alert-$(echo "$message" | md5sum | cut -d' ' -f1)"
    local current_time=$(date +%s)

    # Rate limiting: don't send same alert within 1 hour
    if [ -f "$alert_file" ]; then
        local last_alert_time=$(cat "$alert_file")
        if [ $((current_time - last_alert_time)) -lt 3600 ]; then
            return 0
        fi
    fi

    echo "$current_time" > "$alert_file"

    log_message "ALERT [$severity] $message"

    # Send email alert
    if command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "PRS Monitoring Alert: $severity" "${ADMIN_EMAIL:-admin@prs.client-domain.com}"
    fi

    # Send to webhook if configured
    if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
        curl -X POST "$ALERT_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"severity\":\"$severity\",\"message\":\"$message\",\"timestamp\":\"$(date -Iseconds)\"}" \
            >/dev/null 2>&1 || true
    fi
}

main() {
    log_message "Starting performance monitoring cycle"

    # Create metrics directory if it doesn't exist
    mkdir -p "$(dirname "$METRICS_FILE")"

    # Collect metrics
    collect_system_metrics
    collect_application_metrics

    # Check for alerts
    check_alerts

    log_message "Performance monitoring cycle completed"
}

main "$@"
