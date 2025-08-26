# Configuration Files Reference

## Overview

This reference guide provides comprehensive documentation for all configuration files used in the PRS on-premises deployment, including their purposes, formats, and configuration options.

## Docker Configuration Files

### Docker Compose Configuration

#### Main Compose File
**File:** `02-docker-configuration/docker-compose.onprem.yml`

```yaml
version: '3.8'

services:
  # Nginx Reverse Proxy
  nginx:
    image: nginx:1.24-alpine
    container_name: prs-onprem-nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./ssl:/etc/nginx/ssl:ro
      - /mnt/hdd/logs/nginx:/var/log/nginx
    depends_on:
      - frontend
      - backend
    restart: unless-stopped
    networks:
      - prs-network

  # Frontend Service
  frontend:
    image: prs-frontend:latest
    container_name: prs-onprem-frontend
    environment:
      - VITE_APP_API_URL=${VITE_APP_API_URL}
      - VITE_APP_BASE_URL=${VITE_APP_BASE_URL}
      - VITE_APP_ENVIRONMENT=${VITE_APP_ENVIRONMENT}
    volumes:
      - /mnt/hdd/uploads:/app/uploads:ro
    restart: unless-stopped
    networks:
      - prs-network

  # Backend Service
  backend:
    image: prs-backend:latest
    container_name: prs-onprem-backend
    environment:
      - NODE_ENV=${NODE_ENV}
      - POSTGRES_HOST=${POSTGRES_HOST}
      - POSTGRES_PORT=${POSTGRES_PORT}
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - REDIS_HOST=${REDIS_HOST}
      - REDIS_PORT=${REDIS_PORT}
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - JWT_SECRET=${JWT_SECRET}
      - SESSION_SECRET=${SESSION_SECRET}
    volumes:
      - /mnt/hdd/uploads:/app/uploads
      - /mnt/hdd/logs/backend:/app/logs
    depends_on:
      - postgres
      - redis
    restart: unless-stopped
    networks:
      - prs-network

  # PostgreSQL with TimescaleDB
  postgres:
    image: timescale/timescaledb:2.11.2-pg15
    container_name: prs-onprem-postgres-timescale
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256
    volumes:
      - /mnt/hdd/postgresql-hot:/var/lib/postgresql/data
      - /mnt/hdd/wal-archive:/var/lib/postgresql/wal-archive
      - ./postgres/postgresql.conf:/etc/postgresql/postgresql.conf:ro
      - ./postgres/init:/docker-entrypoint-initdb.d:ro
    ports:
      - "5432:5432"
    restart: unless-stopped
    networks:
      - prs-network

  # Redis Cache
  redis:
    image: redis:7.2-alpine
    container_name: prs-onprem-redis
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    volumes:
      - /mnt/hdd/redis:/data
      - ./redis/redis.conf:/etc/redis/redis.conf:ro
    ports:
      - "6379:6379"
    restart: unless-stopped
    networks:
      - prs-network

networks:
  prs-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
```

### Environment Configuration

#### Production Environment File
**File:** `02-docker-configuration/.env.production`

```bash
# Environment Configuration
NODE_ENV=production
VITE_APP_ENVIRONMENT=production

# Domain Configuration
DOMAIN=prs.yourcompany.com
SERVER_IP=192.168.0.100
SSL_EMAIL=admin@yourcompany.com

# Database Configuration
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=prs_production
POSTGRES_USER=prs_admin
POSTGRES_PASSWORD=prod_secure_db_password_2024

# Redis Configuration
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=prod_secure_redis_password_2024

# Application Security
JWT_SECRET=prod_jwt_secret_key_very_long_and_secure_2024
SESSION_SECRET=prod_session_secret_key_very_long_and_secure_2024

# Frontend Configuration
VITE_APP_API_URL=https://prs.yourcompany.com/api
VITE_APP_BASE_URL=https://prs.yourcompany.com

# External API Configuration
CITYLAND_API_URL=https://api.citylandcondo.com
CITYLAND_API_USERNAME=production_user
CITYLAND_API_PASSWORD=production_password

# Email Configuration
SMTP_HOST=smtp.yourcompany.com
SMTP_PORT=587
SMTP_USER=noreply@yourcompany.com
SMTP_PASSWORD=smtp_production_password

# Monitoring Configuration
GRAFANA_ADMIN_PASSWORD=grafana_secure_password_2024
METRICS_ENABLED=true
ALERTS_ENABLED=true
ALERT_EMAIL=admin@yourcompany.com
```

