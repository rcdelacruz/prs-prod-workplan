# Environment Variables

## Overview

This reference guide provides a comprehensive list of all environment variables used in the PRS on-premises deployment, including their purposes, default values, and configuration examples.

## Core Application Variables

### Database Configuration

```bash
# PostgreSQL/TimescaleDB Configuration
POSTGRES_HOST=postgres                    # Database host (container name)
POSTGRES_PORT=5432                       # Database port
POSTGRES_DB=prs_production               # Database name
POSTGRES_USER=prs_admin                  # Database username
POSTGRES_PASSWORD=secure_random_password # Database password (CHANGE THIS)

# Database Connection Pool
DB_POOL_MIN=5                            # Minimum connections
DB_POOL_MAX=20                           # Maximum connections
DB_POOL_ACQUIRE=30000                    # Connection timeout (ms)
DB_POOL_IDLE=10000                       # Idle timeout (ms)

# Database Performance
DB_STATEMENT_TIMEOUT=30000               # Query timeout (ms)
DB_IDLE_TRANSACTION_TIMEOUT=60000        # Idle transaction timeout (ms)
```

### Redis Configuration

```bash
# Redis Cache Configuration
REDIS_HOST=redis                         # Redis host (container name)
REDIS_PORT=6379                         # Redis port
REDIS_PASSWORD=redis_secure_password     # Redis password (CHANGE THIS)
REDIS_DB=0                              # Redis database number

# Redis Session Store
REDIS_SESSION_DB=1                       # Session database number
REDIS_SESSION_TTL=86400                  # Session TTL (seconds)
```

### Application Server

```bash
# Server Configuration
NODE_ENV=production                      # Environment mode
PORT=4000                               # Backend port
HOST=0.0.0.0                           # Bind address

# Security
JWT_SECRET=your_jwt_secret_key_here     # JWT signing key (CHANGE THIS)
JWT_EXPIRES_IN=24h                      # JWT expiration
SESSION_SECRET=your_session_secret      # Session secret (CHANGE THIS)

# CORS Configuration
CORS_ORIGIN=https://your-domain.com     # Allowed origins
CORS_CREDENTIALS=true                   # Allow credentials
```

### Frontend Configuration

```bash
# Vite/React Configuration
VITE_APP_API_URL=https://your-domain.com/api    # API base URL
VITE_APP_BASE_URL=https://your-domain.com       # Application base URL
VITE_APP_ENVIRONMENT=production                 # Environment name
VITE_APP_VERSION=1.0.0                         # Application version

# Feature Flags
VITE_APP_ENABLE_DEBUG=false             # Debug mode
VITE_APP_ENABLE_ANALYTICS=true          # Analytics tracking
VITE_APP_ENABLE_NOTIFICATIONS=true      # Push notifications
```

## External Integrations

### CityLand API Integration

```bash
# CityLand API Configuration
CITYLAND_API_URL=https://your-api-endpoint.com  # API endpoint
CITYLAND_API_USERNAME=your_username             # API username
CITYLAND_API_PASSWORD=your_password             # API password
CITYLAND_API_TIMEOUT=30000                      # Request timeout (ms)
CITYLAND_API_RETRY_ATTEMPTS=3                   # Retry attempts
CITYLAND_API_RETRY_DELAY=1000                   # Retry delay (ms)

# API Rate Limiting
CITYLAND_API_RATE_LIMIT=100                     # Requests per minute
CITYLAND_API_BURST_LIMIT=10                     # Burst requests
```

### Email Configuration

