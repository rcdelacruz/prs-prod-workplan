# Security Maintenance

## Overview

This guide covers security maintenance procedures for the PRS on-premises deployment, including security updates, vulnerability assessments, access reviews, and compliance monitoring.

## Security Maintenance Schedule

### Daily Security Tasks
- **Security Log Review** - Monitor authentication and access logs
- **Failed Login Analysis** - Investigate suspicious login attempts
- **Certificate Monitoring** - Check SSL certificate status
- **Vulnerability Scanning** - Automated security scans
- **Backup Verification** - Ensure security of backup data

### Weekly Security Tasks
- **Access Review** - Review user permissions and access rights
- **Security Updates** - Apply critical security patches
- **Firewall Log Analysis** - Review network security logs
- **Intrusion Detection** - Check for security incidents
- **Security Configuration Audit** - Verify security settings

### Monthly Security Tasks
- **Comprehensive Security Audit** - Full security assessment
- **Penetration Testing** - Security vulnerability testing
- **Compliance Review** - Ensure regulatory compliance
- **Security Training** - Update security procedures
- **Incident Response Testing** - Test security response procedures

## Daily Security Procedures

### Security Log Monitoring

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/daily-security-check.sh

set -euo pipefail

LOG_FILE="/var/log/prs-security.log"
ALERT_EMAIL="security@your-domain.com"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check failed login attempts
check_failed_logins() {
    log_message "Checking failed login attempts"
    
    # Check system authentication logs
    FAILED_SSH=$(grep "Failed password" /var/log/auth.log | grep "$(date +%Y-%m-%d)" | wc -l)
    FAILED_APP=$(docker logs prs-onprem-backend --since 24h 2>&1 | grep -i "authentication failed" | wc -l)
    
    log_message "Failed SSH logins: $FAILED_SSH"
    log_message "Failed app logins: $FAILED_APP"
    
    # Alert on high failure rates
    if [ "$FAILED_SSH" -gt 20 ]; then
        log_message "WARNING: High SSH login failures detected"
        echo "High SSH login failures: $FAILED_SSH attempts" | \
        mail -s "PRS Security Alert: High SSH Failures" "$ALERT_EMAIL"
    fi
    
    if [ "$FAILED_APP" -gt 50 ]; then
        log_message "WARNING: High application login failures detected"
        echo "High application login failures: $FAILED_APP attempts" | \
        mail -s "PRS Security Alert: High App Failures" "$ALERT_EMAIL"
    fi
}

# Check SSL certificate status
check_ssl_certificates() {
    log_message "Checking SSL certificate status"
    
    CERT_FILE="/opt/prs/prs-deployment/02-docker-configuration/ssl/certificate.crt"
    if [ -f "$CERT_FILE" ]; then
        EXPIRY_DATE=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
        EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
        CURRENT_EPOCH=$(date +%s)
        DAYS_UNTIL_EXPIRY=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
        
        log_message "SSL certificate expires in $DAYS_UNTIL_EXPIRY days"
        
        if [ "$DAYS_UNTIL_EXPIRY" -lt 7 ]; then
            log_message "CRITICAL: SSL certificate expires in $DAYS_UNTIL_EXPIRY days"
            echo "SSL certificate expires in $DAYS_UNTIL_EXPIRY days" | \
            mail -s "PRS Security Alert: SSL Certificate Expiring" "$ALERT_EMAIL"
        elif [ "$DAYS_UNTIL_EXPIRY" -lt 30 ]; then
            log_message "WARNING: SSL certificate expires in $DAYS_UNTIL_EXPIRY days"
        fi
    else
        log_message "ERROR: SSL certificate file not found"
    fi
}

# Check for suspicious database activity
check_database_security() {
    log_message "Checking database security"
    
    # Check for unusual connection patterns
    UNUSUAL_CONNECTIONS=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
    SELECT COUNT(*) FROM pg_stat_activity 
    WHERE client_addr IS NOT NULL 
    AND client_addr NOT IN ('127.0.0.1', '::1')
    AND application_name NOT LIKE 'prs-%';
    " | xargs)
    
    if [ "$UNUSUAL_CONNECTIONS" -gt 0 ]; then
        log_message "WARNING: $UNUSUAL_CONNECTIONS unusual database connections detected"
    fi
    
    # Check for failed database connections
    FAILED_DB_CONNECTIONS=$(docker logs prs-onprem-postgres-timescale --since 24h 2>&1 | grep -i "authentication failed" | wc -l)
    log_message "Failed database connections: $FAILED_DB_CONNECTIONS"
    
    if [ "$FAILED_DB_CONNECTIONS" -gt 10 ]; then
        log_message "WARNING: High database authentication failures"
        echo "High database authentication failures: $FAILED_DB_CONNECTIONS" | \
        mail -s "PRS Security Alert: Database Auth Failures" "$ALERT_EMAIL"
    fi
}

