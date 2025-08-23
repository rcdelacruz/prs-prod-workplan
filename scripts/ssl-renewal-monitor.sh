#!/bin/bash

# 📅 SSL Certificate Renewal Monitor for prs.citylandcondo.com
# Monitors certificate expiry and sends alerts when renewal is needed

set -e

# Configuration
DOMAIN="prs.citylandcondo.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SSL_DIR="$PROJECT_DIR/02-docker-configuration/ssl"
LOG_FILE="/var/log/prs-ssl-monitor.log"
ALERT_EMAIL="admin@citylandcondo.com"
GRAFANA_WEBHOOK="http://192.168.0.100:3000/api/alerts/webhook"

# Alert thresholds (in days)
WARNING_THRESHOLD=30
CRITICAL_THRESHOLD=7

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Print colored output
print_status() {
    echo -e "${BLUE}📊 $1${NC}"
    log "$1"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
    log "WARNING: $1"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    log "ERROR: $1"
}

print_critical() {
    echo -e "${RED}🚨 $1${NC}"
    log "CRITICAL: $1"
}

# Function to check certificate status
check_certificate_status() {
    local cert_file="$SSL_DIR/server.crt"

    if [ ! -f "$cert_file" ]; then
        print_error "Certificate file not found: $cert_file"
        return 1
    fi

    # Get certificate information
    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))

    # Get certificate subject
    local subject=$(openssl x509 -subject -noout -in "$cert_file" | sed 's/subject=//')

    # Get certificate issuer
    local issuer=$(openssl x509 -issuer -noout -in "$cert_file" | sed 's/issuer=//')

    print_status "SSL Certificate Status for $DOMAIN"
    echo "Certificate: $cert_file"
    echo "Subject: $subject"
    echo "Issuer: $issuer"
    echo "Expires: $expiry_date"
    echo "Days until expiry: $days_until_expiry"
    echo ""

    # Return status based on days until expiry
    if [ $days_until_expiry -lt 0 ]; then
        print_critical "Certificate has EXPIRED!"
        return 3
    elif [ $days_until_expiry -le $CRITICAL_THRESHOLD ]; then
        print_critical "Certificate expires in $days_until_expiry days (CRITICAL)"
        return 2
    elif [ $days_until_expiry -le $WARNING_THRESHOLD ]; then
        print_warning "Certificate expires in $days_until_expiry days (WARNING)"
        return 1
    else
        print_success "Certificate is valid for $days_until_expiry more days"
        return 0
    fi
}

# Function to send email alert
send_email_alert() {
    local status="$1"
    local days="$2"
    local subject=""
    local body=""

    case $status in
        "expired")
            subject="🚨 CRITICAL: SSL Certificate EXPIRED - $DOMAIN"
            body="The SSL certificate for $DOMAIN has EXPIRED. Immediate action required!"
            ;;
        "critical")
            subject="🚨 CRITICAL: SSL Certificate expires in $days days - $DOMAIN"
            body="The SSL certificate for $DOMAIN expires in $days days. Immediate renewal required!"
            ;;
        "warning")
            subject="⚠️ WARNING: SSL Certificate expires in $days days - $DOMAIN"
            body="The SSL certificate for $DOMAIN expires in $days days. Please schedule renewal soon."
            ;;
    esac

    # Create email body
    cat > /tmp/ssl_alert_email.txt << EOF
$body

Domain: $DOMAIN
Server: 192.168.0.100
Certificate Location: $SSL_DIR/server.crt

To renew the certificate, run:
sudo /opt/prs/scripts/ssl-automation-citylandcondo.sh renew

For assistance, contact the IT team.

---
PRS SSL Monitoring System
$(date)
EOF

    # Send email if mail command is available
    if command -v mail &> /dev/null; then
        mail -s "$subject" "$ALERT_EMAIL" < /tmp/ssl_alert_email.txt
        print_success "Email alert sent to $ALERT_EMAIL"
    else
        print_warning "Mail command not available, email alert not sent"
    fi

    # Clean up
    rm -f /tmp/ssl_alert_email.txt
}

# Function to send Grafana webhook alert
send_grafana_alert() {
    local status="$1"
    local days="$2"
    local severity=""
    local message=""

    case $status in
        "expired")
            severity="critical"
            message="SSL certificate for $DOMAIN has EXPIRED"
            ;;
        "critical")
            severity="critical"
            message="SSL certificate for $DOMAIN expires in $days days"
            ;;
        "warning")
            severity="warning"
            message="SSL certificate for $DOMAIN expires in $days days"
            ;;
    esac

    # Create JSON payload
    local json_payload=$(cat << EOF
{
    "alert": "ssl_certificate_expiry",
    "domain": "$DOMAIN",
    "severity": "$severity",
    "message": "$message",
    "days_until_expiry": $days,
    "timestamp": "$(date -Iseconds)",
    "server": "192.168.0.100"
}
EOF
)

    # Send webhook if curl is available
    if command -v curl &> /dev/null; then
        if curl -s -X POST "$GRAFANA_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "$json_payload" > /dev/null; then
            print_success "Grafana alert sent"
        else
            print_warning "Failed to send Grafana alert"
        fi
    else
        print_warning "Curl not available, Grafana alert not sent"
    fi
}

