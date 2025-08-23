# Application Configuration

## Overview

This guide covers the complete application configuration for the PRS on-premises deployment, including environment variables, service settings, and performance tuning.

## Configuration Structure

```
02-docker-configuration/
├── .env                          # Main environment file
├── .env.example                  # Environment template
├── docker-compose.onprem.yml     # Docker services configuration
├── nginx/                        # Nginx configuration
│   ├── nginx.conf               # Main nginx config
│   └── sites-enabled/           # Virtual host configs
├── config/                       # Service configurations
│   ├── grafana/                 # Grafana dashboards and settings
│   ├── prometheus/              # Prometheus rules and config
│   └── postgres/                # PostgreSQL initialization scripts
└── ssl/                          # SSL certificates
    ├── certificate.crt
    ├── private.key
    └── ca-bundle.crt
```

## Environment Configuration

### Environment Variables

#### and Network Settings

```bash
# Domain Configuration
DOMAIN=your-domain.com
SERVER_IP=192.168.0.100
NETWORK_SUBNET=192.168.0.0/20
NETWORK_GATEWAY=192.168.0.1

# SSL Configuration
SSL_EMAIL=admin@your-domain.com
ENABLE_SSL=true
SSL_CERT_PATH=./ssl/certificate.crt
SSL_KEY_PATH=./ssl/private.key
SSL_CA_PATH=./ssl/ca-bundle.crt
```

#### Configuration

```bash
# PostgreSQL Settings
POSTGRES_DB=prs_production
POSTGRES_USER=prs_admin
POSTGRES_PASSWORD=your_secure_password_here
POSTGRES_PORT=5432
POSTGRES_HOST=postgres

# Database Performance Settings
POSTGRES_MAX_CONNECTIONS=150
POSTGRES_SHARED_BUFFERS=2GB
POSTGRES_EFFECTIVE_CACHE_SIZE=4GB
POSTGRES_WORK_MEM=32MB
POSTGRES_MAINTENANCE_WORK_MEM=512MB

# TimescaleDB Settings
TIMESCALEDB_TELEMETRY=off
TIMESCALEDB_MAX_BACKGROUND_WORKERS=16
```

#### Secrets

```bash
# Generate secure secrets
JWT_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32)
OTP_KEY=$(openssl rand -base64 16)
PASS_SECRET=$(openssl rand -base64 32)
SESSION_SECRET=$(openssl rand -base64 32)

# API Keys
API_KEY=$(openssl rand -hex 16)
WEBHOOK_SECRET=$(openssl rand -base64 24)
```

#### Configuration

```bash
# Redis Settings
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=your_redis_password_here
REDIS_MEMORY_LIMIT=2g
REDIS_MAXMEMORY_POLICY=allkeys-lru

# Redis Performance
REDIS_SAVE_INTERVAL=900 1
REDIS_APPENDONLY=yes
REDIS_APPENDFSYNC=everysec
```

### API Configuration

#### API Integration

```bash
# Cityland API Settings
CITYLAND_API_URL=https://your-api-endpoint.com
CITYLAND_ACCOUNTING_URL=https://your-accounting-endpoint.com
CITYLAND_API_USERNAME=your_api_username
CITYLAND_API_PASSWORD=your_api_password
CITYLAND_API_TIMEOUT=30000
CITYLAND_API_RETRY_ATTEMPTS=3
```

#### Configuration

```bash
# SMTP Settings
SMTP_HOST=smtp.your-domain.com
SMTP_PORT=587
SMTP_SECURE=true
SMTP_USER=noreply@your-domain.com
SMTP_PASSWORD=your_smtp_password
SMTP_FROM_NAME=PRS System
SMTP_FROM_EMAIL=noreply@your-domain.com
```

### Performance Settings

#### API Configuration

```bash
# Node.js Settings
NODE_ENV=production
PORT=4000
NODEJS_MAX_OLD_SPACE_SIZE=2048
NODEJS_MAX_SEMI_SPACE_SIZE=128

# API Performance
API_RATE_LIMIT=1000
API_RATE_WINDOW=900000
API_TIMEOUT=30000
API_MAX_PAYLOAD_SIZE=50mb

# Connection Pool Settings
DB_POOL_MIN=5
DB_POOL_MAX=20
DB_POOL_ACQUIRE=30000
DB_POOL_IDLE=10000
DB_POOL_EVICT=20000
```

#### Configuration

```bash
# Vite Build Settings
VITE_APP_API_URL=https://${DOMAIN}/api
VITE_APP_WS_URL=wss://${DOMAIN}/ws
VITE_APP_UPLOAD_MAX_SIZE=10485760
VITE_APP_CHUNK_SIZE=1048576

# Frontend Performance
VITE_BUILD_TARGET=es2015
VITE_BUILD_MINIFY=terser
VITE_BUILD_SOURCEMAP=false
```

## Nginx Configuration

### Nginx Configuration

```nginx
# /nginx/nginx.conf
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

    access_log /var/log/nginx/access.log main;

    # Performance Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 50M;

    # Gzip Compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    # Security Headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    # Rate Limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;

    # Include virtual hosts
    include /etc/nginx/sites-enabled/*;
}
```

### Host Configuration