# Check system integrity
check_system_integrity() {
    log_message "Checking system integrity"
    
    # Check for unauthorized file changes
    if command -v aide >/dev/null 2>&1; then
        aide --check > /tmp/aide-check.log 2>&1
        if [ $? -ne 0 ]; then
            log_message "WARNING: System integrity check failed"
            mail -s "PRS Security Alert: System Integrity" "$ALERT_EMAIL" < /tmp/aide-check.log
        fi
    fi
    
    # Check for rootkits
    if command -v rkhunter >/dev/null 2>&1; then
        rkhunter --check --skip-keypress > /tmp/rkhunter.log 2>&1
        if grep -q "Warning" /tmp/rkhunter.log; then
            log_message "WARNING: Rootkit scanner found issues"
            mail -s "PRS Security Alert: Rootkit Check" "$ALERT_EMAIL" < /tmp/rkhunter.log
        fi
    fi
}

# Main execution
main() {
    log_message "Starting daily security check"
    
    check_failed_logins
    check_ssl_certificates
    check_database_security
    check_system_integrity
    
    log_message "Daily security check completed"
}

main "$@"
```

### Access Control Monitoring

```bash
#!/bin/bash
# Monitor user access and permissions

# Check active user sessions
ACTIVE_SESSIONS=$(docker exec prs-onprem-redis redis-cli -a "$REDIS_PASSWORD" eval "return #redis.call('keys', 'session:*')" 0)
echo "Active user sessions: $ACTIVE_SESSIONS"

# Check privileged user activity
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT 
    u.username,
    COUNT(*) as actions_today
FROM audit_logs al
JOIN users u ON al.user_id = u.id
WHERE al.created_at >= CURRENT_DATE
AND u.role IN ('admin', 'super_admin')
GROUP BY u.username
ORDER BY actions_today DESC;
"

# Check for new user registrations
NEW_USERS=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
SELECT COUNT(*) FROM users WHERE created_at >= CURRENT_DATE;
" | xargs)

echo "New user registrations today: $NEW_USERS"
```

## Weekly Security Procedures

### Security Updates Management

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/weekly-security-updates.sh

set -euo pipefail

LOG_FILE="/var/log/prs-security.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

main() {
    log_message "Starting weekly security updates"
    
    # Check for security updates
    apt update
    SECURITY_UPDATES=$(apt list --upgradable 2>/dev/null | grep security | wc -l)
    
    log_message "Available security updates: $SECURITY_UPDATES"
    
    if [ "$SECURITY_UPDATES" -gt 0 ]; then
        log_message "Applying security updates"
        
        # Create pre-update backup
        /opt/prs-deployment/scripts/backup-full.sh
        
        # Apply security updates
        DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
        
        # Check if reboot required
        if [ -f /var/run/reboot-required ]; then
            log_message "System reboot required after security updates"
            echo "System reboot required after security updates" | \
            mail -s "PRS Security: Reboot Required" admin@your-domain.com
        fi
        
        # Restart services
        systemctl restart docker
        docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml restart
        
        log_message "Security updates completed"
    else
        log_message "No security updates available"
    fi
}

main "$@"
```

### Access Review Procedures

```bash
#!/bin/bash
# Weekly access review

# Generate user access report
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT 
    u.username,
    u.email,
    u.role,
    u.last_login_at,
    CASE 
        WHEN u.last_login_at < NOW() - INTERVAL '30 days' THEN 'Inactive'
        WHEN u.last_login_at < NOW() - INTERVAL '7 days' THEN 'Low Activity'
        ELSE 'Active'
    END as activity_status,
    u.created_at
FROM users u
ORDER BY u.last_login_at DESC NULLS LAST;
" > /tmp/user-access-report.csv

# Check for inactive users
INACTIVE_USERS=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "
SELECT COUNT(*) FROM users 
WHERE last_login_at < NOW() - INTERVAL '90 days'
OR last_login_at IS NULL;
" | xargs)

echo "Inactive users (90+ days): $INACTIVE_USERS"

# Email access report
if command -v mail >/dev/null 2>&1; then
    mail -s "PRS Weekly Access Review" admin@your-domain.com < /tmp/user-access-report.csv
fi
```

## Monthly Security Procedures

### Comprehensive Security Audit

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/monthly-security-audit.sh