# Function to create renewal reminder
create_renewal_reminder() {
    local days="$1"

    cat > /tmp/ssl_renewal_instructions.txt << EOF
🔐 SSL Certificate Renewal Instructions for $DOMAIN

The certificate expires in $days days. Follow these steps to renew:

1. Prepare for renewal:
   - Ensure you have router/firewall admin access
   - Schedule a brief maintenance window (5-10 minutes)
   - Notify users of potential brief downtime

2. Run the renewal script:
   sudo /opt/prs/scripts/ssl-automation-citylandcondo.sh renew

3. The script will guide you through:
   - Enabling port 80 forwarding temporarily
   - Generating new certificate
   - Disabling port 80 forwarding
   - Validating the new certificate

4. Verify renewal:
   sudo /opt/prs/scripts/ssl-renewal-monitor.sh check

For questions or assistance, contact the IT team.

---
Generated: $(date)
EOF

    print_status "Renewal instructions created at /tmp/ssl_renewal_instructions.txt"
    cat /tmp/ssl_renewal_instructions.txt
}

# Function to check HTTPS connectivity
test_connectivity() {
    print_status "Testing HTTPS connectivity..."

    # Test internal connectivity
    if curl -k -s --connect-timeout 10 "https://192.168.0.100/health" | grep -q "healthy"; then
        print_success "Internal HTTPS (IP) connectivity: OK"
    else
        print_warning "Internal HTTPS (IP) connectivity: FAILED"
    fi

    # Test domain connectivity
    if curl -s --connect-timeout 10 "https://$DOMAIN/health" | grep -q "healthy"; then
        print_success "Domain HTTPS connectivity: OK"
    else
        print_warning "Domain HTTPS connectivity: FAILED (may be normal if not publicly accessible)"
    fi
}

# Function to generate monitoring report
generate_report() {
    local report_file="/tmp/ssl_monitoring_report_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "🔐 SSL Certificate Monitoring Report"
        echo "===================================="
        echo "Generated: $(date)"
        echo "Domain: $DOMAIN"
        echo "Server: 192.168.0.100"
        echo ""

        # Certificate status
        check_certificate_status
        echo ""

        # Connectivity test
        test_connectivity
        echo ""

        # Recent log entries
        echo "Recent SSL Monitor Log Entries:"
        echo "--------------------------------"
        if [ -f "$LOG_FILE" ]; then
            tail -20 "$LOG_FILE"
        else
            echo "No log file found"
        fi

    } > "$report_file"

    print_success "Monitoring report generated: $report_file"

    # Display report
    cat "$report_file"
}

# Main monitoring function
main() {
    print_status "Starting SSL certificate monitoring for $DOMAIN"

    # Check certificate status
    check_certificate_status
    local status_code=$?

    # Get days until expiry for alerts
    local cert_file="$SSL_DIR/server.crt"
    local days_until_expiry=0

    if [ -f "$cert_file" ]; then
        local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry_date" +%s)
        local current_epoch=$(date +%s)
        days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    fi

    # Handle different status codes
    case $status_code in
        0)
            print_success "Certificate monitoring: All OK"
            ;;
        1)
            print_warning "Certificate monitoring: Warning threshold reached"
            send_email_alert "warning" "$days_until_expiry"
            send_grafana_alert "warning" "$days_until_expiry"
            create_renewal_reminder "$days_until_expiry"
            ;;
        2)
            print_critical "Certificate monitoring: Critical threshold reached"
            send_email_alert "critical" "$days_until_expiry"
            send_grafana_alert "critical" "$days_until_expiry"
            create_renewal_reminder "$days_until_expiry"
            ;;
        3)
            print_critical "Certificate monitoring: Certificate expired"
            send_email_alert "expired" "$days_until_expiry"
            send_grafana_alert "expired" "$days_until_expiry"
            create_renewal_reminder "$days_until_expiry"
            ;;
        *)
            print_error "Certificate monitoring: Unknown error"
            ;;
    esac

    print_status "SSL certificate monitoring completed"
}

# Script entry point
case "${1:-main}" in
    "main"|"")
        main
        ;;
    "check")
        check_certificate_status
        ;;
    "test")
        test_connectivity
        ;;
    "report")
        generate_report
        ;;
    "alert-test")
        print_status "Testing alert system..."
        send_email_alert "warning" "15"
        send_grafana_alert "warning" "15"
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  main (default) - Run full monitoring check"
        echo "  check          - Check certificate status only"
        echo "  test           - Test HTTPS connectivity"
        echo "  report         - Generate detailed monitoring report"
        echo "  alert-test     - Test alert system"
        echo "  help           - Show this help message"
        echo ""
        echo "Cron job example (daily check at 2 AM):"
        echo "0 2 * * * /opt/prs/scripts/ssl-renewal-monitor.sh"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
