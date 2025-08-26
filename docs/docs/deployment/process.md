# Deployment Process

## Overview

This guide covers the complete deployment process for the PRS on-premises production environment, from initial setup to final validation.

## Pre-Deployment Checklist

### Validation

- [ ] **RAM**: 16GB available and recognized
- [ ] **SSD**: 470GB RAID1 mounted at `/mnt/hdd`
- [ ] **HDD**: 2.4TB RAID5 mounted at `/mnt/hdd`
- [ ] **Network**: 1 Gbps interface configured
- [ ] **UPS**: Backup power system operational
- [ ] **Firewall**: Network security configured

### Prerequisites

- [ ] **Operating System**: Ubuntu 20.04+ or CentOS 8+
- [ ] **Docker**: Version 20.10+ installed
- [ ] **Docker Compose**: Version 2.0+ installed
- [ ] **Git**: Version 2.25+ installed
- [ ] **SSL Certificates**: Valid certificates available

## Deployment Steps

### 1: Environment Preparation

#### Deployment Repository

```bash
# Clone the deployment repository
cd /opt
sudo git clone https://github.com/your-org/prs-deployment.git
sudo chown -R $USER:$USER /opt/prs-deployment
cd /opt/prs-deployment
```

#### Storage Directories

```bash
# Run storage setup script
cd scripts
sudo ./setup-storage.sh

# Verify storage structure
ls -la /mnt/hdd/
ls -la /mnt/hdd/
```

Expected output:
```
/mnt/hdd/:
├── postgresql-hot/
├── redis-data/
├── uploads/
├── logs/
├── nginx-cache/
├── prometheus-data/
└── grafana-data/

/mnt/hdd/:
├── postgresql-cold/
├── postgres-backups/
├── app-logs-archive/
└── prometheus-archive/
```

### 2: Environment Configuration

#### Environment Variables

```bash
# Copy and customize environment file
cp 02-docker-configuration/.env.example 02-docker-configuration/.env

# Edit environment variables
nano 02-docker-configuration/.env
```

Key environment variables to configure:

```bash
# Domain and Network
DOMAIN=your-domain.com
SERVER_IP=192.168.0.100
NETWORK_SUBNET=192.168.0.0/20

# Database Configuration
POSTGRES_DB=prs_production
POSTGRES_USER=prs_admin
POSTGRES_PASSWORD=secure_password_here

# Application Secrets
JWT_SECRET=your_jwt_secret_here
ENCRYPTION_KEY=your_encryption_key_here
OTP_KEY=your_otp_key_here

# External API Integration
CITYLAND_API_URL=https://your-api-endpoint.com
CITYLAND_API_USERNAME=api_username
CITYLAND_API_PASSWORD=api_password

# SSL Configuration
SSL_EMAIL=admin@your-domain.com
```

#### Repository Paths

```bash
# Setup repository configuration
cp scripts/repo-config.example.sh scripts/repo-config.sh
nano scripts/repo-config.sh
```

Update repository paths:
```bash
# Repository configuration
export REPOS_BASE_DIR="/opt/prs"
export BACKEND_REPO_NAME="prs-backend-a"
export FRONTEND_REPO_NAME="prs-frontend-a"
export BACKEND_REPO_URL="https://github.com/your-org/prs-backend-a.git"
export FRONTEND_REPO_URL="https://github.com/your-org/prs-frontend-a.git"
```

### 3: Application Deployment

#### Deployment Script

```bash
# Make deployment script executable
chmod +x scripts/deploy-onprem.sh

# Run deployment for production environment
./scripts/deploy-onprem.sh prod
```

The deployment script will:

1. **Validate Environment**: Check prerequisites and configuration
2. **Clone Repositories**: Download application source code
3. **Build Images**: Create Docker images for all services
4. **Setup Database**: Initialize TimescaleDB with proper configuration
5. **Start Services**: Launch all application services
6. **Configure SSL**: Setup SSL certificates and HTTPS
7. **Run Health Checks**: Validate deployment success

#### Deployment Progress

```bash
# Watch deployment logs
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml logs -f

# Check service status
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml ps
```

### 4: Database Initialization

#### Setup

```bash
# Connect to database
docker exec -it prs-onprem-postgres-timescale psql -U prs_admin -d prs_production

# Create tablespaces for HDD-only storage
-- Tablespace creation not needed (HDD-only)
-- Tablespace creation not needed (HDD-only)

# Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

# Configure telemetry
ALTER SYSTEM SET timescaledb.telemetry = 'off';
SELECT pg_reload_conf();
```

#### Database Migrations

```bash
# Access backend container
docker exec -it prs-onprem-backend bash

# Run database migrations
npm run migrate

# Setup TimescaleDB hypertables and compression
npm run setup:timescaledb
```

### 5: SSL Configuration

#### SSL Setup

```bash
# Run SSL automation script
./scripts/ssl-automation-citylandcondo.sh
```