set -euo pipefail

AUDIT_DATE=$(date +%Y%m)
AUDIT_REPORT="/tmp/security-audit-$AUDIT_DATE.txt"

# Generate comprehensive security audit report
cat > "$AUDIT_REPORT" << EOF
PRS Security Audit Report - $AUDIT_DATE
========================================
Generated: $(date)

SYSTEM SECURITY STATUS
----------------------
EOF

# Check system hardening
echo "System Hardening:" >> "$AUDIT_REPORT"
echo "- SSH root login: $(grep "^PermitRootLogin" /etc/ssh/sshd_config || echo "Not configured")" >> "$AUDIT_REPORT"
echo "- Password authentication: $(grep "^PasswordAuthentication" /etc/ssh/sshd_config || echo "Not configured")" >> "$AUDIT_REPORT"
echo "- Firewall status: $(ufw status | head -1)" >> "$AUDIT_REPORT"

# Check SSL configuration
echo "" >> "$AUDIT_REPORT"
echo "SSL/TLS Configuration:" >> "$AUDIT_REPORT"
if [ -f "/opt/prs-deployment/02-docker-configuration/ssl/certificate.crt" ]; then
    CERT_SUBJECT=$(openssl x509 -in /opt/prs-deployment/02-docker-configuration/ssl/certificate.crt -noout -subject)
    CERT_EXPIRY=$(openssl x509 -in /opt/prs-deployment/02-docker-configuration/ssl/certificate.crt -noout -enddate)
    echo "- Certificate subject: $CERT_SUBJECT" >> "$AUDIT_REPORT"
    echo "- Certificate expiry: $CERT_EXPIRY" >> "$AUDIT_REPORT"
else
    echo "- SSL certificate: NOT FOUND" >> "$AUDIT_REPORT"
fi

# Check database security
echo "" >> "$AUDIT_REPORT"
echo "Database Security:" >> "$AUDIT_REPORT"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT 
    'Total users: ' || COUNT(*)
FROM users
UNION ALL
SELECT 
    'Admin users: ' || COUNT(*)
FROM users 
WHERE role IN ('admin', 'super_admin')
UNION ALL
SELECT 
    'Inactive users (90+ days): ' || COUNT(*)
FROM users 
WHERE last_login_at < NOW() - INTERVAL '90 days'
OR last_login_at IS NULL;
" >> "$AUDIT_REPORT"

# Check application security
echo "" >> "$AUDIT_REPORT"
echo "Application Security:" >> "$AUDIT_REPORT"
echo "- Authentication failures (30 days): $(docker logs prs-onprem-backend --since 720h 2>&1 | grep -i "authentication failed" | wc -l)" >> "$AUDIT_REPORT"
echo "- Active sessions: $(docker exec prs-onprem-redis redis-cli -a "$REDIS_PASSWORD" eval "return #redis.call('keys', 'session:*')" 0)" >> "$AUDIT_REPORT"

# Security recommendations
echo "" >> "$AUDIT_REPORT"
echo "SECURITY RECOMMENDATIONS" >> "$AUDIT_REPORT"
echo "------------------------" >> "$AUDIT_REPORT"

# Check for common security issues
if grep -q "PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
    echo "- CRITICAL: Disable SSH root login" >> "$AUDIT_REPORT"
fi

if [ "$INACTIVE_USERS" -gt 5 ]; then
    echo "- WARNING: Review and disable inactive user accounts" >> "$AUDIT_REPORT"
fi

# Email security audit report
if command -v mail >/dev/null 2>&1; then
    mail -s "PRS Monthly Security Audit Report" admin@your-domain.com < "$AUDIT_REPORT"
fi

echo "Security audit completed: $AUDIT_REPORT"
```

### Vulnerability Assessment

```bash
#!/bin/bash
# Vulnerability assessment procedures

# Check for known vulnerabilities
if command -v nmap >/dev/null 2>&1; then
    echo "Running network vulnerability scan..."
    nmap -sV --script vuln localhost > /tmp/vuln-scan.txt
fi

# Check Docker security
echo "Checking Docker security..."
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    -v /usr/local/bin/docker:/usr/local/bin/docker \
    aquasec/trivy image prs-backend:latest > /tmp/docker-security.txt

# Check for outdated packages
echo "Checking for outdated packages..."
apt list --upgradable > /tmp/outdated-packages.txt

# Generate vulnerability report
cat > /tmp/vulnerability-report.txt << EOF
PRS Vulnerability Assessment Report
===================================
Date: $(date)