```nginx
# /nginx/sites-enabled/prs.conf
upstream backend {
    least_conn;
    server frontend:3000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

upstream api {
    least_conn;
    server backend:4000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://$server_name$request_uri;
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/certificate.crt;
    ssl_certificate_key /etc/nginx/ssl/private.key;
    ssl_trusted_certificate /etc/nginx/ssl/ca-bundle.crt;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Frontend Application
    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
        
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }

    # API Endpoints
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        
        proxy_pass http://api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_connect_timeout 30s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Login endpoint with stricter rate limiting
    location /api/auth/login {
        limit_req zone=login burst=5 nodelay;
        
        proxy_pass http://api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # File Uploads
    location /api/upload {
        client_max_body_size 50M;
        proxy_request_buffering off;
        
        proxy_pass http://api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }

    # Static Files
    location /uploads/ {
        alias /var/www/uploads/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Content-Type-Options nosniff;
    }

    # Health Check
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Security
    location ~ /\. {
        deny all;
    }
}
```

## Monitoring Configuration

### Configuration

```yaml
# config/grafana/grafana.ini
[server]
protocol = http
http_port = 3000
domain = ${DOMAIN}
root_url = https://${DOMAIN}:3001/

[database]
type = postgres
host = postgres:5432
name = grafana
user = ${POSTGRES_USER}
password = ${POSTGRES_PASSWORD}

[security]
admin_user = admin
admin_password = ${GRAFANA_ADMIN_PASSWORD}
secret_key = ${GRAFANA_SECRET_KEY}

[users]
allow_sign_up = false
allow_org_create = false
auto_assign_org = true
auto_assign_org_role = Viewer

[auth.anonymous]
enabled = false

[snapshots]
external_enabled = false

[alerting]
enabled = true
execute_alerts = true
```

### Configuration

```yaml
# config/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alerts.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis-exporter'
    static_configs:
      - targets: ['redis-exporter:9121']

  - job_name: 'nginx-exporter'
    static_configs:
      - targets: ['nginx-exporter:9113']

  - job_name: 'prs-backend'
    static_configs:
      - targets: ['backend:4000']
    metrics_path: '/metrics'
    scrape_interval: 30s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
```

## Security Configuration

### Security Settings

```bash
# Security Headers
SECURITY_HSTS_MAX_AGE=31536000
SECURITY_CONTENT_TYPE_OPTIONS=nosniff
SECURITY_FRAME_OPTIONS=DENY
SECURITY_XSS_PROTECTION=1; mode=block

# CORS Settings
CORS_ORIGIN=https://${DOMAIN}
CORS_METHODS=GET,POST,PUT,DELETE,OPTIONS
CORS_ALLOWED_HEADERS=Content-Type,Authorization,X-Requested-With

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=1000
RATE_LIMIT_SKIP_SUCCESSFUL_REQUESTS=false

# Session Security
SESSION_SECURE=true
SESSION_HTTP_ONLY=true
SESSION_SAME_SITE=strict
SESSION_MAX_AGE=86400000
```

### Security

```sql
-- Create application-specific roles
CREATE ROLE prs_app_read;
CREATE ROLE prs_app_write;
CREATE ROLE prs_app_admin;

-- Grant appropriate permissions
GRANT SELECT ON ALL TABLES IN SCHEMA public TO prs_app_read;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO prs_app_write;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO prs_app_admin;

-- Create application user
CREATE USER prs_application WITH PASSWORD 'secure_app_password';
GRANT prs_app_write TO prs_application;
```

## Configuration Management

### File Generation

```bash
#!/bin/bash
# Generate secure environment file

ENV_FILE="/opt/prs-deployment/02-docker-configuration/.env"

# Generate secure passwords
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 16)

# Create environment file
cat > "$ENV_FILE" << EOF
# Generated on $(date)

# Domain Configuration
DOMAIN=your-domain.com
SERVER_IP=192.168.0.100

# Database Configuration
POSTGRES_DB=prs_production
POSTGRES_USER=prs_admin
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Redis Configuration
REDIS_PASSWORD=$REDIS_PASSWORD

# Application Secrets
JWT_SECRET=$JWT_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY

# Monitoring
GRAFANA_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD

# External APIs
CITYLAND_API_URL=https://your-api-endpoint.com
CITYLAND_API_USERNAME=your_username
CITYLAND_API_PASSWORD=your_password
EOF

echo "Environment file generated: $ENV_FILE"
echo "Please update the external API credentials and domain settings."
```

### Validation

```bash
#!/bin/bash
# Validate configuration

ENV_FILE="/opt/prs-deployment/02-docker-configuration/.env"

# Check required variables
REQUIRED_VARS=(
    "DOMAIN"
    "POSTGRES_PASSWORD"
    "REDIS_PASSWORD"
    "JWT_SECRET"
    "ENCRYPTION_KEY"
)

echo "Validating configuration..."

for var in "${REQUIRED_VARS[@]}"; do
    if ! grep -q "^${var}=" "$ENV_FILE"; then
        echo "❌ Missing required variable: $var"
        exit 1
    else
        echo "Found: $var"
    fi
done

# Check password strength
if grep -q "POSTGRES_PASSWORD=password" "$ENV_FILE"; then
    echo "❌ Weak PostgreSQL password detected"
    exit 1
fi

echo "Configuration validation passed"
```

---

!!! success "Configuration Complete"
    With proper application configuration, the PRS system provides optimal performance, security, and reliability for production use.

!!! tip "Security Best Practices"
    Always use strong, randomly generated passwords and keep configuration files secure with appropriate file permissions.
