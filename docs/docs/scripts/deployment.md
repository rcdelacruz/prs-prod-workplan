# Deployment Scripts

## Overview

This guide documents all deployment scripts used in the PRS on-premises deployment, including their purpose, usage, and configuration options.

## Scripts Directory Structure

```
scripts/
├── deploy-onprem.sh              # Main deployment script
├── setup-env.sh                  # Environment setup
├── setup-storage.sh              # Storage configuration
├── ssl-automation-citylandcondo.sh # SSL certificate automation
├── backup-maintenance.sh         # Backup procedures with NAS integration
├── backup-full.sh                # Full database backup with NAS support
├── backup-application-data.sh    # Application backup with NAS support
├── system-health-check.sh        # Health monitoring
├── security-hardening-check.sh   # Security validation
├── repo-config.sh                # Repository configuration
├── nas-config.example.sh         # NAS configuration template
├── test-nas-connection.sh        # NAS connectivity testing
├── restore-point-in-time.sh      # Point-in-time recovery
└── utils/                        # Utility scripts
    ├── docker-cleanup.sh         # Docker maintenance
    ├── log-rotation.sh           # Log management
    └── performance-test.sh       # Performance testing
```

## Main Deployment Script

### deploy-onprem.sh

**Purpose**: Complete deployment automation for PRS on-premises environment

**Usage**:
```bash
./deploy-onprem.sh [environment] [options]

# Examples:
./deploy-onprem.sh prod                    # Deploy production
./deploy-onprem.sh staging                 # Deploy staging
./deploy-onprem.sh prod --skip-build       # Skip image building
./deploy-onprem.sh prod --force-rebuild    # Force rebuild all images
```

**Script Overview**:
```bash
#!/bin/bash
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${1:-prod}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Main deployment function
main() {
    log_info "Starting PRS deployment for environment: $ENVIRONMENT"

    # Validate environment
    validate_environment

    # Setup repositories
    setup_repositories

    # Build Docker images
    build_images

    # Deploy services
    deploy_services

    # Configure database
    setup_database

    # Run health checks
    health_checks

    log_success "Deployment completed successfully!"
}

# Environment validation
validate_environment() {
    log_info "Validating deployment environment..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi

    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi

    # Check environment file
    if [ ! -f "$PROJECT_ROOT/02-docker-configuration/.env" ]; then
        log_error "Environment file not found. Run setup-env.sh first."
        exit 1
    fi

    # Check storage
    if [ ! -d "/mnt/ssd" ] || [ ! -d "/mnt/hdd" ]; then
        log_error "Storage not configured. Run setup-storage.sh first."
        exit 1
    fi

    log_success "Environment validation passed"
}

# Repository setup
setup_repositories() {
    log_info "Setting up application repositories..."

    # Source repository configuration
    source "$SCRIPT_DIR/repo-config.sh"

    # Create repositories directory
    mkdir -p "$REPOS_BASE_DIR"
    cd "$REPOS_BASE_DIR"

    # Clone or update backend repository
    if [ ! -d "$BACKEND_REPO_NAME" ]; then
        log_info "Cloning backend repository..."
        git clone "$BACKEND_REPO_URL" "$BACKEND_REPO_NAME"
    else
        log_info "Updating backend repository..."
        cd "$BACKEND_REPO_NAME"
        git fetch origin
        git reset --hard "origin/$BACKEND_BRANCH"
        cd ..
    fi

    # Clone or update frontend repository
    if [ ! -d "$FRONTEND_REPO_NAME" ]; then
        log_info "Cloning frontend repository..."
        git clone "$FRONTEND_REPO_URL" "$FRONTEND_REPO_NAME"
    else
        log_info "Updating frontend repository..."
        cd "$FRONTEND_REPO_NAME"
        git fetch origin
        git reset --hard "origin/$FRONTEND_BRANCH"
        cd ..
    fi

    log_success "Repository setup completed"
}

# Docker image building
build_images() {
    log_info "Building Docker images..."

    cd "$PROJECT_ROOT/02-docker-configuration"

    # Build backend image
    log_info "Building backend image..."
    docker build -t prs-backend:latest \
        -f ../dockerfiles/Dockerfile.backend \
        "$REPOS_BASE_DIR/$BACKEND_REPO_NAME"

    # Build frontend image
    log_info "Building frontend image..."
    docker build -t prs-frontend:latest \
        -f ../dockerfiles/Dockerfile.frontend \
        "$REPOS_BASE_DIR/$FRONTEND_REPO_NAME"

    log_success "Docker images built successfully"
}

# Service deployment
deploy_services() {
    log_info "Deploying services..."

    cd "$PROJECT_ROOT/02-docker-configuration"

    # Stop existing services
    docker-compose -f docker-compose.onprem.yml down

    # Start services
    docker-compose -f docker-compose.onprem.yml up -d

    # Wait for services to be ready
    log_info "Waiting for services to start..."
    sleep 30

    log_success "Services deployed successfully"
}

# Database setup
setup_database() {
    log_info "Setting up database..."

    # Wait for PostgreSQL to be ready
    while ! docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin; do
        log_info "Waiting for PostgreSQL to be ready..."
        sleep 5
    done

    # Create tablespaces
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
        CREATE TABLESPACE IF NOT EXISTS ssd_hot LOCATION '/mnt/ssd/postgresql-hot';
        CREATE TABLESPACE IF NOT EXISTS hdd_cold LOCATION '/mnt/hdd/postgresql-cold';
    "

    # Run migrations
    docker exec prs-onprem-backend npm run migrate

    # Setup TimescaleDB
    docker exec prs-onprem-backend npm run setup:timescaledb

    log_success "Database setup completed"
}

# Health checks
health_checks() {
    log_info "Running health checks..."

    # Check service status
    docker-compose -f "$PROJECT_ROOT/02-docker-configuration/docker-compose.onprem.yml" ps

    # Test API endpoint
    if curl -f -s https://localhost/api/health > /dev/null; then
        log_success "API health check passed"
    else
        log_warning "API health check failed"
    fi

    # Test database connectivity
    if docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin; then
        log_success "Database health check passed"
    else
        log_error "Database health check failed"
        exit 1
    fi

    log_success "Health checks completed"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --force-rebuild)
            FORCE_REBUILD=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Run main function
main "$@"
```

