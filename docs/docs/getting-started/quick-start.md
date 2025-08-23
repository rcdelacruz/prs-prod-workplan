# Quick Start Guide

## Rapid Deployment (30 Minutes)

This guide will get your PRS system running in production in approximately 30 minutes, assuming all [prerequisites](prerequisites.md) are met.

## Step 1: Environment Setup (5 minutes)

### Repository

```bash
# Navigate to deployment directory
cd /opt

# Clone the deployment repository
sudo git clone https://github.com/your-org/prs-deployment.git
sudo chown -R $USER:$USER /opt/prs-deployment
cd /opt/prs-deployment
```

### Storage

```bash
# Run automated storage setup
cd scripts
sudo ./setup-storage.sh

# Verify storage structure
ls -la /mnt/ssd/
ls -la /mnt/hdd/
```

Expected output:
```
/mnt/ssd/:
├── postgresql-hot/
├── redis-data/
├── uploads/
├── logs/
└── nginx-cache/

/mnt/hdd/:
├── postgresql-cold/
├── postgres-backups/
└── app-logs-archive/
```

## Step 2: Configuration (10 minutes)

### Variables

```bash
# Copy environment template
cp 02-docker-configuration/.env.example 02-docker-configuration/.env

# Edit configuration (use your preferred editor)
nano 02-docker-configuration/.env
```

**Essential Configuration:**
```bash
# Domain Configuration
DOMAIN=your-domain.com
SERVER_IP=192.168.0.100

# Database Configuration
POSTGRES_DB=prs_production
POSTGRES_USER=prs_admin
POSTGRES_PASSWORD=your_secure_password_here

# Application Secrets (generate secure values)
JWT_SECRET=your_jwt_secret_32_chars_minimum
ENCRYPTION_KEY=your_encryption_key_32_chars
OTP_KEY=your_otp_key_base64_encoded

# Redis Configuration
REDIS_PASSWORD=your_redis_password_here

# External API (configure for your environment)
CITYLAND_API_URL=https://your-api-endpoint.com
CITYLAND_API_USERNAME=your_api_username
CITYLAND_API_PASSWORD=your_api_password

# SSL Configuration
SSL_EMAIL=admin@your-domain.com
```

### Configuration

```bash
# Setup repository paths
cp scripts/repo-config.example.sh scripts/repo-config.sh
nano scripts/repo-config.sh
```

Update with your repository URLs:
```bash
export REPOS_BASE_DIR="/opt/prs"
export BACKEND_REPO_NAME="prs-backend-a"
export FRONTEND_REPO_NAME="prs-frontend-a"
export BACKEND_REPO_URL="https://github.com/your-org/prs-backend-a.git"
export FRONTEND_REPO_URL="https://github.com/your-org/prs-frontend-a.git"
```

## Step 3: Deployment (10 minutes)

### Deployment Script

```bash
# Make script executable
chmod +x scripts/deploy-onprem.sh

# Deploy production environment
./scripts/deploy-onprem.sh prod
```

The script will automatically:

1. Validate environment and prerequisites
2. Clone application repositories
3. Build Docker images
4. Setup TimescaleDB with dual storage
5. Configure SSL certificates
6. Start all services
7. Run health checks

### Deployment

```bash
# Watch deployment progress
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml logs -f

# Check service status
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml ps
```

Expected services:
```
NAME                          STATUS
prs-onprem-nginx             Up
prs-onprem-frontend          Up  
prs-onprem-backend           Up
prs-onprem-postgres-timescale Up (healthy)
prs-onprem-redis             Up (healthy)
prs-onprem-redis-worker      Up
prs-onprem-adminer           Up
prs-onprem-prometheus        Up
prs-onprem-grafana           Up
```

## Step 4: Validation (5 minutes)

### Checks

```bash
# Run comprehensive health check
./scripts/system-health-check.sh
```

### Verification

```bash
# Test web interface
curl -k https://your-domain.com/

# Test API health
curl -k https://your-domain.com/api/health

# Test database connectivity
docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin

# Test Redis connectivity
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD ping
```

### Management Interfaces

| Service | URL | Purpose |
|---------|-----|---------|
| **Main Application** | `https://your-domain.com` | PRS web interface |
| **Database Admin** | `https://your-domain.com:8080` | Adminer database management |
| **Monitoring** | `https://your-domain.com:3001` | Grafana dashboards |
| **Container Management** | `https://your-domain.com:9000` | Portainer interface |
| **Metrics** | `https://your-domain.com:9090` | Prometheus metrics |

## Post-Deployment Setup

### Initialization

