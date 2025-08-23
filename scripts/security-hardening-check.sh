#!/bin/bash
# /opt/prs-deployment/scripts/security-hardening-check.sh
# Security validation and hardening check for PRS on-premises deployment

set -euo pipefail

LOG_FILE="/var/log/prs-security-check.log"
REPORT_FILE="/tmp/prs-security-report-$(date +%Y%m%d_%H%M%S).txt"

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

output() {
    echo "$1" | tee -a "$REPORT_FILE"
}

check_system_security() {
    output "=== System Security Check ==="

    # Check SSH configuration
    output "SSH Security:"
    if [ -f "/etc/ssh/sshd_config" ]; then
        local root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}' || echo "not_set")
        local password_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config | awk '{print $2}' || echo "not_set")
        local port=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}' || echo "22")

        output "  SSH Port: $port"
        output "  Root Login: $root_login"
        output "  Password Auth: $password_auth"

        if [ "$root_login" = "no" ]; then
            output "  ✅ Root login disabled"
        else
            output "  ⚠️  Root login enabled - security risk"
        fi

        if [ "$password_auth" = "no" ]; then
            output "  ✅ Password authentication disabled"
        else
            output "  ⚠️  Password authentication enabled - consider key-only auth"
        fi
    fi

    # Check firewall status
    output ""
    output "Firewall Status:"
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=$(ufw status | head -1)
        output "  UFW: $ufw_status"

        if echo "$ufw_status" | grep -q "active"; then
            output "  ✅ UFW firewall is active"
        else
            output "  ⚠️  UFW firewall is inactive"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        local iptables_rules=$(iptables -L | wc -l)
        output "  iptables rules: $iptables_rules"
    else
        output "  ⚠️  No firewall detected"
    fi

    # Check fail2ban
    output ""
    output "Intrusion Prevention:"
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        output "  ✅ fail2ban is active"
        local banned_ips=$(fail2ban-client status sshd 2>/dev/null | grep "Banned IP list" | wc -w || echo "0")
        output "  Currently banned IPs: $banned_ips"
    else
        output "  ⚠️  fail2ban not active - consider installing"
    fi

    output ""
}

check_docker_security() {
    output "=== Docker Security Check ==="

    # Check Docker daemon security
    output "Docker Configuration:"

    # Check if Docker is running as root
    local docker_user=$(ps aux | grep dockerd | grep -v grep | awk '{print $1}' | head -1)
    output "  Docker daemon user: $docker_user"

    # Check Docker socket permissions
    if [ -S "/var/run/docker.sock" ]; then
        local socket_perms=$(ls -la /var/run/docker.sock | awk '{print $1}')
        output "  Docker socket permissions: $socket_perms"

        if echo "$socket_perms" | grep -q "rw-rw----"; then
            output "  ✅ Docker socket has restricted permissions"
        else
            output "  ⚠️  Docker socket permissions may be too permissive"
        fi
    fi

    # Check container security
    output ""
    output "Container Security:"

    local privileged_containers=$(docker ps --format "{{.Names}}" --filter "label=privileged=true" | wc -l)
    output "  Privileged containers: $privileged_containers"

    if [ "$privileged_containers" -eq 0 ]; then
        output "  ✅ No privileged containers running"
    else
        output "  ⚠️  Privileged containers detected - review necessity"
    fi

    # Check for containers running as root
    output ""
    output "Container User Security:"
    local services=("prs-onprem-nginx" "prs-onprem-frontend" "prs-onprem-backend" "prs-onprem-postgres-timescale" "prs-onprem-redis")

    for service in "${services[@]}"; do
        if docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
            local container_user=$(docker exec "$service" whoami 2>/dev/null || echo "unknown")
            output "  $service user: $container_user"
        fi
    done

    output ""
}