Network Vulnerabilities:
$(cat /tmp/vuln-scan.txt 2>/dev/null || echo "Network scan not available")

Docker Security Issues:
$(cat /tmp/docker-security.txt 2>/dev/null || echo "Docker scan not available")

Outdated Packages:
$(cat /tmp/outdated-packages.txt)
EOF

# Email vulnerability report
if command -v mail >/dev/null 2>&1; then
    mail -s "PRS Vulnerability Assessment" security@your-domain.com < /tmp/vulnerability-report.txt
fi
```

## Security Incident Response

### Incident Detection

```bash
#!/bin/bash
# Security incident detection

# Check for brute force attacks
BRUTE_FORCE_THRESHOLD=50
FAILED_LOGINS=$(grep "Failed password" /var/log/auth.log | grep "$(date +%Y-%m-%d)" | wc -l)

if [ "$FAILED_LOGINS" -gt "$BRUTE_FORCE_THRESHOLD" ]; then
    echo "SECURITY INCIDENT: Possible brute force attack detected"
    echo "Failed login attempts: $FAILED_LOGINS"
    
    # Block suspicious IPs
    grep "Failed password" /var/log/auth.log | grep "$(date +%Y-%m-%d)" | \
    awk '{print $(NF-3)}' | sort | uniq -c | sort -nr | head -10 | \
    while read count ip; do
        if [ "$count" -gt 10 ]; then
            echo "Blocking IP: $ip (attempts: $count)"
            ufw deny from "$ip"
        fi
    done
fi

# Check for unusual database activity
UNUSUAL_QUERIES=$(docker logs prs-onprem-postgres-timescale --since 1h 2>&1 | grep -i "drop\|delete\|truncate" | wc -l)
if [ "$UNUSUAL_QUERIES" -gt 5 ]; then
    echo "SECURITY INCIDENT: Unusual database activity detected"
    echo "Destructive queries in last hour: $UNUSUAL_QUERIES"
fi
```

### Incident Response Procedures

```bash
#!/bin/bash
# Security incident response

incident_response() {
    local incident_type="$1"
    local severity="$2"
    
    echo "SECURITY INCIDENT DETECTED"
    echo "Type: $incident_type"
    echo "Severity: $severity"
    echo "Time: $(date)"
    
    # Log incident
    echo "$(date): INCIDENT [$severity] $incident_type" >> /var/log/prs-security-incidents.log
    
    # Immediate response actions
    case "$severity" in
        "CRITICAL")
            # Isolate system
            echo "Implementing emergency security measures..."
            
            # Block all external access
            ufw --force reset
            ufw default deny incoming
            ufw default deny outgoing
            ufw allow from 192.168.0.0/16
            ufw --force enable
            
            # Stop non-essential services
            docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml stop frontend
            
            # Create forensic backup
            /opt/prs-deployment/scripts/backup-full.sh
            ;;
        "HIGH")
            # Enhanced monitoring
            echo "Implementing enhanced security monitoring..."
            
            # Reduce session timeouts
            # Force password resets for admin users
            ;;
        "MEDIUM")
            # Standard response
            echo "Implementing standard security response..."
            ;;
    esac
    
    # Notify security team
    echo "Security incident: $incident_type ($severity)" | \
    mail -s "PRS SECURITY INCIDENT: $severity" security@your-domain.com
}
```

## Compliance and Auditing

### Compliance Monitoring

```bash
#!/bin/bash
# Compliance monitoring procedures

# Check data retention compliance
echo "Checking data retention compliance..."
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT 
    'Audit logs older than 7 years: ' || COUNT(*)
FROM audit_logs 
WHERE created_at < NOW() - INTERVAL '7 years'
UNION ALL
SELECT 
    'User data without consent: ' || COUNT(*)
FROM users 
WHERE consent_date IS NULL
AND created_at < NOW() - INTERVAL '30 days';
"

# Check access control compliance
echo "Checking access control compliance..."
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT 
    'Users without role assignment: ' || COUNT(*)
FROM users 
WHERE role IS NULL
UNION ALL
SELECT 
    'Admin users without MFA: ' || COUNT(*)
FROM users 
WHERE role IN ('admin', 'super_admin')
AND mfa_enabled = false;
"
```

---

!!! success "Security Maintenance Ready"
    Your PRS deployment now has comprehensive security maintenance procedures covering daily monitoring, weekly updates, monthly audits, and incident response.

!!! tip "Proactive Security"
    Regular security maintenance helps prevent incidents and ensures compliance with security standards and regulations.

!!! warning "Incident Response"
    Ensure all team members are familiar with incident response procedures and have access to emergency contact information.
