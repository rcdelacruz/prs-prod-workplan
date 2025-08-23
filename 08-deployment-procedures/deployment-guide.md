# 🚀 Deployment Procedures for On-Premises Production

## 🎯 Overview

This document provides step-by-step deployment procedures for the PRS on-premises production environment, adapted from the EC2 Graviton setup to work optimally with the client's infrastructure.

## 📋 Pre-Deployment Checklist

### Infrastructure Requirements
- [ ] Ubuntu 24.04 LTS installed and updated
- [ ] 16GB RAM available and recognized
- [ ] SSD (470GB) mounted at `/mnt/ssd` with RAID1
- [ ] HDD (2.4TB) mounted at `/mnt/hdd` with RAID5
- [ ] Network connectivity to 192.168.0.0/20
- [ ] Static IP 192.168.0.100 assigned
- [ ] Hardware firewall rules configured by IT team
- [ ] UPS backup power tested and functional

### Software Requirements
- [ ] Docker Engine 24.0+ installed
- [ ] Docker Compose v2 installed
- [ ] Git installed
- [ ] UFW firewall installed
- [ ] Certbot for SSL certificates
- [ ] Basic monitoring tools (htop, iotop, nethogs)

### Network Requirements
- [ ] DNS resolution for prs.client-domain.com
- [ ] Firewall ports opened (80, 443, 8080, 3001, 9000, 9090)
- [ ] SSH access from IT network (192.168.1.0/24)
- [ ] Internet access for package downloads and updates

## 🔧 Phase 1: System Preparation

### Step 1.1: System Updates
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y curl wget git htop iotop nethogs tree unzip

# Reboot if kernel was updated
sudo reboot
```

### Step 1.2: Storage Setup
```bash
# Verify storage mounts
df -h | grep -E "(ssd|hdd)"

# Check mount options
mount | grep -E "(ssd|hdd)"

# Ensure proper permissions
sudo chown -R $USER:$USER /mnt/ssd /mnt/hdd
chmod -R 755 /mnt/ssd /mnt/hdd
```

### Step 1.3: Network Configuration
```bash
# Verify network configuration
ip addr show
ip route show

# Test connectivity
ping -c 4 8.8.8.8
ping -c 4 192.168.1.1

# Check DNS resolution
nslookup prs.client-domain.com
```

## 🐳 Phase 2: Docker Installation

### Step 2.1: Install Docker
```bash
# Run the setup script
cd /opt/prs/prod-workplan/06-installation-scripts
chmod +x setup-onprem.sh
./setup-onprem.sh docker

# Verify Docker installation
docker --version
docker compose version

# Test Docker
docker run hello-world
```

### Step 2.2: Configure Docker
```bash
# Create Docker daemon configuration
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

# Restart Docker
sudo systemctl restart docker
```

## 📁 Phase 3: Application Setup

### Step 3.1: Clone Repositories
```bash
# Create project directory
sudo mkdir -p /opt/prs
sudo chown $USER:$USER /opt/prs

# Clone repositories
cd /opt/prs
git clone https://github.com/rcdelacruz/prs-backend-a.git
git clone https://github.com/rcdelacruz/prs-frontend-a.git

# Copy workplan to deployment location
cp -r /path/to/prod-workplan /opt/prs/
```

### Step 3.2: Environment Configuration
```bash
# Copy environment file
cd /opt/prs/prod-workplan/02-docker-configuration
cp .env.onprem.example .env

# Edit environment file
nano .env

# Generate secure passwords and secrets
openssl rand -base64 32  # For JWT_SECRET
openssl rand -base64 32  # For ENCRYPTION_KEY
openssl rand -base64 16  # For OTP_KEY
openssl rand -base64 32  # For PASS_SECRET
openssl rand -base64 32  # For REDIS_PASSWORD
```

### Step 3.3: SSL Certificate Setup
```bash
# Install Certbot
sudo apt install -y certbot

# Generate SSL certificate (replace with actual domain)
sudo certbot certonly --standalone \
  -d prs.client-domain.com \
  --email admin@client-domain.com \
  --agree-tos \
  --non-interactive

# Copy certificates to project
sudo cp /etc/letsencrypt/live/prs.client-domain.com/fullchain.pem /opt/prs/prod-workplan/02-docker-configuration/ssl/server.crt
sudo cp /etc/letsencrypt/live/prs.client-domain.com/privkey.pem /opt/prs/prod-workplan/02-docker-configuration/ssl/server.key

# Set permissions
chmod 644 /opt/prs/prod-workplan/02-docker-configuration/ssl/server.crt
chmod 600 /opt/prs/prod-workplan/02-docker-configuration/ssl/server.key
```

## 🔒 Phase 4: Security Configuration

### Step 4.1: Firewall Setup
```bash
# Run firewall configuration
cd /opt/prs/prod-workplan/06-installation-scripts
./setup-onprem.sh firewall

# Verify firewall status
sudo ufw status verbose
```

### Step 4.2: System Hardening
```bash
# Apply system optimizations
sudo tee /etc/sysctl.d/99-prs-optimization.conf > /dev/null <<EOF
# Network optimization
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr

# File system optimization
fs.file-max = 2097152
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

