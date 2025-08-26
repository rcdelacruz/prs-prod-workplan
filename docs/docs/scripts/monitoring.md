# Monitoring Scripts

## Overview

This guide covers all monitoring-related scripts in the PRS on-premises deployment, including system monitoring, performance tracking, alerting, and dashboard automation.

## Core Monitoring Scripts

### System Performance Monitor

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/system-performance-monitor.sh
# Comprehensive system performance monitoring

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
    local ssd_total=$(df -B1 /mnt/hdd | awk 'NR==2 {print $2}')
    local ssd_used=$(df -B1 /mnt/hdd | awk 'NR==2 {print $3}')
    local ssd_available=$(df -B1 /mnt/hdd | awk 'NR==2 {print $4}')
    local ssd_usage_percent=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')
    
    local hdd_total=$(df -B1 /mnt/hdd | awk 'NR==2 {print $2}')
    local hdd_used=$(df -B1 /mnt/hdd | awk 'NR==2 {print $3}')
    local hdd_available=$(df -B1 /mnt/hdd | awk 'NR==2 {print $4}')
    local hdd_usage_percent=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')
    
    # Network metrics
    local network_rx_bytes=$(cat /proc/net/dev | grep eth0 | awk '{print $2}')
    local network_tx_bytes=$(cat /proc/net/dev | grep eth0 | awk '{print $10}')
    
    # Write Prometheus metrics
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
    local db_connections=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "0")
    local db_size_bytes=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT pg_database_size('prs_production');" 2>/dev/null | xargs || echo "0")
    local cache_hit_ratio=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT round(100.0 * sum(blks_hit) / nullif(sum(blks_hit) + sum(blks_read), 0), 2) FROM pg_stat_database WHERE datname = 'prs_production';" 2>/dev/null | xargs || echo "0")
    
    # Redis metrics
    local redis_connected_clients=$(docker exec prs-onprem-redis redis-cli -a "$REDIS_PASSWORD" info clients 2>/dev/null | grep connected_clients | cut -d: -f2 | tr -d '\r' || echo "0")
    local redis_used_memory=$(docker exec prs-onprem-redis redis-cli -a "$REDIS_PASSWORD" info memory 2>/dev/null | grep used_memory: | cut -d: -f2 | tr -d '\r' || echo "0")
    
    # Application metrics
    local active_sessions=$(docker exec prs-onprem-redis redis-cli -a "$REDIS_PASSWORD" eval "return #redis.call('keys', 'session:*')" 0 2>/dev/null || echo "0")
    
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
    local ssd_usage=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')
    local hdd_usage=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')
    local db_connections=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "0")
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
        echo "$message" | mail -s "PRS Monitoring Alert: $severity" admin@your-domain.com
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
```

### Database Performance Monitor

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/database-performance-monitor.sh
# Database-specific performance monitoring

set -euo pipefail

LOG_FILE="/var/log/prs-db-monitoring.log"
METRICS_FILE="/var/lib/node_exporter/textfile_collector/prs-db-metrics.prom"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

collect_database_metrics() {
    log_message "Collecting database performance metrics"
    
    # Database connection and activity metrics
    local db_stats=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT 
        (SELECT count(*) FROM pg_stat_activity) as total_connections,
        (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') as active_connections,
        (SELECT count(*) FROM pg_stat_activity WHERE state = 'idle') as idle_connections,
        (SELECT round(100.0 * sum(blks_hit) / nullif(sum(blks_hit) + sum(blks_read), 0), 2) FROM pg_stat_database WHERE datname = 'prs_production') as cache_hit_ratio,
        (SELECT pg_database_size('prs_production')) as database_size,
        (SELECT sum(xact_commit + xact_rollback) FROM pg_stat_database WHERE datname = 'prs_production') as total_transactions;
    " | tr '|' ' ')
    
    read total_conn active_conn idle_conn cache_hit db_size total_txn <<< "$db_stats"
    
    # Query performance metrics
    local slow_queries=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT count(*) FROM pg_stat_statements WHERE mean_time > 1000 AND calls > 10;
    " | xargs)
    
    # Table statistics
    local table_stats=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT 
        sum(n_tup_ins) as total_inserts,
        sum(n_tup_upd) as total_updates,
        sum(n_tup_del) as total_deletes,
        sum(n_live_tup) as live_tuples,
        sum(n_dead_tup) as dead_tuples
    FROM pg_stat_user_tables;
    " | tr '|' ' ')
    
    read total_ins total_upd total_del live_tup dead_tup <<< "$table_stats"
    
    # TimescaleDB specific metrics
    local ts_stats=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT 
        count(*) as total_chunks,
        count(*) FILTER (WHERE is_compressed = true) as compressed_chunks,
        coalesce(round(avg((before_compression_total_bytes::numeric - after_compression_total_bytes::numeric) / before_compression_total_bytes::numeric * 100), 2), 0) as avg_compression_ratio
    FROM timescaledb_information.chunks c
    LEFT JOIN timescaledb_information.compressed_hypertable_stats s ON c.hypertable_name = s.hypertable_name;
    " | tr '|' ' ')
    
    read total_chunks compressed_chunks avg_compression <<< "$ts_stats"
    
    # Write metrics to Prometheus format
    cat > "$METRICS_FILE" << EOF
# HELP prs_db_connections Database connections
# TYPE prs_db_connections gauge
prs_db_connections{state="total"} ${total_conn:-0}
prs_db_connections{state="active"} ${active_conn:-0}
prs_db_connections{state="idle"} ${idle_conn:-0}

# HELP prs_db_cache_hit_ratio Database cache hit ratio percentage
# TYPE prs_db_cache_hit_ratio gauge
prs_db_cache_hit_ratio ${cache_hit:-0}

# HELP prs_db_size_bytes Database size in bytes
# TYPE prs_db_size_bytes gauge
prs_db_size_bytes ${db_size:-0}

# HELP prs_db_transactions_total Total database transactions
# TYPE prs_db_transactions_total counter
prs_db_transactions_total ${total_txn:-0}

# HELP prs_db_slow_queries Number of slow queries
# TYPE prs_db_slow_queries gauge
prs_db_slow_queries ${slow_queries:-0}

# HELP prs_db_table_operations_total Table operations
# TYPE prs_db_table_operations_total counter
prs_db_table_operations_total{operation="insert"} ${total_ins:-0}
prs_db_table_operations_total{operation="update"} ${total_upd:-0}
prs_db_table_operations_total{operation="delete"} ${total_del:-0}

# HELP prs_db_tuples Table tuples
# TYPE prs_db_tuples gauge
prs_db_tuples{state="live"} ${live_tup:-0}
prs_db_tuples{state="dead"} ${dead_tup:-0}

# HELP prs_timescaledb_chunks TimescaleDB chunks
# TYPE prs_timescaledb_chunks gauge
prs_timescaledb_chunks{state="total"} ${total_chunks:-0}
prs_timescaledb_chunks{state="compressed"} ${compressed_chunks:-0}

# HELP prs_timescaledb_compression_ratio Average compression ratio percentage
# TYPE prs_timescaledb_compression_ratio gauge
prs_timescaledb_compression_ratio ${avg_compression:-0}
EOF
    
    log_message "Database metrics collected: Connections=${total_conn:-0}, Cache_Hit=${cache_hit:-0}%, Slow_Queries=${slow_queries:-0}"
}

analyze_query_performance() {
    log_message "Analyzing query performance"
    
    # Get top slow queries
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
    SELECT 
        left(query, 80) as query_snippet,
        calls,
        round(mean_time::numeric, 2) as avg_time_ms,
        round(total_time::numeric, 2) as total_time_ms,
        round(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0), 2) as hit_percent
    FROM pg_stat_statements 
    WHERE calls > 100
    ORDER BY total_time DESC 
    LIMIT 10;
    " > /tmp/slow-queries-$(date +%Y%m%d_%H%M%S).log
    
    # Check for table bloat
    local bloated_tables=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT count(*) FROM pg_stat_user_tables 
    WHERE n_dead_tup > 1000 
    AND n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0) > 0.1;
    " | xargs)
    
    if [ "$bloated_tables" -gt 0 ]; then
        log_message "WARNING: $bloated_tables tables have significant bloat"
    fi
}

main() {
    log_message "Starting database performance monitoring"
    
    collect_database_metrics
    analyze_query_performance
    
    log_message "Database performance monitoring completed"
}

main "$@"
```

