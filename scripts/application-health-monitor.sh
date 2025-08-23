#!/bin/bash
# /opt/prs-deployment/scripts/application-health-monitor.sh
# Application-specific health monitoring for PRS on-premises deployment

set -euo pipefail

LOG_FILE="/var/log/prs-app-monitoring.log"
HEALTH_ENDPOINTS=(
    "https://localhost/api/health"
    "https://localhost/api/version"
    "https://localhost/"
)

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
    local active_sessions=$(docker exec prs-onprem-redis redis-cli -a "${REDIS_PASSWORD:-}" eval "return #redis.call('keys', 'session:*')" 0 2>/dev/null || echo "0")

    # Check recent user activity
    local recent_logins=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "
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
        echo "$message" | mail -s "PRS Application Health Alert" "${ADMIN_EMAIL:-admin@prs.client-domain.com}"
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
