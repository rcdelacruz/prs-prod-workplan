# Security Configuration

## Overview

This guide covers comprehensive security hardening for the PRS on-premises deployment, including system-level security, application security, and compliance measures.

## System Security

### Firewall Configuration

#### UFW Firewall Setup

```bash
# Reset and configure UFW firewall
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH access (restrict to admin network)
sudo ufw allow from 192.168.0.201/24 to any port 22 comment 'SSH admin access'

# HTTP/HTTPS access (internal network only)
sudo ufw allow from 192.168.0.0/20 to any port 80 comment 'HTTP internal'
sudo ufw allow from 192.168.0.0/20 to any port 443 comment 'HTTPS internal'

# Management interfaces (admin network only)
sudo ufw allow from 192.168.0.201/24 to any port 8080 comment 'Adminer'
sudo ufw allow from 192.168.0.201/24 to any port 3001 comment 'Grafana'
sudo ufw allow from 192.168.0.201/24 to any port 9000 comment 'Portainer'
sudo ufw allow from 192.168.0.201/24 to any port 9090 comment 'Prometheus'

# Rate limiting for HTTP services
sudo ufw limit 80/tcp
sudo ufw limit 443/tcp

# Enable firewall
sudo ufw --force enable
sudo ufw status verbose
```

#### Advanced Firewall Rules

```bash
# Block common attack patterns
sudo ufw deny from 192.168.0.0/20 to any port 22 comment 'Block SSH from clients'
sudo ufw deny from 172.20.0.0/24 to any port 22 comment 'Block SSH from containers'

# Allow Docker networks
sudo ufw allow in on docker0
sudo ufw allow in on br-*

# Log dropped packets
sudo ufw logging on

# Custom iptables rules for additional security
sudo iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --set
sudo iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
```

### Intrusion Detection

#### Fail2Ban Configuration

```bash
# Install and configure Fail2Ban
sudo apt install fail2ban

# Create custom configuration
sudo tee /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 1800

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10
bantime = 600

[docker-auth]
enabled = true
filter = docker-auth
logpath = /var/log/docker.log
maxretry = 3
bantime = 3600
EOF

# Create custom filters
sudo tee /etc/fail2ban/filter.d/nginx-http-auth.conf << 'EOF'
[Definition]
failregex = ^ \[error\] \d+#\d+: \*\d+ user "\S+":? (password mismatch|was not found in), client: <HOST>, server: \S+, request: "\S+ \S+ HTTP/\d+\.\d+", host: "\S+"$
            ^ \[error\] \d+#\d+: \*\d+ no user/password was provided for basic authentication, client: <HOST>, server: \S+, request: "\S+ \S+ HTTP/\d+\.\d+", host: "\S+"$

ignoreregex =
EOF

sudo tee /etc/fail2ban/filter.d/nginx-limit-req.conf << 'EOF'
[Definition]
failregex = limiting requests, excess: \S+ by zone "\S+", client: <HOST>

ignoreregex =
EOF

# Start and enable Fail2Ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
sudo fail2ban-client status
```

### System Hardening

#### Kernel Security Parameters

```bash
# Apply security-focused kernel parameters
sudo tee -a /etc/sysctl.conf << 'EOF'
# Network security
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1

# IPv6 security (disable if not used)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# Kernel security
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF

# Apply changes
sudo sysctl -p
```

#### File System Security

```bash
# Set secure file permissions
sudo chmod 600 /etc/shadow
sudo chmod 600 /etc/gshadow
sudo chmod 644 /etc/passwd
sudo chmod 644 /etc/group

# Secure important directories
sudo chmod 700 /root
sudo chmod 755 /etc
sudo chmod 755 /var

# Set immutable flag on critical files
sudo chattr +i /etc/passwd
sudo chattr +i /etc/shadow
sudo chattr +i /etc/group
sudo chattr +i /etc/gshadow

# Create secure tmp directory
sudo mount -o remount,noexec,nosuid,nodev /tmp
```

## Application Security

### Container Security

#### Docker Security Configuration