### Application Health Monitor

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/application-health-monitor.sh
# Application-specific health monitoring

set -euo pipefail

LOG_FILE="/var/log/prs-app-monitoring.log"
HEALTH_ENDPOINTS=(
    "https://localhost/api/health"
    "https://localhost/api/version"
    "https://localhost/"
)

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

check_application_health() {
    log_message "Checking application health endpoints"
    
    local all_healthy=true
    
    for endpoint in "${HEALTH_ENDPOINTS[@]}"; do
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" "$endpoint" 2>/dev/null || echo "000")
        local response_time=$(curl -w "%{time_total}" -o /dev/null -s "$endpoint" 2>/dev/null || echo "0")
        
        if [ "$response_code" = "200" ]; then
            log_message "✓ $endpoint - OK (${response_time}s)"
        else
            log_message "✗ $endpoint - FAILED (HTTP $response_code)"
            all_healthy=false
        fi
    done
    
    if [ "$all_healthy" = false ]; then
        send_health_alert "Application health check failed"
    fi
}

check_service_logs() {
    log_message "Checking service logs for errors"
    
    local services=("prs-onprem-backend" "prs-onprem-frontend" "prs-onprem-nginx")
    
    for service in "${services[@]}"; do
        local error_count=$(docker logs "$service" --since 1h 2>&1 | grep -i error | wc -l)
        local warning_count=$(docker logs "$service" --since 1h 2>&1 | grep -i warning | wc -l)
        
        log_message "$service: $error_count errors, $warning_count warnings (last hour)"
        
        if [ "$error_count" -gt 10 ]; then
            send_health_alert "High error count in $service: $error_count errors in last hour"
        fi
    done
}