## Environment Setup Script

### setup-env.sh

**Purpose**: Automated environment configuration and secret generation

**Usage**:
```bash
./setup-env.sh [--interactive] [--force]
```

**Key Features**:
- Generates secure passwords and secrets
- Creates environment file from template
- Validates configuration
- Interactive mode for custom settings

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/02-docker-configuration/.env"
ENV_TEMPLATE="$PROJECT_ROOT/02-docker-configuration/.env.example"

# Generate secure environment
generate_environment() {
    log_info "Generating secure environment configuration..."

    # Generate secure passwords
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    REDIS_PASSWORD=$(openssl rand -base64 32)
    JWT_SECRET=$(openssl rand -base64 32)
    ENCRYPTION_KEY=$(openssl rand -base64 32)
    OTP_KEY=$(openssl rand -base64 16)
    GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 16)

    # Copy template and replace placeholders
    cp "$ENV_TEMPLATE" "$ENV_FILE"

    # Replace generated values
    sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" "$ENV_FILE"
    sed -i "s/REDIS_PASSWORD=.*/REDIS_PASSWORD=$REDIS_PASSWORD/" "$ENV_FILE"
    sed -i "s/JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" "$ENV_FILE"
    sed -i "s/ENCRYPTION_KEY=.*/ENCRYPTION_KEY=$ENCRYPTION_KEY/" "$ENV_FILE"
    sed -i "s/OTP_KEY=.*/OTP_KEY=$OTP_KEY/" "$ENV_FILE"
    sed -i "s/GRAFANA_ADMIN_PASSWORD=.*/GRAFANA_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD/" "$ENV_FILE"

    log_success "Environment file generated: $ENV_FILE"
}