```yaml
# Security-hardened Docker Compose configuration
services:
  backend:
    security_opt:
      - no-new-privileges:true
      - apparmor:docker-default
    read_only: true
    tmpfs:
      - /tmp
      - /var/tmp
    user: "1000:1000"
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    
  postgres:
    security_opt:
      - no-new-privileges:true
    user: "999:999"
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - DAC_OVERRIDE
      - FOWNER
      - SETGID
      - SETUID
```

#### Container Image Security

```bash
# Scan Docker images for vulnerabilities
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image prs-backend:latest

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image prs-frontend:latest

# Update base images regularly
docker pull timescale/timescaledb:latest-pg15
docker pull redis:7-alpine
docker pull nginx:1.24-alpine
```

### Database Security

#### PostgreSQL Security Hardening

```sql
-- Remove default databases and users
DROP DATABASE IF EXISTS template0;
DROP DATABASE IF EXISTS template1;
DROP ROLE IF EXISTS postgres;

-- Create security-focused configuration
ALTER SYSTEM SET log_connections = 'on';
ALTER SYSTEM SET log_disconnections = 'on';
ALTER SYSTEM SET log_statement = 'all';
ALTER SYSTEM SET log_min_duration_statement = 1000;
ALTER SYSTEM SET log_checkpoints = 'on';
ALTER SYSTEM SET log_lock_waits = 'on';

-- Password security
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
ALTER SYSTEM SET ssl = 'on';
ALTER SYSTEM SET ssl_cert_file = '/var/lib/postgresql/ssl/server.crt';
ALTER SYSTEM SET ssl_key_file = '/var/lib/postgresql/ssl/server.key';

-- Connection security
ALTER SYSTEM SET listen_addresses = 'localhost,172.20.0.30';
ALTER SYSTEM SET port = 5432;

-- Reload configuration
SELECT pg_reload_conf();
```

#### Database Access Control

```sql
-- Create role hierarchy with minimal privileges
CREATE ROLE prs_readonly NOLOGIN;
CREATE ROLE prs_readwrite NOLOGIN;
CREATE ROLE prs_admin NOLOGIN;

-- Grant minimal required permissions
GRANT CONNECT ON DATABASE prs_production TO prs_readonly;
GRANT USAGE ON SCHEMA public TO prs_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO prs_readonly;

GRANT prs_readonly TO prs_readwrite;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO prs_readwrite;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO prs_readwrite;

GRANT prs_readwrite TO prs_admin;
GRANT CREATE ON SCHEMA public TO prs_admin;

-- Create application users with strong passwords
CREATE USER prs_app_user WITH 
  PASSWORD 'secure_random_password_32_chars'
  CONNECTION LIMIT 50
  VALID UNTIL 'infinity';
GRANT prs_readwrite TO prs_app_user;

-- Revoke dangerous functions from public
REVOKE EXECUTE ON FUNCTION pg_read_file(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pg_ls_dir(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pg_read_binary_file(text) FROM PUBLIC;
```

### Application Security Headers

#### Nginx Security Configuration

```nginx
# Security headers configuration
server {
    # Security headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self'; frame-ancestors 'none';" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    
    # HSTS with preload
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    
    # Hide server information
    server_tokens off;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;
    
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        limit_req_status 429;
    }
    
    location /api/auth/login {
        limit_req zone=login burst=3 nodelay;
        limit_req_status 429;
    }
    
    # Block common attack patterns
    location ~* \.(php|asp|aspx|jsp)$ {
        deny all;
    }
    
    location ~* /\.(git|svn|hg) {
        deny all;
    }
    
    location ~* \.(env|config|ini|log|bak)$ {
        deny all;
    }
}
```

## SSL/TLS Security

### SSL Configuration Hardening

```nginx
# Modern SSL configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;

# SSL session optimization
ssl_session_cache shared:SSL:50m;
ssl_session_timeout 1d;
ssl_session_tickets off;

# OCSP stapling
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/nginx/ssl/ca-bundle.crt;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;

# DH parameters for perfect forward secrecy
ssl_dhparam /etc/nginx/ssl/dhparam.pem;
```

### Certificate Security