check_application_security() {
    output "=== Application Security Check ==="

    # Check SSL/TLS configuration
    output "SSL/TLS Configuration:"
    if [ -f "$PROJECT_DIR/02-docker-configuration/ssl/certificate.crt" ]; then
        local cert_expiry=$(openssl x509 -in "$PROJECT_DIR/02-docker-configuration/ssl/certificate.crt" -noout -enddate | cut -d= -f2)
        local expiry_epoch=$(date -d "$cert_expiry" +%s)
        local current_epoch=$(date +%s)
        local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))

        output "  SSL Certificate expires in: $days_until_expiry days"

        if [ "$days_until_expiry" -gt 30 ]; then
            output "  ✅ SSL certificate is valid"
        elif [ "$days_until_expiry" -gt 7 ]; then
            output "  ⚠️  SSL certificate expires soon"
        else
            output "  🚨 SSL certificate expires very soon!"
        fi

        # Check certificate strength
        local key_size=$(openssl x509 -in "$PROJECT_DIR/02-docker-configuration/ssl/certificate.crt" -noout -text | grep "Public-Key:" | awk '{print $2}' | sed 's/[()]//g')
        output "  Certificate key size: $key_size"

        if [ "${key_size:-0}" -ge 2048 ]; then
            output "  ✅ Certificate key size is adequate"
        else
            output "  ⚠️  Certificate key size may be weak"
        fi
    else
        output "  ⚠️  No SSL certificate found"
    fi

    # Check database security
    output ""
    output "Database Security:"

    # Check if database is accessible externally
    local db_external_port=$(docker port prs-onprem-postgres-timescale 5432 2>/dev/null | grep "0.0.0.0" || echo "")
    if [ -z "$db_external_port" ]; then
        output "  ✅ Database not exposed externally"
    else
        output "  ⚠️  Database exposed externally: $db_external_port"
    fi

    # Check Redis security
    local redis_external_port=$(docker port prs-onprem-redis 6379 2>/dev/null | grep "0.0.0.0" || echo "")
    if [ -z "$redis_external_port" ]; then
        output "  ✅ Redis not exposed externally"
    else
        output "  ⚠️  Redis exposed externally: $redis_external_port"
    fi

    output ""
}

check_file_permissions() {
    output "=== File Permissions Check ==="

    # Check sensitive file permissions
    output "Sensitive Files:"

    local sensitive_files=(
        "$PROJECT_DIR/02-docker-configuration/.env"
        "$PROJECT_DIR/02-docker-configuration/ssl/private.key"
        "/etc/ssh/ssh_host_rsa_key"
    )

    for file in "${sensitive_files[@]}"; do
        if [ -f "$file" ]; then
            local perms=$(ls -la "$file" | awk '{print $1}')
            local owner=$(ls -la "$file" | awk '{print $3}')
            output "  $file: $perms ($owner)"

            if echo "$perms" | grep -q "rw-------"; then
                output "    ✅ Secure permissions"
            elif echo "$perms" | grep -q "rw-r-----"; then
                output "    ⚠️  Group readable - consider restricting"
            else
                output "    🚨 Insecure permissions detected!"
            fi
        fi
    done

    output ""
}

generate_security_recommendations() {
    output "=== Security Recommendations ==="

    # Check for common security issues and provide recommendations
    output "Recommendations:"

    # SSH hardening
    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
        output "  🔧 Disable root SSH login: PermitRootLogin no"
    fi

    if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
        output "  🔧 Consider disabling password authentication: PasswordAuthentication no"
    fi

    # Firewall recommendations
    if ! command -v ufw >/dev/null 2>&1; then
        output "  🔧 Install and configure UFW firewall"
    fi

    # fail2ban recommendations
    if ! systemctl is-active --quiet fail2ban 2>/dev/null; then
        output "  🔧 Install fail2ban for intrusion prevention"
    fi

    # Docker security
    if docker ps --format "{{.Names}}" --filter "label=privileged=true" | grep -q .; then
        output "  🔧 Review privileged containers - minimize usage"
    fi

    # SSL recommendations
    if [ ! -f "$PROJECT_DIR/02-docker-configuration/ssl/certificate.crt" ]; then
        output "  🔧 Configure SSL/TLS certificates for HTTPS"
    fi

    # Backup security
    if [ ! -d "/mnt/hdd/postgres-backups" ]; then
        output "  🔧 Ensure backup encryption is configured"
    fi

    output ""
    output "Security check completed. Report saved to: $REPORT_FILE"
}

main() {
    log_message "Starting security hardening check"

    output "PRS Security Hardening Check Report"
    output "Generated: $(date)"
    output "Hostname: $(hostname)"
    output ""

    check_system_security
    check_docker_security
    check_application_security
    check_file_permissions
    generate_security_recommendations

    log_message "Security check completed. Report: $REPORT_FILE"

    # Email report if configured
    if command -v mail >/dev/null 2>&1; then
        mail -s "PRS Security Check Report" "${ADMIN_EMAIL:-admin@prs.client-domain.com}" < "$REPORT_FILE"
    fi
}

main "$@"
