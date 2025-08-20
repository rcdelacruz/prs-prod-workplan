#!/bin/bash

# PRS On-Premises Health Check Script
# Comprehensive system and application health monitoring
# Adapted from EC2 setup for on-premises infrastructure

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/prs-health-check.log"
ALERT_EMAIL="admin@client-domain.com"

# Thresholds
CPU_WARNING_THRESHOLD=70
CPU_CRITICAL_THRESHOLD=85
MEMORY_WARNING_THRESHOLD=75
MEMORY_CRITICAL_THRESHOLD=90
SSD_WARNING_THRESHOLD=80
SSD_CRITICAL_THRESHOLD=90
HDD_WARNING_THRESHOLD=70
HDD_CRITICAL_THRESHOLD=85

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Status counters
WARNINGS=0
ERRORS=0
CHECKS_PASSED=0
TOTAL_CHECKS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$LOG_FILE"
    ((CHECKS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"
    ((ERRORS++))
}

# Increment total checks counter
check_start() {
    ((TOTAL_CHECKS++))
}

# System health checks
check_system_resources() {
    log_info "Checking system resources..."
    
    # CPU Usage Check
    check_start
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    CPU_USAGE_INT=${CPU_USAGE%.*}
    
    if [ "$CPU_USAGE_INT" -gt "$CPU_CRITICAL_THRESHOLD" ]; then
        log_error "CPU usage critical: ${CPU_USAGE}%"
    elif [ "$CPU_USAGE_INT" -gt "$CPU_WARNING_THRESHOLD" ]; then
        log_warning "CPU usage high: ${CPU_USAGE}%"
    else
        log_success "CPU usage normal: ${CPU_USAGE}%"
    fi
    
    # Memory Usage Check
    check_start
    MEMORY_INFO=$(free | grep Mem)
    TOTAL_MEM=$(echo $MEMORY_INFO | awk '{print $2}')
    USED_MEM=$(echo $MEMORY_INFO | awk '{print $3}')
    MEMORY_USAGE=$((USED_MEM * 100 / TOTAL_MEM))
    
    if [ "$MEMORY_USAGE" -gt "$MEMORY_CRITICAL_THRESHOLD" ]; then
        log_error "Memory usage critical: ${MEMORY_USAGE}%"
    elif [ "$MEMORY_USAGE" -gt "$MEMORY_WARNING_THRESHOLD" ]; then
        log_warning "Memory usage high: ${MEMORY_USAGE}%"
    else
        log_success "Memory usage normal: ${MEMORY_USAGE}%"
    fi
    
    # Load Average Check
    check_start
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    LOAD_AVG_INT=${LOAD_AVG%.*}
    CPU_CORES=$(nproc)
    
    if [ "$LOAD_AVG_INT" -gt $((CPU_CORES * 2)) ]; then
        log_error "Load average high: $LOAD_AVG (cores: $CPU_CORES)"
    elif [ "$LOAD_AVG_INT" -gt "$CPU_CORES" ]; then
        log_warning "Load average elevated: $LOAD_AVG (cores: $CPU_CORES)"
    else
        log_success "Load average normal: $LOAD_AVG (cores: $CPU_CORES)"
    fi
}

# Storage health checks
check_storage() {
    log_info "Checking storage health..."
    
    # SSD Storage Check
    check_start
    if [ -d "/mnt/ssd" ]; then
        SSD_USAGE=$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')
        if [ "$SSD_USAGE" -gt "$SSD_CRITICAL_THRESHOLD" ]; then
            log_error "SSD usage critical: ${SSD_USAGE}%"
        elif [ "$SSD_USAGE" -gt "$SSD_WARNING_THRESHOLD" ]; then
            log_warning "SSD usage high: ${SSD_USAGE}%"
        else
            log_success "SSD usage normal: ${SSD_USAGE}%"
        fi
    else
        log_error "SSD mount point not found"
    fi
    
    # HDD Storage Check
    check_start
    if [ -d "/mnt/hdd" ]; then
        HDD_USAGE=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')
        if [ "$HDD_USAGE" -gt "$HDD_CRITICAL_THRESHOLD" ]; then
            log_error "HDD usage critical: ${HDD_USAGE}%"
        elif [ "$HDD_USAGE" -gt "$HDD_WARNING_THRESHOLD" ]; then
            log_warning "HDD usage high: ${HDD_USAGE}%"
        else
            log_success "HDD usage normal: ${HDD_USAGE}%"
        fi
    else
        log_error "HDD mount point not found"
    fi
    
    # Check disk I/O
    check_start
    if command -v iostat >/dev/null 2>&1; then
        IO_WAIT=$(iostat -c 1 2 | tail -1 | awk '{print $4}')
        IO_WAIT_INT=${IO_WAIT%.*}
        if [ "$IO_WAIT_INT" -gt 20 ]; then
            log_warning "High I/O wait: ${IO_WAIT}%"
        else
            log_success "I/O wait normal: ${IO_WAIT}%"
        fi
    else
        log_warning "iostat not available, skipping I/O check"
    fi
}

# Docker health checks
check_docker() {
    log_info "Checking Docker services..."
    
    # Docker daemon check
    check_start
    if docker info >/dev/null 2>&1; then
        log_success "Docker daemon running"
    else
        log_error "Docker daemon not running"
        return 1
    fi
    
    # Container health checks
    CONTAINERS=("prs-onprem-nginx" "prs-onprem-backend" "prs-onprem-frontend" "prs-onprem-postgres-timescale" "prs-onprem-redis")
    
    for container in "${CONTAINERS[@]}"; do
        check_start
        if docker ps | grep -q "$container"; then
            # Check container health status
            HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-health-check")
            if [ "$HEALTH_STATUS" = "healthy" ] || [ "$HEALTH_STATUS" = "no-health-check" ]; then
                log_success "Container $container running"
            else
                log_warning "Container $container unhealthy: $HEALTH_STATUS"
            fi
        else
            log_error "Container $container not running"
        fi
    done
}

# Application health checks
check_application() {
    log_info "Checking application health..."
    
    # Backend API health check
    check_start
    if curl -f -s http://localhost:4000/health >/dev/null 2>&1; then
        log_success "Backend API responding"
    else
        log_error "Backend API not responding"
    fi
    
    # Frontend health check
    check_start
    if curl -f -s http://192.168.16.100/ >/dev/null 2>&1; then
        log_success "Frontend responding"
    else
        log_error "Frontend not responding"
    fi
    
    # HTTPS health check
    check_start
    if curl -f -s -k https://192.168.16.100/ >/dev/null 2>&1; then
        log_success "HTTPS responding"
    else
        log_error "HTTPS not responding"
    fi
    
    # Database connectivity check
    check_start
    if docker exec prs-onprem-postgres-timescale pg_isready -U prs_user >/dev/null 2>&1; then
        log_success "Database responding"
    else
        log_error "Database not responding"
    fi
    
    # Redis connectivity check
    check_start
    if docker exec prs-onprem-redis redis-cli ping >/dev/null 2>&1; then
        log_success "Redis responding"
    else
        log_error "Redis not responding"
    fi
}

# Network health checks
check_network() {
    log_info "Checking network connectivity..."
    
    # Internal network connectivity
    check_start
    if ping -c 1 192.168.1.1 >/dev/null 2>&1; then
        log_success "Internal network connectivity"
    else
        log_warning "Internal network connectivity issues"
    fi
    
    # External network connectivity
    check_start
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_success "External network connectivity"
    else
        log_warning "External network connectivity issues"
    fi
    
    # DNS resolution check
    check_start
    if nslookup google.com >/dev/null 2>&1; then
        log_success "DNS resolution working"
    else
        log_warning "DNS resolution issues"
    fi
    
    # Port accessibility check
    check_start
    PORTS=(80 443 8080 3001 9000 9090)
    PORTS_OK=0
    for port in "${PORTS[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            ((PORTS_OK++))
        fi
    done
    
    if [ "$PORTS_OK" -eq "${#PORTS[@]}" ]; then
        log_success "All required ports accessible"
    else
        log_warning "Some ports not accessible ($PORTS_OK/${#PORTS[@]})"
    fi
}

# Security checks
check_security() {
    log_info "Checking security status..."
    
    # Firewall status check
    check_start
    if ufw status | grep -q "Status: active"; then
        log_success "Firewall active"
    else
        log_warning "Firewall not active"
    fi
    
    # SSL certificate check
    check_start
    if [ -f "/opt/prs/ssl/server.crt" ]; then
        CERT_EXPIRY=$(openssl x509 -in /opt/prs/ssl/server.crt -noout -enddate | cut -d= -f2)
        CERT_EXPIRY_EPOCH=$(date -d "$CERT_EXPIRY" +%s)
        CURRENT_EPOCH=$(date +%s)
        DAYS_UNTIL_EXPIRY=$(( (CERT_EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
        
        if [ "$DAYS_UNTIL_EXPIRY" -lt 7 ]; then
            log_error "SSL certificate expires in $DAYS_UNTIL_EXPIRY days"
        elif [ "$DAYS_UNTIL_EXPIRY" -lt 30 ]; then
            log_warning "SSL certificate expires in $DAYS_UNTIL_EXPIRY days"
        else
            log_success "SSL certificate valid ($DAYS_UNTIL_EXPIRY days remaining)"
        fi
    else
        log_error "SSL certificate not found"
    fi
    
    # Check for failed login attempts
    check_start
    FAILED_LOGINS=$(grep "Failed password" /var/log/auth.log 2>/dev/null | grep "$(date '+%b %d')" | wc -l || echo 0)
    if [ "$FAILED_LOGINS" -gt 10 ]; then
        log_warning "High number of failed login attempts today: $FAILED_LOGINS"
    else
        log_success "Failed login attempts normal: $FAILED_LOGINS"
    fi
}

# Backup status check
check_backups() {
    log_info "Checking backup status..."
    
    # Check last daily backup
    check_start
    if [ -d "/mnt/ssd/backups/daily" ]; then
        LATEST_BACKUP=$(ls -t /mnt/ssd/backups/daily/ | head -1)
        if [ -n "$LATEST_BACKUP" ]; then
            BACKUP_AGE=$(find "/mnt/ssd/backups/daily/$LATEST_BACKUP" -mtime +1 | wc -l)
            if [ "$BACKUP_AGE" -gt 0 ]; then
                log_warning "Daily backup is older than 24 hours"
            else
                log_success "Daily backup is current"
            fi
        else
            log_error "No daily backup found"
        fi
    else
        log_error "Daily backup directory not found"
    fi
    
    # Check backup storage usage
    check_start
    if [ -d "/mnt/hdd/backups" ]; then
        BACKUP_SIZE=$(du -sh /mnt/hdd/backups | cut -f1)
        log_success "Backup storage usage: $BACKUP_SIZE"
    else
        log_warning "Backup storage directory not found"
    fi
}

# Generate health report
generate_report() {
    log_info "Generating health check report..."
    
    REPORT_FILE="/var/log/prs-health-report-$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$REPORT_FILE" << EOF
PRS On-Premises Health Check Report
==================================
Date: $(date)
Server: $(hostname)

Summary:
========
Total Checks: $TOTAL_CHECKS
Passed: $CHECKS_PASSED
Warnings: $WARNINGS
Errors: $ERRORS

Overall Status: $([ $ERRORS -eq 0 ] && echo "HEALTHY" || echo "ISSUES DETECTED")

System Information:
==================
Uptime: $(uptime)
CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
Memory Usage: $(free -h | grep Mem | awk '{print $3"/"$2}')
Load Average: $(uptime | awk -F'load average:' '{print $2}')

Storage Usage:
==============
SSD: $(df -h /mnt/ssd 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A")
HDD: $(df -h /mnt/hdd 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A")

Docker Containers:
==================
$(docker ps --format "table {{.Names}}\t{{.Status}}")

Network Status:
===============
$(ip addr show | grep "inet " | grep -v "127.0.0.1")

Recommendations:
================
EOF

    if [ $ERRORS -gt 0 ]; then
        echo "- CRITICAL: $ERRORS error(s) detected. Immediate attention required." >> "$REPORT_FILE"
    fi
    
    if [ $WARNINGS -gt 0 ]; then
        echo "- WARNING: $WARNINGS warning(s) detected. Monitor closely." >> "$REPORT_FILE"
    fi
    
    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo "- All systems operating normally." >> "$REPORT_FILE"
    fi
    
    log_success "Health report generated: $REPORT_FILE"
}

# Send alerts if needed
send_alerts() {
    if [ $ERRORS -gt 0 ]; then
        log_info "Sending critical alert..."
        # Uncomment to enable email alerts
        # echo "CRITICAL: PRS system has $ERRORS error(s). Check $LOG_FILE for details." | mail -s "PRS Critical Alert" "$ALERT_EMAIL"
    elif [ $WARNINGS -gt 5 ]; then
        log_info "Sending warning alert..."
        # Uncomment to enable email alerts
        # echo "WARNING: PRS system has $WARNINGS warning(s). Check $LOG_FILE for details." | mail -s "PRS Warning Alert" "$ALERT_EMAIL"
    fi
}

# Main execution
main() {
    echo "========================================" | tee -a "$LOG_FILE"
    log_info "Starting PRS On-Premises Health Check - $(date)"
    echo "========================================" | tee -a "$LOG_FILE"
    
    check_system_resources
    check_storage
    check_docker
    check_application
    check_network
    check_security
    check_backups
    
    echo "========================================" | tee -a "$LOG_FILE"
    generate_report
    send_alerts
    
    # Exit with appropriate code
    if [ $ERRORS -gt 0 ]; then
        log_error "Health check completed with $ERRORS error(s) and $WARNINGS warning(s)"
        exit 1
    elif [ $WARNINGS -gt 0 ]; then
        log_warning "Health check completed with $WARNINGS warning(s)"
        exit 0
    else
        log_success "Health check completed successfully - all systems healthy"
        exit 0
    fi
}

# Execute main function
main "$@"