```bash
# Generate strong DH parameters
sudo openssl dhparam -out /opt/prs-deployment/02-docker-configuration/ssl/dhparam.pem 2048

# Set secure permissions
sudo chmod 600 /opt/prs-deployment/02-docker-configuration/ssl/dhparam.pem

# Certificate monitoring script
cat > /opt/prs-deployment/scripts/ssl-monitor.sh << 'EOF'
#!/bin/bash
CERT_FILE="/opt/prs-deployment/02-docker-configuration/ssl/certificate.crt"
DAYS_WARNING=30

# Check certificate expiration
EXPIRY_DATE=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))

if [ $DAYS_UNTIL_EXPIRY -lt $DAYS_WARNING ]; then
    echo "WARNING: SSL certificate expires in $DAYS_UNTIL_EXPIRY days"
    # Send alert email or notification
fi
EOF

chmod +x /opt/prs-deployment/scripts/ssl-monitor.sh

# Add to crontab for daily monitoring
(crontab -l 2>/dev/null; echo "0 6 * * * /opt/prs-deployment/scripts/ssl-monitor.sh") | crontab -
```

## Access Control

### User Management

#### System User Security

```bash
# Disable unused system accounts
sudo usermod -s /usr/sbin/nologin bin
sudo usermod -s /usr/sbin/nologin daemon
sudo usermod -s /usr/sbin/nologin adm
sudo usermod -s /usr/sbin/nologin lp
sudo usermod -s /usr/sbin/nologin sync
sudo usermod -s /usr/sbin/nologin shutdown
sudo usermod -s /usr/sbin/nologin halt
sudo usermod -s /usr/sbin/nologin mail
sudo usermod -s /usr/sbin/nologin news
sudo usermod -s /usr/sbin/nologin uucp
sudo usermod -s /usr/sbin/nologin operator
sudo usermod -s /usr/sbin/nologin games
sudo usermod -s /usr/sbin/nologin gopher
sudo usermod -s /usr/sbin/nologin ftp

# Set password policies
sudo tee -a /etc/login.defs << 'EOF'
PASS_MAX_DAYS 90
PASS_MIN_DAYS 1
PASS_WARN_AGE 7
PASS_MIN_LEN 12
EOF

# Configure PAM for strong passwords
sudo tee -a /etc/pam.d/common-password << 'EOF'
password requisite pam_pwquality.so retry=3 minlen=12 difok=3 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1
EOF
```

#### SSH Security

```bash
# Harden SSH configuration
sudo tee /etc/ssh/sshd_config.d/99-prs-security.conf << 'EOF'
# Protocol and encryption
Protocol 2
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Authentication
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
MaxAuthTries 3
MaxSessions 2

# Network restrictions
AllowUsers prs-deploy
AllowGroups sudo
DenyUsers root
ClientAliveInterval 300
ClientAliveCountMax 2

# Logging
LogLevel VERBOSE
SyslogFacility AUTH

# Disable dangerous features
PermitEmptyPasswords no
PermitUserEnvironment no
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PrintMotd no
EOF

# Restart SSH service
sudo systemctl restart sshd
```

## Monitoring and Auditing

### Security Monitoring

```bash
# Install security monitoring tools
sudo apt install aide rkhunter chkrootkit

# Configure AIDE (Advanced Intrusion Detection Environment)
sudo aideinit
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Create AIDE monitoring script
cat > /opt/prs-deployment/scripts/security-monitor.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/prs-security.log"

# Run AIDE check
echo "$(date): Running AIDE integrity check" >> "$LOG_FILE"
if ! aide --check; then
    echo "$(date): AIDE detected file system changes" >> "$LOG_FILE"
    # Send alert
fi

# Run rootkit check
echo "$(date): Running rootkit scan" >> "$LOG_FILE"
if ! rkhunter --check --skip-keypress; then
    echo "$(date): rkhunter detected potential issues" >> "$LOG_FILE"
    # Send alert
fi

# Check for failed login attempts
FAILED_LOGINS=$(grep "Failed password" /var/log/auth.log | wc -l)
if [ $FAILED_LOGINS -gt 10 ]; then
    echo "$(date): High number of failed login attempts: $FAILED_LOGINS" >> "$LOG_FILE"
    # Send alert
fi
EOF

chmod +x /opt/prs-deployment/scripts/security-monitor.sh

# Add to crontab for daily security checks
(crontab -l 2>/dev/null; echo "0 3 * * * /opt/prs-deployment/scripts/security-monitor.sh") | crontab -
```

