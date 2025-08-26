#!/bin/bash
# /opt/prs-deployment/scripts/performance-test.sh
# Performance testing for PRS on-premises deployment

set -euo pipefail

LOG_FILE="/var/log/prs-performance-test.log"
RESULTS_DIR="/tmp/prs-performance-results"

# Test configuration
CONCURRENT_USERS=10
TEST_DURATION=300  # 5 minutes
API_BASE_URL="https://localhost"

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

setup_test_environment() {
    log_message "Setting up performance test environment"

    mkdir -p "$RESULTS_DIR"

    # Check if required tools are available
    if ! command -v curl >/dev/null 2>&1; then
        log_message "ERROR: curl is required for performance testing"
        exit 1
    fi

    if ! command -v ab >/dev/null 2>&1; then
        log_message "Installing Apache Bench (ab) for load testing"
        apt-get update && apt-get install -y apache2-utils
    fi

    # Verify application is running
    if ! curl -s -k "$API_BASE_URL/api/health" >/dev/null; then
        log_message "ERROR: Application is not responding"
        exit 1
    fi

    log_message "Test environment ready"
}

test_api_endpoints() {
    log_message "Testing API endpoint performance"

    local endpoints=(
        "/api/health"
        "/api/version"
        "/api/auth/me"
        "/api/requisitions"
        "/api/departments"
    )

    for endpoint in "${endpoints[@]}"; do
        log_message "Testing endpoint: $endpoint"

        # Single request test
        local response_time=$(curl -w "%{time_total}" -o /dev/null -s -k "$API_BASE_URL$endpoint" 2>/dev/null || echo "0")
        local status_code=$(curl -w "%{http_code}" -o /dev/null -s -k "$API_BASE_URL$endpoint" 2>/dev/null || echo "000")

        log_message "  Single request: ${response_time}s (HTTP $status_code)"

        # Load test with Apache Bench
        if [ "$status_code" = "200" ] || [ "$status_code" = "401" ]; then  # 401 is expected for auth endpoints
            local ab_result_file="$RESULTS_DIR/ab-$(echo "$endpoint" | tr '/' '_').txt"
            ab -n 100 -c 10 -k -s 30 "$API_BASE_URL$endpoint" > "$ab_result_file" 2>&1 || true

            if [ -f "$ab_result_file" ]; then
                local avg_time=$(grep "Time per request:" "$ab_result_file" | head -1 | awk '{print $4}')
                local requests_per_sec=$(grep "Requests per second:" "$ab_result_file" | awk '{print $4}')
                log_message "  Load test: ${avg_time}ms avg, ${requests_per_sec} req/sec"
            fi
        fi
    done
}

test_database_performance() {
    log_message "Testing database performance"

    # Test database connection time
    local db_connect_time=$(time (docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "SELECT 1;" >/dev/null) 2>&1 | grep real | awk '{print $2}')
    log_message "Database connection time: $db_connect_time"

    # Test simple queries
    local queries=(
        "SELECT COUNT(*) FROM users;"
        "SELECT COUNT(*) FROM requisitions WHERE created_at >= NOW() - INTERVAL '30 days';"
        "SELECT COUNT(*) FROM audit_logs WHERE created_at >= NOW() - INTERVAL '7 days';"
    )

    for query in "${queries[@]}"; do
        log_message "Testing query: $query"

        local query_time=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "\timing on" -c "$query" 2>&1 | grep "Time:" | awk '{print $2}' || echo "N/A")
        log_message "  Query time: $query_time"
    done

    # Test TimescaleDB specific queries
    log_message "Testing TimescaleDB compression performance"
    local compression_query="SELECT hypertable_name, compression_status FROM timescaledb_information.hypertables;"
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "$compression_query" > "$RESULTS_DIR/timescaledb-status.txt"
}