## Nginx Configuration

### Main Nginx Configuration
**File:** `02-docker-configuration/nginx/nginx.conf`

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging Configuration
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
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'none';" always;

    # Rate Limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;

    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
}
```

### Site Configuration
**File:** `02-docker-configuration/nginx/conf.d/prs.conf`

```nginx
# Upstream Backend
upstream backend {
    server backend:4000;
    keepalive 32;
}

# Upstream Frontend
upstream frontend {
    server frontend:3000;
    keepalive 32;
}

# HTTP to HTTPS Redirect
server {
    listen 80;
    server_name prs.yourcompany.com;
    return 301 https://$server_name$request_uri;
}

# Main HTTPS Server
server {
    listen 443 ssl http2;
    server_name prs.yourcompany.com;

    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/certificate.crt;
    ssl_certificate_key /etc/nginx/ssl/private.key;
    ssl_trusted_certificate /etc/nginx/ssl/ca-bundle.crt;

    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;

    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # API Routes
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    # Authentication Routes (Stricter Rate Limiting)
    location /api/auth/ {
        limit_req zone=login burst=5 nodelay;
        
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # File Upload Routes
    location /api/files/upload {
        client_max_body_size 50M;
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Extended timeouts for file uploads
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Static File Serving
    location /uploads/ {
        alias /var/www/uploads/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Frontend Application
    location / {
        proxy_pass http://frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Health Check Endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
```

## Database Configuration

### PostgreSQL Configuration
**File:** `02-docker-configuration/postgres/postgresql.conf`

```ini
# PostgreSQL Configuration for PRS On-Premises
# Optimized for 16GB RAM, HDD-only HDD-only storage

# Connection Settings
listen_addresses = '*'
port = 5432
max_connections = 150

# Memory Settings
shared_buffers = 2GB
effective_cache_size = 4GB
work_mem = 32MB
maintenance_work_mem = 512MB

# WAL Settings
wal_level = replica
wal_buffers = 32MB
checkpoint_completion_target = 0.9
max_wal_size = 2GB
min_wal_size = 512MB

# Query Planner Settings
random_page_cost = 1.1
effective_io_concurrency = 200
seq_page_cost = 1.0

# Background Writer Settings
bgwriter_delay = 200ms
bgwriter_lru_maxpages = 100
bgwriter_lru_multiplier = 2.0

# Autovacuum Settings
autovacuum = on
autovacuum_naptime = 1min
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
autovacuum_vacuum_scale_factor = 0.2
autovacuum_analyze_scale_factor = 0.1

# Logging Settings
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on

# TimescaleDB Settings
shared_preload_libraries = 'timescaledb'
timescaledb.max_background_workers = 16

# Performance Monitoring
track_activities = on
track_counts = on
track_io_timing = on
track_functions = all
```

### Database Initialization
**File:** `02-docker-configuration/postgres/init/01-init-timescaledb.sql`

```sql
-- Initialize TimescaleDB Extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Create tablespaces for HDD-only storage
-- Tablespace creation not needed (HDD-only)
-- Tablespace creation not needed (HDD-only)

-- Create hypertables for time-series data
SELECT create_hypertable('notifications', 'created_at', 
    chunk_time_interval => INTERVAL '1 day',
    partitioning_column => 'user_id',
    number_partitions => 4
);

SELECT create_hypertable('audit_logs', 'created_at',
    chunk_time_interval => INTERVAL '1 day',
    partitioning_column => 'user_id', 
    number_partitions => 4
);

-- Set up compression policies
ALTER TABLE notifications SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'user_id',
    timescaledb.compress_orderby = 'created_at DESC'
);

ALTER TABLE audit_logs SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'user_id, action',
    timescaledb.compress_orderby = 'created_at DESC'
);

-- Add compression policies
SELECT add_compression_policy('notifications', INTERVAL '7 days');
SELECT add_compression_policy('audit_logs', INTERVAL '7 days');

-- Add data movement policies
SELECT add_move_chunk_policy('notifications', INTERVAL '30 days', 'pg_default');
SELECT add_move_chunk_policy('audit_logs', INTERVAL '30 days', 'pg_default');
```

## Redis Configuration

### Redis Configuration
**File:** `02-docker-configuration/redis/redis.conf`

```ini
# Redis Configuration for PRS On-Premises

# Network
bind 0.0.0.0
port 6379
protected-mode yes

# General
daemonize no
supervised no
pidfile /var/run/redis_6379.pid
loglevel notice
logfile ""

# Persistence
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /data

# Append Only File
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# Memory Management
maxmemory 1gb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Clients
maxclients 10000
timeout 300

# Security
requirepass your_redis_password_here

# Performance
tcp-keepalive 300
tcp-backlog 511
```

## Monitoring Configuration

### Prometheus Configuration
**File:** `02-docker-configuration/prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Node Exporter
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  # PostgreSQL Exporter
  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['postgres-exporter:9187']

  # Redis Exporter
  - job_name: 'redis-exporter'
    static_configs:
      - targets: ['redis-exporter:9121']

  # Application Metrics
  - job_name: 'prs-backend'
    static_configs:
      - targets: ['backend:4000']
    metrics_path: '/metrics'

  # Nginx Metrics
  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx-exporter:9113']
```

### Grafana Configuration
**File:** `02-docker-configuration/grafana/grafana.ini`

```ini
[server]
http_port = 3001
domain = prs.yourcompany.com
root_url = https://prs.yourcompany.com/grafana/

[security]
admin_user = admin
admin_password = grafana_secure_password_2024
secret_key = grafana_secret_key_2024

[auth]
disable_login_form = false
disable_signout_menu = false

[auth.anonymous]
enabled = false

[database]
type = postgres
host = postgres:5432
name = grafana
user = grafana_user
password = grafana_password

[session]
provider = redis
provider_config = addr=redis:6379,pool_size=100,db=2

[log]
mode = console file
level = info

[paths]
data = /var/lib/grafana
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins
provisioning = /etc/grafana/provisioning
```

## SSL Configuration

### SSL Certificate Configuration
**File:** `02-docker-configuration/ssl/ssl.conf`

```nginx
# SSL Configuration Template

# Certificate Paths
ssl_certificate /etc/nginx/ssl/certificate.crt;
ssl_certificate_key /etc/nginx/ssl/private.key;
ssl_trusted_certificate /etc/nginx/ssl/ca-bundle.crt;

# SSL Protocols and Ciphers
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
ssl_prefer_server_ciphers off;

# SSL Session Settings
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
ssl_session_tickets off;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;

# Security Headers
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header X-Frame-Options DENY always;
add_header X-Content-Type-Options nosniff always;
add_header X-XSS-Protection "1; mode=block" always;
```

---

!!! success "Configuration Reference Complete"
    This comprehensive reference covers all major configuration files used in the PRS on-premises deployment with detailed explanations and examples.

!!! tip "Configuration Management"
    Keep configuration files in version control and use environment-specific configurations for different deployment stages.

!!! warning "Security Configuration"
    Always review and customize security settings, passwords, and certificates before deploying to production environments.