#### SSL Configuration (if needed)

```bash
# Copy SSL certificates to proper location
sudo cp /path/to/your/certificate.crt 02-docker-configuration/ssl/
sudo cp /path/to/your/private.key 02-docker-configuration/ssl/
sudo cp /path/to/your/ca-bundle.crt 02-docker-configuration/ssl/

# Update nginx configuration
nano 02-docker-configuration/nginx/sites-enabled/default.conf
```

### 6: Service Validation

#### Check Script

```bash
# Run comprehensive health checks
./scripts/system-health-check.sh
```

#### Service Verification

```bash
# Check all services are running
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml ps

# Test database connectivity
docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin

# Test Redis connectivity
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD ping

# Test application endpoints
curl -k https://your-domain.com/api/health
curl -k https://your-domain.com/
```

## Deployment Validation

### Testing

#### Testing

```bash
# Install testing tools
sudo apt install apache2-utils

# Test concurrent connections
ab -n 1000 -c 10 https://your-domain.com/

# Test API endpoints
ab -n 500 -c 5 https://your-domain.com/api/health
```

#### Performance

```sql
-- Test query performance
EXPLAIN ANALYZE SELECT COUNT(*) FROM notifications 
WHERE created_at >= NOW() - INTERVAL '30 days';

-- Check TimescaleDB status
SELECT * FROM timescaledb_information.hypertables;

-- Verify compression policies
SELECT * FROM timescaledb_information.compression_settings;
```

### Validation

#### Certificate Verification

```bash
# Check SSL certificate
openssl s_client -connect your-domain.com:443 -servername your-domain.com

# Verify certificate chain
curl -vI https://your-domain.com/
```

#### Scan

```bash
# Run security hardening check
./scripts/security-hardening-check.sh

# Check open ports
sudo netstat -tulpn | grep LISTEN
```

## Post-Deployment Configuration

### Setup

#### Grafana

1. Access Grafana at `https://your-domain.com:3001`
2. Login with admin credentials
3. Import PRS dashboards from `02-docker-configuration/config/grafana/dashboards/`
4. Configure data sources for Prometheus and TimescaleDB

#### Alerting

```bash
# Configure alert rules
cp 02-docker-configuration/config/prometheus/alerts.yml.example \
   02-docker-configuration/config/prometheus/alerts.yml

# Restart Prometheus to load alerts
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart prometheus
```

### Configuration

#### Automated Backups

```bash
# Configure backup script
cp scripts/backup-maintenance.sh.example scripts/backup-maintenance.sh
chmod +x scripts/backup-maintenance.sh

# Add to crontab for daily execution
echo "0 2 * * * /opt/prs-deployment/scripts/backup-maintenance.sh" | sudo crontab -
```

#### Backup and Restore

```bash
# Run manual backup
./scripts/backup-maintenance.sh

# Verify backup files
ls -la /mnt/hdd/postgres-backups/
ls -la /mnt/hdd/app-logs-archive/
```

## Troubleshooting

### Issues

#### Startup Failures

```bash
# Check service logs
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml logs service-name

# Restart specific service
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart service-name
```

#### Connection Issues

```bash
# Check database status
docker exec prs-onprem-postgres-timescale pg_isready

# Check database logs
docker logs prs-onprem-postgres-timescale

# Test connection from backend
docker exec prs-onprem-backend npm run db:test
```

#### Certificate Issues

```bash
# Regenerate SSL certificates
./scripts/ssl-automation-citylandcondo.sh --force

# Check certificate validity
openssl x509 -in 02-docker-configuration/ssl/certificate.crt -text -noout
```

### Procedures

#### Recovery

```bash
# Stop all services
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml down

# Clean up containers and volumes (if needed)
docker system prune -f

# Restart deployment
./scripts/deploy-onprem.sh prod
```

#### Recovery

```bash
# Restore from backup
./scripts/restore-database.sh /mnt/hdd/postgres-backups/latest-backup.sql

# Verify data integrity
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "SELECT COUNT(*) FROM notifications;"
```

## Deployment Success Criteria

### Validation

- [ ] All services running and healthy
- [ ] Database accessible and optimized
- [ ] SSL certificates valid and configured
- [ ] Monitoring and alerting operational
- [ ] Backup procedures tested and working

### Validation

- [ ] Response time <200ms for 95% of requests
- [ ] Support for 100+ concurrent users
- [ ] Database queries optimized for HDD-only storage
- [ ] Storage tiers functioning correctly

### Validation

- [ ] SSL/TLS encryption enabled
- [ ] Firewall rules configured
- [ ] Security hardening applied
- [ ] Access controls implemented

---

!!! success "Deployment Complete"
    Once all validation steps pass, your PRS on-premises deployment is ready for production use.

!!! tip "Next Steps"
    Proceed to [Testing & Validation](testing.md) for comprehensive system testing procedures.