# Interactive configuration
interactive_setup() {
    echo "=== PRS Environment Setup ==="
    echo ""

    read -p "Enter domain name [your-domain.com]: " DOMAIN
    DOMAIN=${DOMAIN:-your-domain.com}

    read -p "Enter server IP [192.168.0.100]: " SERVER_IP
    SERVER_IP=${SERVER_IP:-192.168.0.100}

    read -p "Enter SSL email [admin@$DOMAIN]: " SSL_EMAIL
    SSL_EMAIL=${SSL_EMAIL:-admin@$DOMAIN}

    # Update environment file
    sed -i "s/DOMAIN=.*/DOMAIN=$DOMAIN/" "$ENV_FILE"
    sed -i "s/SERVER_IP=.*/SERVER_IP=$SERVER_IP/" "$ENV_FILE"
    sed -i "s/SSL_EMAIL=.*/SSL_EMAIL=$SSL_EMAIL/" "$ENV_FILE"

    echo ""
    echo "Configuration updated successfully!"
}
```

## Storage Setup Script

### setup-storage.sh

**Purpose**: Configure dual storage architecture (SSD/HDD)

**Usage**:
```bash
sudo ./setup-storage.sh [--verify-only]
```

**Key Features**:
- Creates storage directory structure
- Sets proper permissions
- Configures ownership for services
- Validates storage configuration

```bash
#!/bin/bash
set -e

# Storage configuration
SSD_MOUNT="/mnt/ssd"
HDD_MOUNT="/mnt/hdd"

# Create storage directories
create_directories() {
    log_info "Creating storage directory structure..."

    # SSD directories
    mkdir -p "$SSD_MOUNT"/{postgresql-hot,redis-data,uploads,logs,nginx-cache,prometheus-data,grafana-data,portainer-data}

    # HDD directories
    mkdir -p "$HDD_MOUNT"/{postgresql-cold,postgres-backups,app-logs-archive,redis-backups,prometheus-archive,config-backups}

    log_success "Storage directories created"
}