monitor_user_activity() {
    log_message "Monitoring user activity"
    
    # Check active sessions
    local active_sessions=$(docker exec prs-onprem-redis redis-cli -a "$REDIS_PASSWORD" eval "return #redis.call('keys', 'session:*')" 0 2>/dev/null || echo "0")
    
    # Check recent user activity
    local recent_logins=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT count(*) FROM audit_logs 
    WHERE action = 'login' 
    AND created_at >= NOW() - INTERVAL '1 hour';
    " 2>/dev/null | xargs || echo "0")
    
    log_message "Active sessions: $active_sessions, Recent logins: $recent_logins"
    
    # Alert on unusual activity
    if [ "$active_sessions" -gt 200 ]; then
        send_health_alert "Unusually high session count: $active_sessions"
    fi
}

send_health_alert() {
    local message="$1"
    
    log_message "HEALTH ALERT: $message"
    
    if command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "PRS Application Health Alert" admin@your-domain.com
    fi
}

main() {
    log_message "Starting application health monitoring"
    
    check_application_health
    check_service_logs
    monitor_user_activity
    
    log_message "Application health monitoring completed"
}

main "$@"
```

## Monitoring Automation

### Monitoring Cron Setup

```bash
#!/bin/bash
# Setup monitoring automation

setup_monitoring_cron() {
    (crontab -l 2>/dev/null; cat << 'EOF'
# PRS Monitoring Schedule

# System performance monitoring every minute
* * * * * /opt/prs-deployment/scripts/system-performance-monitor.sh >/dev/null 2>&1

# Database performance monitoring every 5 minutes
*/5 * * * * /opt/prs-deployment/scripts/database-performance-monitor.sh >/dev/null 2>&1

# Application health monitoring every 2 minutes
*/2 * * * * /opt/prs-deployment/scripts/application-health-monitor.sh >/dev/null 2>&1

# Comprehensive health check every 5 minutes
*/5 * * * * /opt/prs-deployment/scripts/system-health-check.sh >/dev/null 2>&1

# Log analysis every 15 minutes
*/15 * * * * /opt/prs-deployment/scripts/log-analysis.sh >/dev/null 2>&1

# Generate monitoring report daily at 8:00 AM
0 8 * * * /opt/prs-deployment/scripts/generate-monitoring-report.sh
EOF
    ) | crontab -
    
    echo "Monitoring cron jobs configured successfully"
}

setup_monitoring_cron
```

### Monitoring Dashboard Script

```bash
#!/bin/bash
# Real-time monitoring dashboard

display_monitoring_dashboard() {
    while true; do
        clear
        echo "=============================================="
        echo "         PRS Real-time Monitoring Dashboard"
        echo "=============================================="
        echo "Last Updated: $(date)"
        echo ""
        
        # System Status
        echo "SYSTEM STATUS"
        echo "-------------"
        printf "CPU:    %3s%% " "$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d. -f1)"
        [ "$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d. -f1)" -gt 80 ] && echo "[HIGH]" || echo "[OK]"
        
        printf "Memory: %3s%% " "$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')"
        [ "$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')" -gt 85 ] && echo "[HIGH]" || echo "[OK]"
        
        printf "SSD:    %3s%% " "$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')"
        [ "$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')" -gt 90 ] && echo "[HIGH]" || echo "[OK]"
        
        printf "HDD:    %3s%% " "$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')"
        [ "$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')" -gt 85 ] && echo "[HIGH]" || echo "[OK]"
        
        echo ""
        
        # Service Status
        echo "SERVICE STATUS"
        echo "--------------"
        local services=("prs-onprem-nginx" "prs-onprem-frontend" "prs-onprem-backend" "prs-onprem-postgres-timescale" "prs-onprem-redis")
        
        for service in "${services[@]}"; do
            if docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
                printf "%-25s [RUNNING]\n" "$service"
            else
                printf "%-25s [STOPPED]\n" "$service"
            fi
        done
        
        echo ""
        
        # Application Metrics
        echo "APPLICATION METRICS"
        echo "-------------------"
        local active_sessions=$(docker exec prs-onprem-redis redis-cli -a "$REDIS_PASSWORD" eval "return #redis.call('keys', 'session:*')" 0 2>/dev/null || echo "N/A")
        local db_connections=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "N/A")
        local api_response=$(curl -w "%{time_total}" -o /dev/null -s https://localhost/api/health 2>/dev/null || echo "N/A")
        
        echo "Active Sessions: $active_sessions"
        echo "DB Connections:  $db_connections"
        echo "API Response:    ${api_response}s"
        
        echo ""
        echo "Press Ctrl+C to exit"
        sleep 5
    done
}

# Run dashboard
display_monitoring_dashboard
```

---

!!! success "Monitoring Scripts Ready"
    Your PRS deployment now has comprehensive monitoring scripts covering system performance, database health, application monitoring, and real-time dashboards.

!!! tip "Automation"
    Use the provided cron setup to automate monitoring tasks and ensure continuous system observation.

!!! warning "Alert Configuration"
    Configure email and webhook alerts properly to ensure you receive notifications about system issues promptly.
