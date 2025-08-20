# 🔒 Security Hardening for On-Premises Deployment

## 🎯 Security Overview

This document outlines comprehensive security hardening measures for the PRS on-premises deployment, adapted from the EC2 setup to work without Cloudflare protection while maintaining enterprise-grade security.

## 🛡️ Security Architecture

### Security Layers
```
Layer 1: Network Security (Hardware Firewall + UFW)
Layer 2: Application Security (Nginx + Headers)
Layer 3: Container Security (Docker + Isolation)
Layer 4: Database Security (PostgreSQL + SSL)
Layer 5: Application Security (Authentication + Authorization)
Layer 6: Monitoring Security (Audit Logs + Intrusion Detection)
```

### Threat Model
- **Internal Network**: Trusted but monitored
- **User Access**: 100 concurrent users from internal network
- **Data Sensitivity**: High (property registration data)
- **Compliance**: Data protection and audit requirements
- **Attack Vectors**: Internal threats, privilege escalation, data exfiltration

## 🔐 Authentication & Authorization

### Multi-Factor Authentication (MFA)
```javascript
// Backend MFA Configuration
MFA_ENABLED=true
OTP_ISSUER="PRS On-Premises"
OTP_WINDOW=30
OTP_BACKUP_CODES=10
BYPASS_OTP=false  // Never bypass in production
```

### Session Management
```javascript
// Secure Session Configuration
SESSION_TIMEOUT=3600          // 1 hour timeout
SESSION_SECURE=true           // HTTPS only
SESSION_HTTP_ONLY=true        // No JavaScript access
SESSION_SAME_SITE=strict      // CSRF protection
MAX_LOGIN_ATTEMPTS=5          // Account lockout
LOCKOUT_DURATION=900          // 15 minutes lockout
```

### Password Policy
```javascript
// Password Requirements
PASSWORD_MIN_LENGTH=12
PASSWORD_REQUIRE_UPPERCASE=true
PASSWORD_REQUIRE_LOWERCASE=true
PASSWORD_REQUIRE_NUMBERS=true
PASSWORD_REQUIRE_SYMBOLS=true
PASSWORD_HISTORY=12           // Prevent reuse
PASSWORD_EXPIRY_DAYS=90       // Force rotation
```

## 🌐 Network Security

### Firewall Configuration (UFW)
```bash
#!/bin/bash
# /opt/prs/security/configure-firewall.sh

# Reset and set defaults
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow internal network access to services
sudo ufw allow from 192.168.0.0/20 to any port 80 comment "HTTP"
sudo ufw allow from 192.168.0.0/20 to any port 443 comment "HTTPS"
sudo ufw allow from 192.168.0.0/20 to any port 8080 comment "Adminer"
sudo ufw allow from 192.168.0.0/20 to any port 3001 comment "Grafana"
sudo ufw allow from 192.168.0.0/20 to any port 9000 comment "Portainer"
sudo ufw allow from 192.168.0.0/20 to any port 9090 comment "Prometheus"

# Allow SSH from IT network only
sudo ufw allow from 192.168.1.0/24 to any port 22 comment "SSH IT"

# Rate limiting for HTTP/HTTPS
sudo ufw limit 80/tcp
sudo ufw limit 443/tcp

# Enable firewall
sudo ufw --force enable

# Log configuration
sudo ufw logging on
```

### Network Intrusion Detection
```bash
# Install and configure Fail2Ban
sudo apt install fail2ban

# /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
```

## 🔒 SSL/TLS Configuration

### SSL Certificate Management
```bash
#!/bin/bash
# /opt/prs/security/ssl-setup.sh

# Install Certbot for Let's Encrypt
sudo apt update
sudo apt install certbot python3-certbot-nginx

# Generate SSL certificate
sudo certbot certonly --standalone \
  -d prs.client-domain.com \
  --email admin@client-domain.com \
  --agree-tos \
  --non-interactive

# Set up auto-renewal
echo "0 12 * * * /usr/bin/certbot renew --quiet" | sudo crontab -

# Copy certificates to Docker volume
sudo mkdir -p /opt/prs/ssl
sudo cp /etc/letsencrypt/live/prs.client-domain.com/fullchain.pem /opt/prs/ssl/server.crt
sudo cp /etc/letsencrypt/live/prs.client-domain.com/privkey.pem /opt/prs/ssl/server.key

# Generate DH parameters
sudo openssl dhparam -out /opt/prs/ssl/dhparam.pem 2048

# Set proper permissions
sudo chmod 600 /opt/prs/ssl/server.key
sudo chmod 644 /opt/prs/ssl/server.crt
sudo chmod 644 /opt/prs/ssl/dhparam.pem
```