# Set permissions
set_permissions() {
    log_info "Setting storage permissions..."

    # PostgreSQL (UID 999)
    chown -R 999:999 "$SSD_MOUNT/postgresql-hot" "$HDD_MOUNT/postgresql-cold" "$HDD_MOUNT/postgres-backups"
    chmod 700 "$SSD_MOUNT/postgresql-hot" "$HDD_MOUNT/postgresql-cold"

    # Redis (UID 999)
    chown -R 999:999 "$SSD_MOUNT/redis-data" "$HDD_MOUNT/redis-backups"
    chmod 755 "$SSD_MOUNT/redis-data"

    # Grafana (UID 472)
    chown -R 472:472 "$SSD_MOUNT/grafana-data"

    # Prometheus (UID 65534)
    chown -R 65534:65534 "$SSD_MOUNT/prometheus-data" "$HDD_MOUNT/prometheus-archive"

    # Nginx/Application (UID 33 or 1000)
    chown -R www-data:www-data "$SSD_MOUNT/nginx-cache" "$SSD_MOUNT/uploads"
    chown -R 1000:1000 "$SSD_MOUNT/logs" "$HDD_MOUNT/app-logs-archive"

    # General permissions
    chmod 755 "$SSD_MOUNT"/* "$HDD_MOUNT"/*

    log_success "Permissions set successfully"
}

# Verify storage
verify_storage() {
    log_info "Verifying storage configuration..."

    # Check mount points
    if ! mountpoint -q "$SSD_MOUNT"; then
        log_warning "SSD not mounted at $SSD_MOUNT"
    fi

    if ! mountpoint -q "$HDD_MOUNT"; then
        log_warning "HDD not mounted at $HDD_MOUNT"
    fi

    # Check directory structure
    for dir in postgresql-hot redis-data uploads logs; do
        if [ ! -d "$SSD_MOUNT/$dir" ]; then
            log_error "Missing SSD directory: $dir"
            exit 1
        fi
    done

    for dir in postgresql-cold postgres-backups app-logs-archive; do
        if [ ! -d "$HDD_MOUNT/$dir" ]; then
            log_error "Missing HDD directory: $dir"
            exit 1
        fi
    done

    log_success "Storage verification passed"
}
```

## SSL Automation Script

### ssl-automation-citylandcondo.sh

**Purpose**: Automated SSL certificate management

**Usage**:
```bash
./ssl-automation-citylandcondo.sh [--force] [--staging]
```

**Key Features**:
- Let's Encrypt integration
- Certificate renewal automation
- Nginx configuration update
- Certificate validation

```bash
#!/bin/bash
set -e

DOMAIN="${DOMAIN:-your-domain.com}"
SSL_DIR="/opt/prs-deployment/02-docker-configuration/ssl"
EMAIL="${SSL_EMAIL:-admin@$DOMAIN}"

# Certificate generation
generate_certificate() {
    log_info "Generating SSL certificate for $DOMAIN..."

    # Stop nginx temporarily
    docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml stop nginx

    # Generate certificate
    certbot certonly \
        --standalone \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --domains "$DOMAIN" \
        --cert-path "$SSL_DIR/certificate.crt" \
        --key-path "$SSL_DIR/private.key" \
        --chain-path "$SSL_DIR/ca-bundle.crt"

    # Restart nginx
    docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml start nginx

    log_success "SSL certificate generated successfully"
}

# Certificate renewal
renew_certificate() {
    log_info "Renewing SSL certificate..."

    certbot renew --quiet

    # Reload nginx
    docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml exec nginx nginx -s reload

    log_success "SSL certificate renewed"
}

# Setup auto-renewal
setup_auto_renewal() {
    log_info "Setting up automatic certificate renewal..."

    # Add cron job for renewal
    (crontab -l 2>/dev/null; echo "0 3 * * * /opt/prs-deployment/scripts/ssl-automation-citylandcondo.sh --renew") | crontab -

    log_success "Auto-renewal configured"
}
```

## Health Check Script

### system-health-check.sh

**Purpose**: Comprehensive system health monitoring

**Usage**:
```bash
./system-health-check.sh [--verbose] [--json]
```

**Key Features**:
- Service status monitoring
- Resource usage checking
- Database connectivity testing
- Performance metrics collection

```bash
#!/bin/bash

# Health check functions
check_services() {
    log_info "Checking service status..."

    SERVICES=(
        "prs-onprem-nginx"
        "prs-onprem-frontend"
        "prs-onprem-backend"
        "prs-onprem-postgres-timescale"
        "prs-onprem-redis"
        "prs-onprem-grafana"
        "prs-onprem-prometheus"
    )

    for service in "${SERVICES[@]}"; do
        if docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
            log_success "✓ $service is running"
        else
            log_error "✗ $service is not running"
            HEALTH_ISSUES=$((HEALTH_ISSUES + 1))
        fi
    done
}

check_resources() {
    log_info "Checking system resources..."

    # CPU usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    if (( $(echo "$CPU_USAGE > 80" | bc -l) )); then
        log_warning "High CPU usage: ${CPU_USAGE}%"
    else
        log_success "✓ CPU usage: ${CPU_USAGE}%"
    fi

    # Memory usage
    MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')
    if (( $(echo "$MEMORY_USAGE > 85" | bc -l) )); then
        log_warning "High memory usage: ${MEMORY_USAGE}%"
    else
        log_success "✓ Memory usage: ${MEMORY_USAGE}%"
    fi

    # Storage usage
    SSD_USAGE=$(df -h /mnt/ssd | awk 'NR==2{print $5}' | cut -d'%' -f1)
    HDD_USAGE=$(df -h /mnt/hdd | awk 'NR==2{print $5}' | cut -d'%' -f1)

    if [ "$SSD_USAGE" -gt 85 ]; then
        log_warning "High SSD usage: ${SSD_USAGE}%"
    else
        log_success "✓ SSD usage: ${SSD_USAGE}%"
    fi

    if [ "$HDD_USAGE" -gt 80 ]; then
        log_warning "High HDD usage: ${HDD_USAGE}%"
    else
        log_success "✓ HDD usage: ${HDD_USAGE}%"
    fi
}

check_connectivity() {
    log_info "Checking connectivity..."

    # Database connectivity
    if docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin >/dev/null 2>&1; then
        log_success "✓ Database connectivity"
    else
        log_error "✗ Database connectivity failed"
        HEALTH_ISSUES=$((HEALTH_ISSUES + 1))
    fi

    # Redis connectivity
    if docker exec prs-onprem-redis redis-cli -a "$REDIS_PASSWORD" ping >/dev/null 2>&1; then
        log_success "✓ Redis connectivity"
    else
        log_error "✗ Redis connectivity failed"
        HEALTH_ISSUES=$((HEALTH_ISSUES + 1))
    fi

    # API endpoint
    if curl -f -s https://localhost/api/health >/dev/null 2>&1; then
        log_success "✓ API endpoint"
    else
        log_warning "API endpoint check failed"
    fi
}

# Main health check
main() {
    HEALTH_ISSUES=0

    log_info "=== PRS System Health Check ==="

    check_services
    check_resources
    check_connectivity

    if [ "$HEALTH_ISSUES" -eq 0 ]; then
        log_success "=== All health checks passed ==="
        exit 0
    else
        log_error "=== Health check failed with $HEALTH_ISSUES issues ==="
        exit 1
    fi
}

main "$@"
```

## Utility Scripts

### docker-cleanup.sh

**Purpose**: Docker system maintenance and cleanup

```bash
#!/bin/bash
# Docker cleanup utility

# Remove stopped containers
docker container prune -f

# Remove unused images
docker image prune -f

# Remove unused volumes
docker volume prune -f

# Remove unused networks
docker network prune -f

# Clean build cache
docker builder prune -f

log_success "Docker cleanup completed"
```

### log-rotation.sh

**Purpose**: Application log rotation and archival

```bash
#!/bin/bash
# Log rotation script

LOG_DIR="/mnt/ssd/logs"
ARCHIVE_DIR="/mnt/hdd/app-logs-archive"
RETENTION_DAYS=30

# Rotate and compress logs older than 1 day
find "$LOG_DIR" -name "*.log" -mtime +1 -exec gzip {} \;

# Move compressed logs older than 7 days to archive
find "$LOG_DIR" -name "*.log.gz" -mtime +7 -exec mv {} "$ARCHIVE_DIR/" \;

# Remove archived logs older than retention period
find "$ARCHIVE_DIR" -name "*.log.gz" -mtime +$RETENTION_DAYS -delete

log_success "Log rotation completed"
```

## NAS Integration for Enterprise Backup

### Overview

The PRS deployment now includes comprehensive NAS (Network Attached Storage) integration for enterprise-grade backup redundancy and disaster recovery capabilities.

### NAS Configuration

#### Quick Setup

1. **Configure NAS Settings:**
   ```bash
   # Copy NAS configuration template
   cp /opt/prs-deployment/scripts/nas-config.example.sh /opt/prs-deployment/scripts/nas-config.sh

   # Edit with your NAS details
   nano /opt/prs-deployment/scripts/nas-config.sh

   # Secure the configuration
   chmod 600 /opt/prs-deployment/scripts/nas-config.sh
   ```

2. **Test NAS Connection:**
   ```bash
   # Verify NAS connectivity and functionality
   /opt/prs-deployment/scripts/test-nas-connection.sh
   ```

3. **Enable NAS in Environment:**
   ```bash
   # Add to .env file
   echo "BACKUP_TO_NAS=true" >> /opt/prs-deployment/02-docker-configuration/.env
   echo "NAS_HOST=your-nas-hostname" >> /opt/prs-deployment/02-docker-configuration/.env
   echo "NAS_SHARE=backups" >> /opt/prs-deployment/02-docker-configuration/.env
   ```

#### Supported NAS Systems

- **Synology DSM** (CIFS/SMB)
- **QNAP QTS** (CIFS/SMB)
- **FreeNAS/TrueNAS** (NFS)
- **Windows Server** (CIFS/SMB)
- **Linux NFS** servers

#### Enterprise Features

- **Dual retention policies**: Local (30 days) + NAS (90 days)
- **Automatic mounting/unmounting** of NAS shares
- **Backup verification** and integrity checking
- **Graceful degradation** if NAS is unavailable
- **Comprehensive logging** and error handling
- **Email notifications** with NAS status

### Integration with Deployment Scripts

The following deployment scripts now include NAS integration:

- `backup-full.sh` - Database backups with NAS copy
- `backup-application-data.sh` - Application data with NAS storage
- `backup-maintenance.sh` - Comprehensive maintenance with NAS
- `daily-maintenance-automation.sh` - Automated NAS operations

### Security Considerations

- **Secure credential storage** in protected configuration files
- **Network isolation** for backup traffic
- **Encryption support** for sensitive backup data
- **Access control** with dedicated backup user accounts

---

!!! tip "Script Automation"
    All scripts can be automated using cron jobs for regular maintenance and monitoring tasks. NAS integration provides additional backup redundancy.

!!! warning "Permissions"
    Ensure scripts have proper execution permissions and are run with appropriate user privileges. Verify NAS connectivity before enabling automated backups.