### Audit Logging

```bash
# Install and configure auditd
sudo apt install auditd audispd-plugins

# Configure audit rules
sudo tee /etc/audit/rules.d/prs-audit.rules << 'EOF'
# Monitor file access
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k identity

# Monitor system calls
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change

# Monitor network configuration
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/network -p wa -k system-locale

# Monitor Docker
-w /var/lib/docker -p wa -k docker
-w /etc/docker -p wa -k docker

# Monitor PRS application
-w /opt/prs-deployment -p wa -k prs-config
-w /mnt/ssd -p wa -k prs-data
-w /mnt/hdd -p wa -k prs-data
EOF

# Restart auditd
sudo systemctl restart auditd
sudo systemctl enable auditd
```

## Compliance and Backup Security

### Backup Encryption

```bash
# Encrypt database backups
cat > /opt/prs-deployment/scripts/encrypted-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/mnt/hdd/postgres-backups/encrypted"
GPG_RECIPIENT="backup@your-domain.com"
DATE=$(date +%Y%m%d_%H%M%S)

# Create encrypted backup
docker exec prs-onprem-postgres-timescale pg_dump -U prs_admin -d prs_production | \
  gzip | \
  gpg --trust-model always --encrypt -r "$GPG_RECIPIENT" > \
  "$BACKUP_DIR/prs_encrypted_backup_${DATE}.sql.gz.gpg"

# Verify backup
if [ -f "$BACKUP_DIR/prs_encrypted_backup_${DATE}.sql.gz.gpg" ]; then
    echo "$(date): Encrypted backup created successfully" >> /var/log/prs-backup.log
else
    echo "$(date): Encrypted backup failed" >> /var/log/prs-backup.log
fi
EOF

chmod +x /opt/prs-deployment/scripts/encrypted-backup.sh
```

### Security Compliance Checklist

```bash
# Create compliance validation script
cat > /opt/prs-deployment/scripts/compliance-check.sh << 'EOF'
#!/bin/bash
REPORT_FILE="/tmp/prs-compliance-report.txt"

echo "PRS Security Compliance Report - $(date)" > "$REPORT_FILE"
echo "================================================" >> "$REPORT_FILE"

# Check firewall status
if sudo ufw status | grep -q "Status: active"; then
    echo "✓ Firewall is active" >> "$REPORT_FILE"
else
    echo "✗ Firewall is not active" >> "$REPORT_FILE"
fi

# Check fail2ban status
if sudo systemctl is-active fail2ban >/dev/null; then
    echo "✓ Fail2Ban is running" >> "$REPORT_FILE"
else
    echo "✗ Fail2Ban is not running" >> "$REPORT_FILE"
fi

# Check SSL certificate validity
if openssl x509 -in /opt/prs-deployment/02-docker-configuration/ssl/certificate.crt -checkend 2592000 >/dev/null; then
    echo "✓ SSL certificate is valid for 30+ days" >> "$REPORT_FILE"
else
    echo "✗ SSL certificate expires within 30 days" >> "$REPORT_FILE"
fi

# Check audit daemon
if sudo systemctl is-active auditd >/dev/null; then
    echo "✓ Audit daemon is running" >> "$REPORT_FILE"
else
    echo "✗ Audit daemon is not running" >> "$REPORT_FILE"
fi

# Check for security updates
UPDATES=$(apt list --upgradable 2>/dev/null | grep -c security)
if [ "$UPDATES" -eq 0 ]; then
    echo "✓ No security updates pending" >> "$REPORT_FILE"
else
    echo "✗ $UPDATES security updates pending" >> "$REPORT_FILE"
fi

cat "$REPORT_FILE"
EOF

chmod +x /opt/prs-deployment/scripts/compliance-check.sh
```

---

!!! success "Security Hardened"
    Your PRS deployment now has enterprise-grade security with comprehensive protection against common threats and compliance with security best practices.

!!! tip "Regular Security Reviews"
    Perform monthly security reviews using the compliance check script and update security configurations based on new threats and vulnerabilities.

!!! warning "Security Maintenance"
    Security is an ongoing process. Regularly update systems, monitor logs, and review access controls to maintain a strong security posture.