```bash
# Access backend container
docker exec -it prs-onprem-backend bash

# Run database migrations
npm run migrate

# Setup TimescaleDB hypertables
npm run setup:timescaledb

# Create initial admin user
npm run create:admin
```

### Monitoring

```bash
# Import Grafana dashboards
docker exec -it prs-onprem-grafana grafana-cli admin reset-admin-password admin

# Access Grafana at https://your-domain.com:3001
# Login: admin / admin (change on first login)
```

### Automated Backups

```bash
# Configure backup script
cp scripts/backup-maintenance.sh.example scripts/backup-maintenance.sh
chmod +x scripts/backup-maintenance.sh

# Test backup
./scripts/backup-maintenance.sh

# Add to crontab for daily execution
echo "0 2 * * * /opt/prs-deployment/scripts/backup-maintenance.sh" | crontab -
```

## Quick Configuration

### Certificate Setup

**Option 1: Automatic (Let's Encrypt)**
```bash
# Run SSL automation
./scripts/ssl-automation-citylandcondo.sh
```

**Option 2: Manual (Existing Certificates)**
```bash
# Copy certificates to SSL directory
sudo cp /path/to/certificate.crt 02-docker-configuration/ssl/
sudo cp /path/to/private.key 02-docker-configuration/ssl/
sudo cp /path/to/ca-bundle.crt 02-docker-configuration/ssl/

# Restart nginx to load certificates
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart nginx
```

### Tuning

```bash
# Optimize PostgreSQL for your workload
docker exec -it prs-onprem-postgres-timescale psql -U prs_admin -d prs_production

-- Create tablespaces for dual storage
CREATE TABLESPACE ssd_hot LOCATION '/mnt/ssd/postgresql-hot';
CREATE TABLESPACE hdd_cold LOCATION '/mnt/hdd/postgresql-cold';

-- Setup data movement policies
SELECT add_move_chunk_policy('notifications', INTERVAL '30 days', 'hdd_cold');
SELECT add_move_chunk_policy('audit_logs', INTERVAL '30 days', 'hdd_cold');
```

## Troubleshooting Quick Fixes

### Won't Start

```bash
# Check service logs
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml logs service-name

# Restart specific service
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart service-name

# Restart all services
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart
```

### Connection Issues

```bash
# Check database status
docker exec prs-onprem-postgres-timescale pg_isready

# Reset database connection
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart postgres backend
```

### Certificate Issues

```bash
# Check certificate validity
openssl x509 -in 02-docker-configuration/ssl/certificate.crt -text -noout

# Regenerate certificates
./scripts/ssl-automation-citylandcondo.sh --force
```

### Issues

```bash
# Check storage usage
df -h /mnt/ssd /mnt/hdd

# Check storage permissions
ls -la /mnt/ssd/ /mnt/hdd/

# Fix permissions if needed
sudo chown -R 999:999 /mnt/ssd/postgresql-hot /mnt/hdd/postgresql-cold
```

## Success Validation

### Benchmarks

```bash
# Test application performance
ab -n 100 -c 10 https://your-domain.com/

# Test API performance
ab -n 100 -c 5 https://your-domain.com/api/health

# Test database performance
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT COUNT(*) FROM notifications WHERE created_at >= NOW() - INTERVAL '30 days';
"
```

### Results

| Metric | Target | Validation |
|--------|--------|------------|
| **Web Response** | <200ms | Fast page loads |
| **API Response** | <100ms | Quick API calls |
| **Database Query** | <50ms | Optimized queries |
| **SSL Certificate** | Valid | HTTPS working |
| **All Services** | Running | No failed containers |

## Deployment Complete!

Your PRS system is now running in production with:

- **Dual Storage**: SSD for performance, HDD for capacity
- **TimescaleDB**: Zero-deletion policy with automatic tiering
- **SSL Security**: HTTPS encryption enabled
- **Monitoring**: Grafana dashboards and Prometheus metrics
- **Automated Backups**: Daily backup procedures
- **High Performance**: Optimized for 100+ concurrent users

## Next Steps

1. **[Configure Monitoring](../configuration/monitoring.md)** - Setup alerts and dashboards
2. **[Security Hardening](../configuration/security.md)** - Additional security measures
3. **[Backup Procedures](../operations/backup.md)** - Comprehensive backup strategy
4. **[Daily Operations](../operations/daily.md)** - Routine maintenance tasks

---

!!! success "Production Ready"
    Your PRS system is now ready for production use with enterprise-grade performance and reliability.

!!! tip "Support"
    For additional help, see [Troubleshooting](../deployment/troubleshooting.md) or [Support](../appendix/support.md).