### Nginx SSL Configuration
```nginx
# /opt/prs/nginx/sites-enabled/prs-ssl.conf
server {
    listen 443 ssl http2;
    server_name prs.client-domain.com;

    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    ssl_dhparam /etc/nginx/ssl/dhparam.pem;

    # SSL Security
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self';" always;

    # Rate Limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;

    location / {
        proxy_pass http://frontend:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://backend:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /auth/login {
        limit_req zone=login burst=5 nodelay;
        proxy_pass http://backend:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name prs.client-domain.com;
    return 301 https://$server_name$request_uri;
}
```

## 🗄️ Database Security

### PostgreSQL Security Configuration
```sql
-- Database security settings
ALTER SYSTEM SET ssl = on;
ALTER SYSTEM SET ssl_cert_file = '/etc/ssl/certs/server.crt';
ALTER SYSTEM SET ssl_key_file = '/etc/ssl/private/server.key';
ALTER SYSTEM SET ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL';
ALTER SYSTEM SET ssl_prefer_server_ciphers = on;

-- Connection security
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;
ALTER SYSTEM SET log_statement = 'mod';
ALTER SYSTEM SET log_min_duration_statement = 1000;

-- Authentication security
ALTER SYSTEM SET password_encryption = 'scram-sha-256';

-- Reload configuration
SELECT pg_reload_conf();
```

### Database Access Control
```sql
-- Create read-only user for monitoring
CREATE USER prs_monitor WITH PASSWORD 'CHANGE_THIS_MONITOR_PASSWORD';
GRANT CONNECT ON DATABASE prs_production TO prs_monitor;
GRANT USAGE ON SCHEMA public TO prs_monitor;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO prs_monitor;

-- Create backup user
CREATE USER prs_backup WITH PASSWORD 'CHANGE_THIS_BACKUP_PASSWORD';
GRANT CONNECT ON DATABASE prs_production TO prs_backup;
GRANT USAGE ON SCHEMA public TO prs_backup;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO prs_backup;

-- Revoke unnecessary permissions
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO prs_user;
```

## 🐳 Container Security

### Docker Security Configuration
```bash
# /etc/docker/daemon.json
{
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "seccomp-profile": "/etc/docker/seccomp.json",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

### Container Hardening
```yaml
# Security context for containers
security_opt:
  - no-new-privileges:true
  - seccomp:unconfined
read_only: true
tmpfs:
  - /tmp
  - /var/tmp
cap_drop:
  - ALL
cap_add:
  - CHOWN
  - DAC_OVERRIDE
  - SETGID
  - SETUID
```

## 📊 Security Monitoring

### Audit Logging
```bash
# Install and configure auditd
sudo apt install auditd audispd-plugins

# /etc/audit/rules.d/prs.rules
# Monitor file access
-w /opt/prs/ -p wa -k prs_files
-w /mnt/ssd/ -p wa -k ssd_access
-w /mnt/hdd/ -p wa -k hdd_access

# Monitor network connections
-a always,exit -F arch=b64 -S connect -k network_connect
-a always,exit -F arch=b64 -S accept -k network_accept

# Monitor privilege escalation
-w /etc/sudoers -p wa -k privilege_escalation
-w /etc/passwd -p wa -k user_modification

# Restart auditd
sudo systemctl restart auditd
```

### Security Metrics
```yaml
# Prometheus security metrics
failed_login_attempts_total
ssl_certificate_expiry_days
firewall_blocked_connections_total
audit_events_total{type="file_access"}
audit_events_total{type="network_access"}
audit_events_total{type="privilege_escalation"}
```

## 🚨 Incident Response

### Security Incident Procedures
1. **Detection**: Automated alerts and monitoring
2. **Assessment**: Determine scope and impact
3. **Containment**: Isolate affected systems
4. **Eradication**: Remove threats and vulnerabilities
5. **Recovery**: Restore normal operations
6. **Lessons Learned**: Update security measures

### Emergency Contacts
```yaml
IT Security Team: security@client-domain.com
System Administrator: admin@client-domain.com
Management: management@client-domain.com
External Security Consultant: consultant@security-firm.com
```

## 📋 Security Checklist

### Daily Security Tasks
- [ ] Review security logs and alerts
- [ ] Check failed login attempts
- [ ] Verify backup integrity
- [ ] Monitor system resource usage
- [ ] Check SSL certificate status

### Weekly Security Tasks
- [ ] Review audit logs
- [ ] Update security patches
- [ ] Test backup restoration
- [ ] Review user access permissions
- [ ] Check firewall logs

### Monthly Security Tasks
- [ ] Security vulnerability assessment
- [ ] Review and update security policies
- [ ] Test incident response procedures
- [ ] Review user accounts and permissions
- [ ] Update security documentation

---

**Document Version**: 1.0  
**Created**: 2025-08-13  
**Last Updated**: 2025-08-13  
**Status**: Production Ready