# Apply settings
sudo sysctl -p /etc/sysctl.d/99-prs-optimization.conf
```

## 🚀 Phase 5: Application Deployment

### Step 5.1: Build Images
```bash
cd /opt/prs/prod-workplan/02-docker-configuration

# Build backend image
docker build -t prs-backend:latest /opt/prs/prs-backend-a

# Build frontend image
docker build -t prs-frontend:latest /opt/prs/prs-frontend-a

# Verify images
docker images | grep prs
```

### Step 5.2: Start Services
```bash
# Start infrastructure services first
docker compose -f docker-compose.onprem.yml up -d postgres redis

# Wait for database to be ready
sleep 30

# Start application services
docker compose -f docker-compose.onprem.yml up -d backend redis-worker

# Wait for backend to be ready
sleep 30

# Start web services
docker compose -f docker-compose.onprem.yml up -d frontend nginx

# Start monitoring services
docker compose -f docker-compose.onprem.yml --profile monitoring up -d

# Verify all services are running
docker compose -f docker-compose.onprem.yml ps
```

### Step 5.3: Database Initialization
```bash
# Run database migrations
docker exec prs-onprem-backend npm run migrate

# Create initial admin user
docker exec prs-onprem-backend npm run seed:admin

# Verify database setup
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "\dt"
```

## 🔍 Phase 6: Verification and Testing

### Step 6.1: Health Checks
```bash
# Check service health
curl -f http://192.168.0.100/health
curl -f https://192.168.0.100/health

# Check API endpoints
curl -f http://192.168.0.100/api/health
curl -f https://192.168.0.100/api/health

# Check monitoring endpoints
curl -f http://192.168.0.100:9090/-/healthy  # Prometheus
curl -f http://192.168.0.100:3001/api/health  # Grafana
```

### Step 6.2: Performance Testing
```bash
# Test database performance
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "SELECT version();"

# Test Redis performance
docker exec prs-onprem-redis redis-cli --latency-history -i 1

# Test application response time
curl -w "@curl-format.txt" -o /dev/null -s https://192.168.0.100/
```

### Step 6.3: Load Testing
```bash
# Install Apache Bench for basic load testing
sudo apt install -y apache2-utils

# Test with 10 concurrent users
ab -n 100 -c 10 https://192.168.0.100/

# Test API endpoints
ab -n 100 -c 10 https://192.168.0.100/api/health
```

## 📊 Phase 7: Monitoring Setup

### Step 7.1: Configure Monitoring
```bash
# Access Grafana
open http://192.168.0.100:3001
# Login with admin credentials from .env file

# Import dashboards
# - System Overview Dashboard
# - Application Performance Dashboard
# - Database Performance Dashboard

# Configure alerts
# - High CPU usage
# - High memory usage
# - Storage space warnings
# - Application errors
```

### Step 7.2: Set Up Backup Jobs
```bash
# Create backup scripts directory
sudo mkdir -p /opt/prs/backup-scripts

# Copy backup scripts
cp /opt/prs/prod-workplan/04-backup-strategy/scripts/* /opt/prs/backup-scripts/

# Make scripts executable
chmod +x /opt/prs/backup-scripts/*.sh

# Set up cron jobs
crontab -e
# Add:
# 0 2 * * * /opt/prs/backup-scripts/daily-backup.sh
# 0 1 * * 0 /opt/prs/backup-scripts/weekly-backup.sh
# 0 0 1 * * /opt/prs/backup-scripts/monthly-backup.sh
```

## 🎯 Phase 8: Go-Live Procedures

### Step 8.1: Final Verification
```bash
# Run comprehensive health check
/opt/prs/scripts/health-check.sh

# Verify all services are accessible
curl -f https://192.168.0.100/
curl -f https://192.168.0.100/api/health
curl -f http://192.168.0.100:8080/  # Adminer
curl -f http://192.168.0.100:3001/  # Grafana
curl -f http://192.168.0.100:9000/  # Portainer
```

### Step 8.2: User Acceptance Testing
- [ ] Admin user can log in successfully
- [ ] All main features are functional
- [ ] File uploads work correctly
- [ ] Reports generate successfully
- [ ] Performance meets requirements (< 200ms response time)

### Step 8.3: Documentation Handover
- [ ] Provide access credentials to IT team
- [ ] Share monitoring dashboard URLs
- [ ] Document backup and recovery procedures
- [ ] Provide troubleshooting guide
- [ ] Schedule training session for IT team

## 🚨 Rollback Procedures

### Emergency Rollback
```bash
# Stop all services
docker compose -f docker-compose.onprem.yml down

# Restore from backup if needed
/opt/prs/backup-scripts/restore-backup.sh

# Start services with previous configuration
docker compose -f docker-compose.onprem.yml.backup up -d
```

## 📞 Post-Deployment Support

### Monitoring Checklist (First 24 Hours)
- [ ] Monitor CPU and memory usage
- [ ] Check error logs every 2 hours
- [ ] Verify backup jobs complete successfully
- [ ] Monitor user activity and performance
- [ ] Check SSL certificate validity

### Weekly Follow-up Tasks
- [ ] Review performance metrics
- [ ] Check storage usage trends
- [ ] Verify backup integrity
- [ ] Update security patches
- [ ] Generate performance report

---

**Document Version**: 1.0
**Created**: 2025-08-13
**Last Updated**: 2025-08-13
**Status**: Production Ready