```bash
# SMTP Configuration
SMTP_HOST=smtp.your-domain.com           # SMTP server
SMTP_PORT=587                           # SMTP port (587 for TLS, 465 for SSL)
SMTP_SECURE=false                       # Use SSL (true for port 465)
SMTP_USER=noreply@your-domain.com       # SMTP username
SMTP_PASSWORD=smtp_password             # SMTP password

# Email Settings
EMAIL_FROM=noreply@your-domain.com      # From address
EMAIL_FROM_NAME=PRS System              # From name
EMAIL_REPLY_TO=support@your-domain.com  # Reply-to address

# Email Templates
EMAIL_TEMPLATE_DIR=/app/templates/email # Template directory
EMAIL_LOGO_URL=https://your-domain.com/logo.png  # Logo URL
```

### File Storage

```bash
# File Upload Configuration
UPLOAD_MAX_SIZE=52428800                # Max file size (50MB)
UPLOAD_ALLOWED_TYPES=pdf,doc,docx,xls,xlsx,jpg,jpeg,png  # Allowed types
UPLOAD_STORAGE_PATH=/app/uploads        # Storage path
UPLOAD_TEMP_PATH=/app/temp             # Temporary path

# File Processing
FILE_PROCESSING_ENABLED=true           # Enable file processing
FILE_VIRUS_SCAN_ENABLED=false         # Enable virus scanning
FILE_THUMBNAIL_ENABLED=true           # Generate thumbnails
```

## System Configuration

### Domain and SSL

```bash
# Domain Configuration
DOMAIN=your-domain.com                  # Primary domain
SERVER_IP=192.168.0.100                # Server IP address
SSL_EMAIL=admin@your-domain.com        # SSL certificate email

# SSL Configuration
SSL_CERT_PATH=/etc/nginx/ssl/certificate.crt    # Certificate path
SSL_KEY_PATH=/etc/nginx/ssl/private.key         # Private key path
SSL_CA_PATH=/etc/nginx/ssl/ca-bundle.crt        # CA bundle path
```

### Logging Configuration

```bash
# Application Logging
LOG_LEVEL=info                          # Log level (error, warn, info, debug)
LOG_FORMAT=json                         # Log format (json, text)
LOG_FILE=/app/logs/application.log      # Log file path
LOG_MAX_SIZE=100MB                      # Max log file size
LOG_MAX_FILES=10                        # Max log files to keep

# Database Logging
DB_LOG_QUERIES=false                    # Log all queries
DB_LOG_SLOW_QUERIES=true               # Log slow queries
DB_SLOW_QUERY_THRESHOLD=1000           # Slow query threshold (ms)

# Access Logging
ACCESS_LOG_ENABLED=true                 # Enable access logs
ACCESS_LOG_FORMAT=combined              # Access log format
```

### Performance Configuration

```bash
# Application Performance
WORKER_PROCESSES=4                      # Number of worker processes
WORKER_CONNECTIONS=1000                 # Connections per worker
KEEPALIVE_TIMEOUT=65                    # Keep-alive timeout

# Caching
CACHE_ENABLED=true                      # Enable caching
CACHE_TTL=3600                         # Default cache TTL (seconds)
CACHE_MAX_SIZE=100MB                   # Max cache size

# Rate Limiting
RATE_LIMIT_ENABLED=true                # Enable rate limiting
RATE_LIMIT_WINDOW=900000               # Rate limit window (15 minutes)
RATE_LIMIT_MAX_REQUESTS=100            # Max requests per window
```

## Monitoring and Observability

### Metrics and Monitoring

```bash
# Prometheus Metrics
METRICS_ENABLED=true                    # Enable metrics collection
METRICS_PORT=9090                      # Metrics port
METRICS_PATH=/metrics                  # Metrics endpoint

# Health Checks
HEALTH_CHECK_ENABLED=true              # Enable health checks
HEALTH_CHECK_INTERVAL=30000            # Health check interval (ms)
HEALTH_CHECK_TIMEOUT=5000              # Health check timeout (ms)

# Grafana Configuration
GRAFANA_ADMIN_USER=admin               # Grafana admin username
GRAFANA_ADMIN_PASSWORD=secure_password # Grafana admin password (CHANGE THIS)
GRAFANA_PORT=3001                      # Grafana port
```