test_system_performance() {
    log_message "Testing system performance"

    # CPU stress test
    log_message "Running CPU stress test (30 seconds)"
    local cpu_cores=$(nproc)
    timeout 30s stress --cpu "$cpu_cores" >/dev/null 2>&1 || true

    local cpu_usage_after=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    log_message "CPU usage after stress test: ${cpu_usage_after}%"

    # Memory test
    log_message "Testing memory performance"
    local memory_total=$(free -m | grep Mem | awk '{print $2}')
    local memory_used=$(free -m | grep Mem | awk '{print $3}')
    local memory_usage_percent=$(echo "scale=2; $memory_used * 100 / $memory_total" | bc)
    log_message "Memory usage: ${memory_usage_percent}% (${memory_used}MB/${memory_total}MB)"

    # Disk I/O test
    log_message "Testing disk I/O performance"

    # Test SSD performance
    local ssd_write_speed=$(dd if=/dev/zero of=${STORAGE_HDD_PATH:-/mnt/hdd}/test_write bs=1M count=100 2>&1 | grep copied | awk '{print $(NF-1) " " $NF}')
    rm -f ${STORAGE_HDD_PATH:-/mnt/hdd}/test_write
    log_message "SSD write speed: $ssd_write_speed"

    # Test HDD performance
    local hdd_write_speed=$(dd if=/dev/zero of=/mnt/hdd/test_write bs=1M count=100 2>&1 | grep copied | awk '{print $(NF-1) " " $NF}')
    rm -f /mnt/hdd/test_write
    log_message "HDD write speed: $hdd_write_speed"
}

generate_performance_report() {
    log_message "Generating performance test report"

    local report_file="$RESULTS_DIR/performance-report-$(date +%Y%m%d_%H%M%S).txt"

    cat > "$report_file" << EOF
PRS Performance Test Report
===========================
Generated: $(date)
Test Duration: $TEST_DURATION seconds
Concurrent Users: $CONCURRENT_USERS

SYSTEM SPECIFICATIONS
---------------------
CPU Cores: $(nproc)
Total Memory: $(free -h | grep Mem | awk '{print $2}')
SSD Mount: $(df -h ${STORAGE_HDD_PATH:-/mnt/hdd} | awk 'NR==2 {print $2 " (" $5 " used)"}')
HDD Mount: $(df -h /mnt/hdd | awk 'NR==2 {print $2 " (" $5 " used)"}')

APPLICATION STATUS
------------------
$(curl -s -k "$API_BASE_URL/api/health" | head -5 || echo "API not responding")

DATABASE STATUS
---------------
$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "SELECT version();" | head -3 || echo "Database not responding")

PERFORMANCE SUMMARY
-------------------
EOF

    # Add API endpoint summary
    echo "API Endpoints:" >> "$report_file"
    if [ -f "$RESULTS_DIR/ab-_api_health.txt" ]; then
        local health_rps=$(grep "Requests per second:" "$RESULTS_DIR/ab-_api_health.txt" | awk '{print $4}')
        echo "  Health endpoint: ${health_rps} req/sec" >> "$report_file"
    fi

    # Add system performance summary
    echo "" >> "$report_file"
    echo "System Performance:" >> "$report_file"
    echo "  CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')%" >> "$report_file"
    echo "  Memory Usage: $(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')%" >> "$report_file"
    echo "  Load Average: $(uptime | awk -F'load average:' '{print $2}')" >> "$report_file"

    # Add recommendations
    cat >> "$report_file" << EOF

RECOMMENDATIONS
---------------
EOF

    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d. -f1)
    local memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')

    if [ "$cpu_usage" -gt 80 ]; then
        echo "- High CPU usage detected ($cpu_usage%) - consider CPU optimization" >> "$report_file"
    fi

    if [ "$memory_usage" -gt 80 ]; then
        echo "- High memory usage detected ($memory_usage%) - monitor for memory leaks" >> "$report_file"
    fi

    if [ -f "$RESULTS_DIR/ab-_api_health.txt" ]; then
        local health_rps=$(grep "Requests per second:" "$RESULTS_DIR/ab-_api_health.txt" | awk '{print $4}' | cut -d. -f1)
        if [ "$health_rps" -lt 100 ]; then
            echo "- Low API performance ($health_rps req/sec) - investigate bottlenecks" >> "$report_file"
        fi
    fi

    echo "" >> "$report_file"
    echo "Detailed results available in: $RESULTS_DIR" >> "$report_file"

    log_message "Performance report generated: $report_file"
}

main() {
    log_message "Starting performance testing"

    setup_test_environment
    test_api_endpoints
    test_database_performance
    test_system_performance
    generate_performance_report

    log_message "Performance testing completed"
    log_message "Results available in: $RESULTS_DIR"
}

main "$@"