### Alerting

```bash
# Alert Configuration
ALERTS_ENABLED=true                     # Enable alerting
ALERT_EMAIL=admin@your-domain.com      # Alert email address
ALERT_WEBHOOK_URL=                     # Webhook URL for alerts

# Slack Integration
SLACK_WEBHOOK_URL=                     # Slack webhook URL
SLACK_CHANNEL=#prs-alerts              # Slack channel
SLACK_USERNAME=PRS-Bot                 # Slack bot username
```

## Security Configuration

### Authentication and Authorization

```bash
# Authentication
AUTH_ENABLED=true                       # Enable authentication
AUTH_SESSION_TIMEOUT=86400             # Session timeout (seconds)
AUTH_MAX_LOGIN_ATTEMPTS=5              # Max login attempts
AUTH_LOCKOUT_DURATION=900              # Lockout duration (seconds)

# Password Policy
PASSWORD_MIN_LENGTH=8                   # Minimum password length
PASSWORD_REQUIRE_UPPERCASE=true        # Require uppercase
PASSWORD_REQUIRE_LOWERCASE=true        # Require lowercase
PASSWORD_REQUIRE_NUMBERS=true          # Require numbers
PASSWORD_REQUIRE_SYMBOLS=true          # Require symbols

# Two-Factor Authentication
TWO_FACTOR_ENABLED=false               # Enable 2FA
TWO_FACTOR_ISSUER=PRS                  # 2FA issuer name
```

### Security Headers

```bash
# Security Configuration
SECURITY_HEADERS_ENABLED=true          # Enable security headers
HSTS_MAX_AGE=31536000                 # HSTS max age
CSP_ENABLED=true                      # Enable CSP
CSP_REPORT_URI=/api/csp-report        # CSP report URI

# CORS Security
CORS_MAX_AGE=86400                    # CORS max age
CORS_ALLOWED_HEADERS=Content-Type,Authorization  # Allowed headers
CORS_EXPOSED_HEADERS=X-Total-Count    # Exposed headers
```

## Development and Testing

### Development Environment

```bash
# Development Configuration
DEBUG=true                             # Enable debug mode
HOT_RELOAD=true                       # Enable hot reload
SOURCE_MAPS=true                      # Generate source maps

# Testing
TEST_DATABASE_URL=postgresql://test_user:test_pass@localhost:5433/prs_test
TEST_REDIS_URL=redis://localhost:6380/0
TEST_TIMEOUT=30000                    # Test timeout (ms)
```

### Feature Flags

```bash
# Feature Toggles
FEATURE_NEW_DASHBOARD=true            # Enable new dashboard
FEATURE_ADVANCED_REPORTING=false     # Enable advanced reporting
FEATURE_MOBILE_APP=false             # Enable mobile app features
FEATURE_API_V2=false                 # Enable API v2
```

## Environment File Examples

### Production Environment (.env.production)

```bash
# Production Environment Configuration
NODE_ENV=production
DOMAIN=prs.yourcompany.com
SERVER_IP=192.168.0.100

# Database
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=prs_production
POSTGRES_USER=prs_admin
POSTGRES_PASSWORD=prod_secure_db_password_2024

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=prod_secure_redis_password_2024

# Security
JWT_SECRET=prod_jwt_secret_key_very_long_and_secure_2024
SESSION_SECRET=prod_session_secret_key_very_long_and_secure_2024

# External APIs
CITYLAND_API_URL=https://api.citylandcondo.com
CITYLAND_API_USERNAME=production_user
CITYLAND_API_PASSWORD=production_password

# Email
SMTP_HOST=smtp.yourcompany.com
SMTP_PORT=587
SMTP_USER=noreply@yourcompany.com
SMTP_PASSWORD=smtp_production_password

# Monitoring
GRAFANA_ADMIN_PASSWORD=grafana_secure_password_2024
METRICS_ENABLED=true
ALERTS_ENABLED=true
ALERT_EMAIL=admin@yourcompany.com

# Frontend
VITE_APP_API_URL=https://prs.yourcompany.com/api
VITE_APP_BASE_URL=https://prs.yourcompany.com
VITE_APP_ENVIRONMENT=production
```

### Staging Environment (.env.staging)

```bash
# Staging Environment Configuration
NODE_ENV=staging
DOMAIN=prs-staging.yourcompany.com
SERVER_IP=192.168.0.101

# Database
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=prs_staging
POSTGRES_USER=prs_admin
POSTGRES_PASSWORD=staging_secure_db_password_2024

# Debug and Testing
DEBUG=true
LOG_LEVEL=debug
FEATURE_NEW_DASHBOARD=true
FEATURE_ADVANCED_REPORTING=true

# External APIs (Test endpoints)
CITYLAND_API_URL=https://api-test.citylandcondo.com
CITYLAND_API_USERNAME=staging_user
CITYLAND_API_PASSWORD=staging_password

# Frontend
VITE_APP_API_URL=https://prs-staging.yourcompany.com/api
VITE_APP_BASE_URL=https://prs-staging.yourcompany.com
VITE_APP_ENVIRONMENT=staging
VITE_APP_ENABLE_DEBUG=true
```

### Development Environment (.env.development)

```bash
# Development Environment Configuration
NODE_ENV=development
DOMAIN=localhost
SERVER_IP=127.0.0.1

# Database
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=prs_development
POSTGRES_USER=prs_dev
POSTGRES_PASSWORD=dev_password

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=dev_redis_password

# Development Features
DEBUG=true
HOT_RELOAD=true
SOURCE_MAPS=true
LOG_LEVEL=debug

# Security (Development only - not secure)
JWT_SECRET=dev_jwt_secret
SESSION_SECRET=dev_session_secret

# Frontend
VITE_APP_API_URL=http://localhost:4000/api
VITE_APP_BASE_URL=http://localhost:3000
VITE_APP_ENVIRONMENT=development
VITE_APP_ENABLE_DEBUG=true

# Feature Flags (All enabled for testing)
FEATURE_NEW_DASHBOARD=true
FEATURE_ADVANCED_REPORTING=true
FEATURE_MOBILE_APP=true
FEATURE_API_V2=true
```

## Environment Variable Validation

### Validation Script

```bash
#!/bin/bash
# validate-environment.sh

REQUIRED_VARS=(
    "POSTGRES_PASSWORD"
    "REDIS_PASSWORD"
    "JWT_SECRET"
    "SESSION_SECRET"
    "DOMAIN"
    "SERVER_IP"
)

OPTIONAL_VARS=(
    "CITYLAND_API_URL"
    "SMTP_HOST"
    "GRAFANA_ADMIN_PASSWORD"
)

echo "Validating environment variables..."

# Check required variables
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Required variable $var is not set"
        exit 1
    else
        echo "✓ $var is set"
    fi
done

# Check optional variables
for var in "${OPTIONAL_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "WARNING: Optional variable $var is not set"
    else
        echo "✓ $var is set"
    fi
done

# Validate password strength
if [ ${#POSTGRES_PASSWORD} -lt 12 ]; then
    echo "WARNING: POSTGRES_PASSWORD should be at least 12 characters"
fi

if [ ${#JWT_SECRET} -lt 32 ]; then
    echo "WARNING: JWT_SECRET should be at least 32 characters"
fi

echo "Environment validation completed"
```

---

!!! success "Environment Reference Complete"
    This comprehensive reference covers all environment variables used in the PRS on-premises deployment with examples for different environments.

!!! tip "Security Best Practices"
    Always use strong, unique passwords for production environments and never commit sensitive environment files to version control.

!!! warning "Environment Isolation"
    Keep development, staging, and production environment variables completely separate and use different credentials for each environment.
