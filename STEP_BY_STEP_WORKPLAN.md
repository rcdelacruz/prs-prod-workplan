# 📋 PRS On-Premises Deployment - Step-by-Step Workplan

## 🎯 **OVERVIEW**
This is a detailed, step-by-step workplan for deploying PRS from EC2 to on-premises infrastructure. Each step has clear deliverables, validation criteria, and estimated time.

---

## 📅 **PHASE 1: PRE-DEPLOYMENT PREPARATION (Week 1)**

### **Day 1: Infrastructure Assessment**
**Time Estimate: 4 hours**

#### Step 1.1: Hardware Verification
- [ ] **Task**: Verify 16GB RAM is available and recognized
- [ ] **Command**: `free -h` and `cat /proc/meminfo`
- [ ] **Expected**: Total memory shows ~16GB
- [ ] **Deliverable**: Hardware specification document

#### Step 1.2: Storage Verification
- [ ] **Task**: Verify SSD (470GB) mounted at `/mnt/ssd`
- [ ] **Command**: `df -h /mnt/ssd` and `lsblk`
- [ ] **Expected**: 470GB available space, RAID1 configuration
- [ ] **Deliverable**: Storage configuration confirmed

#### Step 1.3: Network Verification
- [ ] **Task**: Verify server IP 192.168.0.100 is assigned
- [ ] **Command**: `ip addr show` and `ping 192.168.1.1`
- [ ] **Expected**: Static IP assigned, internal network accessible
- [ ] **Deliverable**: Network configuration document

### **Day 2: System Preparation**
**Time Estimate: 6 hours**

#### Step 2.1: Ubuntu System Update
- [ ] **Task**: Update Ubuntu 24.04 LTS to latest packages
- [ ] **Commands**:
  ```bash
  sudo apt update && sudo apt upgrade -y
  sudo apt install -y curl wget git htop iotop nethogs tree unzip
  ```
- [ ] **Expected**: All packages updated, essential tools installed
- [ ] **Deliverable**: Updated system ready for Docker

#### Step 2.2: Docker Installation
- [ ] **Task**: Install Docker Engine and Docker Compose
- [ ] **Script**: Run `setup-onprem.sh docker`
- [ ] **Validation**: `docker --version` and `docker compose version`
- [ ] **Expected**: Docker 24.0+ and Compose v2 installed
- [ ] **Deliverable**: Docker environment ready

#### Step 2.3: Storage Directory Setup
- [ ] **Task**: Create all required storage directories
- [ ] **Commands**:
  ```bash
  sudo mkdir -p /mnt/ssd/{postgresql-data,redis-data,uploads,logs,nginx-cache}
  sudo mkdir -p /mnt/hdd/{postgresql-cold,backups,archives,logs-archive}
  sudo chown -R $USER:$USER /mnt/ssd /mnt/hdd
  ```
- [ ] **Expected**: All directories created with correct permissions
- [ ] **Deliverable**: Storage structure ready

### **Day 3: Security Setup**
**Time Estimate: 4 hours**

#### Step 3.1: Firewall Configuration
- [ ] **Task**: Configure UFW firewall for internal network
- [ ] **Script**: Run `setup-onprem.sh firewall`
- [ ] **Validation**: `sudo ufw status verbose`
- [ ] **Expected**: Firewall active with correct rules
- [ ] **Deliverable**: Firewall configured and active

#### Step 3.2: SSL Certificate Setup
- [ ] **Task**: Generate SSL certificates for HTTPS
- [ ] **Commands**:
  ```bash
  sudo apt install -y certbot
  # Generate self-signed cert for initial setup
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /opt/prs/ssl/server.key \
    -out /opt/prs/ssl/server.crt
  ```
- [ ] **Expected**: SSL certificates generated and accessible
- [ ] **Deliverable**: SSL certificates ready for Docker

---

## 🐳 **PHASE 2: APPLICATION DEPLOYMENT (Week 2)**

### **Day 4: Repository Setup**
**Time Estimate: 3 hours**

#### Step 4.1: Clone Application Repositories
- [ ] **Task**: Clone backend and frontend repositories
- [ ] **Commands**:
  ```bash
  sudo mkdir -p /opt/prs
  sudo chown $USER:$USER /opt/prs
  cd /opt/prs
  git clone https://github.com/rcdelacruz/prs-backend-a.git
  git clone https://github.com/rcdelacruz/prs-frontend-a.git
  ```
- [ ] **Expected**: Both repositories cloned successfully
- [ ] **Deliverable**: Source code available locally

#### Step 4.2: Copy Workplan Configuration
- [ ] **Task**: Copy prod-workplan to deployment location
- [ ] **Command**: `cp -r prod-workplan /opt/prs/`
- [ ] **Expected**: All configuration files available
- [ ] **Deliverable**: Configuration files in place

### **Day 5: Environment Configuration**
**Time Estimate: 6 hours**

#### Step 5.1: Environment File Setup
- [ ] **Task**: Create production environment file
- [ ] **Commands**:
  ```bash
  cd /opt/prs/prod-workplan/02-docker-configuration
  cp .env.onprem.example .env
  ```
- [ ] **Expected**: Environment file created
- [ ] **Deliverable**: Base environment file ready

#### Step 5.2: Generate Secure Secrets
- [ ] **Task**: Generate all required passwords and secrets
- [ ] **Commands**:
  ```bash
  # Generate secure passwords
  openssl rand -base64 32  # For JWT_SECRET
  openssl rand -base64 32  # For ENCRYPTION_KEY
  openssl rand -base64 16  # For OTP_KEY
  openssl rand -base64 32  # For PASS_SECRET
  openssl rand -base64 32  # For REDIS_PASSWORD
  openssl rand -base64 32  # For POSTGRES_PASSWORD
  openssl rand -base64 32  # For GRAFANA_ADMIN_PASSWORD
  ```
- [ ] **Expected**: 7 unique secure passwords generated
- [ ] **Deliverable**: Secure secrets ready for configuration

#### Step 5.3: Update Environment Variables
- [ ] **Task**: Update .env file with generated secrets and client-specific settings
- [ ] **Required Updates**:
  - [ ] All passwords (7 generated secrets)
  - [ ] DOMAIN=prs.client-domain.com
  - [ ] SERVER_IP=192.168.0.100
  - [ ] ROOT_USER_EMAIL=admin@client-domain.com
  - [ ] SMTP settings (if email alerts needed)
- [ ] **Expected**: All variables configured correctly
- [ ] **Deliverable**: Production-ready .env file

### **Day 6: Docker Image Building**
**Time Estimate: 4 hours**

#### Step 6.1: Build Backend Image
- [ ] **Task**: Build production backend Docker image
- [ ] **Command**: `docker build -t prs-backend:latest /opt/prs/prs-backend-a`
- [ ] **Expected**: Backend image built successfully
- [ ] **Validation**: `docker images | grep prs-backend`
- [ ] **Deliverable**: Backend Docker image ready

#### Step 6.2: Build Frontend Image
- [ ] **Task**: Build production frontend Docker image
- [ ] **Command**: `docker build -t prs-frontend:latest /opt/prs/prs-frontend-a`
- [ ] **Expected**: Frontend image built successfully
- [ ] **Validation**: `docker images | grep prs-frontend`
- [ ] **Deliverable**: Frontend Docker image ready

---

## 🚀 **PHASE 3: SERVICE DEPLOYMENT (Week 3)**

### **Day 7: Database Deployment**
**Time Estimate: 6 hours**

#### Step 7.1: Start PostgreSQL + TimescaleDB
- [ ] **Task**: Deploy database service
- [ ] **Command**:
  ```bash
  cd /opt/prs/prod-workplan/02-docker-configuration
  docker compose -f docker-compose.onprem.yml up -d postgres
  ```
- [ ] **Expected**: PostgreSQL container running
- [ ] **Validation**: `docker ps | grep postgres`
- [ ] **Deliverable**: Database service running

#### Step 7.2: Verify Database Connectivity
- [ ] **Task**: Test database connection
- [ ] **Command**:
  ```bash
  docker exec prs-onprem-postgres-timescale pg_isready -U prs_user
  ```
- [ ] **Expected**: Database accepting connections
- [ ] **Deliverable**: Database connectivity confirmed

#### Step 7.3: Initialize TimescaleDB
- [ ] **Task**: Create TimescaleDB extension and configure
- [ ] **Commands**:
  ```bash
  docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
  docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "SELECT timescaledb_version();"
  ```
- [ ] **Expected**: TimescaleDB extension active
- [ ] **Deliverable**: TimescaleDB ready for use

### **Day 8: Application Services Deployment**
**Time Estimate: 6 hours**

#### Step 8.1: Start Redis Service
- [ ] **Task**: Deploy Redis cache service
- [ ] **Command**: `docker compose -f docker-compose.onprem.yml up -d redis`
- [ ] **Expected**: Redis container running
- [ ] **Validation**: `docker exec prs-onprem-redis redis-cli ping`
- [ ] **Deliverable**: Redis service operational

#### Step 8.2: Start Backend API
- [ ] **Task**: Deploy backend application
- [ ] **Command**: `docker compose -f docker-compose.onprem.yml up -d backend`
- [ ] **Expected**: Backend container running
- [ ] **Validation**: `curl -f http://localhost:4000/health`
- [ ] **Deliverable**: Backend API responding

#### Step 8.3: Start Frontend Application
- [ ] **Task**: Deploy frontend application
- [ ] **Command**: `docker compose -f docker-compose.onprem.yml up -d frontend`
- [ ] **Expected**: Frontend container running
- [ ] **Validation**: `curl -f http://localhost:80`
- [ ] **Deliverable**: Frontend application serving

### **Day 9: Web Server and Monitoring**
**Time Estimate: 6 hours**

#### Step 9.1: Start Nginx Reverse Proxy
- [ ] **Task**: Deploy Nginx with SSL termination
- [ ] **Command**: `docker compose -f docker-compose.onprem.yml up -d nginx`
- [ ] **Expected**: Nginx container running
- [ ] **Validation**: `curl -f https://192.168.0.100/`
- [ ] **Deliverable**: HTTPS access working

#### Step 9.2: Start Monitoring Services
- [ ] **Task**: Deploy Prometheus and Grafana
- [ ] **Command**: `docker compose -f docker-compose.onprem.yml --profile monitoring up -d`
- [ ] **Expected**: Monitoring containers running
- [ ] **Validation**:
  - `curl -f http://192.168.0.100:9090` (Prometheus)
  - `curl -f http://192.168.0.100:3001` (Grafana)
- [ ] **Deliverable**: Monitoring stack operational

---

## ✅ **PHASE 4: VALIDATION AND GO-LIVE (Week 4)**

### **Day 10: System Validation**
**Time Estimate: 8 hours**

#### Step 10.1: Run Health Check
- [ ] **Task**: Execute comprehensive health check
- [ ] **Command**: `/opt/prs/prod-workplan/99-templates-examples/health-check.sh`
- [ ] **Expected**: All health checks pass
- [ ] **Deliverable**: Health check report with 0 errors

#### Step 10.2: Database Migration and Seeding
- [ ] **Task**: Run database migrations and create admin user
- [ ] **Commands**:
  ```bash
  docker exec prs-onprem-backend npm run migrate
  docker exec prs-onprem-backend npm run seed:admin
  ```
- [ ] **Expected**: Database schema created, admin user exists
- [ ] **Deliverable**: Database ready for production use

#### Step 10.3: Performance Testing
- [ ] **Task**: Test system performance with load
- [ ] **Commands**:
  ```bash
  # Install Apache Bench
  sudo apt install -y apache2-utils
  # Test with 10 concurrent users
  ab -n 100 -c 10 https://192.168.0.100/
  ```
- [ ] **Expected**: Response time < 200ms, no errors
- [ ] **Deliverable**: Performance test results

### **Day 11: Backup System Setup**
**Time Estimate: 4 hours**

#### Step 11.1: Setup Backup Scripts
- [ ] **Task**: Install and configure backup automation
- [ ] **Commands**:
  ```bash
  sudo mkdir -p /opt/prs/backup-scripts
  sudo cp /opt/prs/prod-workplan/09-scripts-adaptation/*.sh /opt/prs/backup-scripts/
  sudo chmod +x /opt/prs/backup-scripts/*.sh
  ```
- [ ] **Expected**: Backup scripts installed and executable
- [ ] **Deliverable**: Backup automation ready

#### Step 11.2: Test Backup Procedures
- [ ] **Task**: Run manual backup test
- [ ] **Command**: `/opt/prs/backup-scripts/daily-backup.sh`
- [ ] **Expected**: Backup completes successfully
- [ ] **Deliverable**: Verified backup functionality

#### Step 11.3: Schedule Automated Backups
- [ ] **Task**: Setup cron jobs for automated backups
- [ ] **Commands**:
  ```bash
  crontab -e
  # Add these lines:
  # 0 2 * * * /opt/prs/backup-scripts/daily-backup.sh
  # 0 1 * * 0 /opt/prs/backup-scripts/weekly-backup.sh
  ```
- [ ] **Expected**: Cron jobs scheduled
- [ ] **Deliverable**: Automated backup schedule active

### **Day 12: Final Validation and Go-Live**
**Time Estimate: 6 hours**

#### Step 12.1: User Acceptance Testing
- [ ] **Task**: Complete functional testing
- [ ] **Tests**:
  - [ ] Admin login works
  - [ ] User registration works
  - [ ] File upload works
  - [ ] Reports generate
  - [ ] All main features functional
- [ ] **Expected**: All features working correctly
- [ ] **Deliverable**: UAT sign-off

#### Step 12.2: Monitoring Configuration
- [ ] **Task**: Configure Grafana dashboards and alerts
- [ ] **Actions**:
  - [ ] Login to Grafana (http://192.168.0.100:3001)
  - [ ] Import system dashboard
  - [ ] Configure email alerts
  - [ ] Test alert notifications
- [ ] **Expected**: Monitoring and alerting active
- [ ] **Deliverable**: Production monitoring operational

#### Step 12.3: Documentation Handover
- [ ] **Task**: Provide operational documentation to IT team
- [ ] **Deliverables**:
  - [ ] Admin credentials document
  - [ ] Monitoring dashboard URLs
  - [ ] Backup and recovery procedures
  - [ ] Troubleshooting guide
  - [ ] Emergency contact procedures
- [ ] **Expected**: IT team trained and ready
- [ ] **Deliverable**: Operational handover complete

---

## 📊 **SUCCESS CRITERIA**

### **Technical Validation**
- [ ] All 11 services running and healthy
- [ ] HTTPS access working from client network
- [ ] Database responding with <100ms query time
- [ ] Monitoring showing green status
- [ ] Backups completing successfully
- [ ] Health check script passes with 0 errors

### **Performance Validation**
- [ ] System supports 100 concurrent users
- [ ] Response time <200ms for 95% of requests
- [ ] Memory usage <75% under normal load
- [ ] SSD usage <80%, HDD usage <70%
- [ ] No error rates >1%

### **Operational Validation**
- [ ] IT team can access all management interfaces
- [ ] Backup and recovery procedures tested
- [ ] Monitoring alerts working
- [ ] Documentation complete and accessible
- [ ] Emergency procedures documented

---

## 🚨 **ROLLBACK PLAN**

If any step fails critically:

1. **Stop all services**: `docker compose -f docker-compose.onprem.yml down`
2. **Restore from backup**: Use latest backup if data corruption
3. **Revert to previous step**: Fix issues and retry
4. **Emergency contact**: Escalate to technical team if needed

---

## 📋 **VALIDATION CHECKLIST**

### **Pre-Deployment Validation**
```bash
# Hardware Check
free -h | grep "Mem:" | awk '{print $2}'  # Should show ~16G
df -h /mnt/ssd | awk 'NR==2 {print $4}'   # Should show ~400G+ available
df -h /mnt/hdd | awk 'NR==2 {print $4}'   # Should show ~2T+ available
ip addr show | grep "192.168.0.100"      # Should show assigned IP

# Network Check
ping -c 1 192.168.1.1                     # Should succeed
ping -c 1 8.8.8.8                         # Should succeed
nslookup google.com                        # Should resolve

# System Check
docker --version                           # Should show 24.0+
docker compose version                     # Should show v2.x
sudo ufw status                           # Should show "active"
```

### **Post-Deployment Validation**
```bash
# Service Health Check
docker ps | wc -l                         # Should show 11+ containers
curl -f https://192.168.0.100/           # Should return 200
curl -f https://192.168.0.100/api/health # Should return 200
curl -f http://192.168.0.100:3001/       # Grafana should load
curl -f http://192.168.0.100:9090/       # Prometheus should load

# Database Check
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "SELECT version();"
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "SELECT timescaledb_version();"

# Performance Check
ab -n 10 -c 2 https://192.168.0.100/     # Should complete without errors
```

### **Final Go-Live Checklist**
- [ ] All services running (11 containers)
- [ ] HTTPS accessible from client network
- [ ] Admin user can login successfully
- [ ] Database queries responding <100ms
- [ ] Monitoring dashboards showing data
- [ ] Backup scripts tested and scheduled
- [ ] Health check script passes
- [ ] IT team trained on operations
- [ ] Emergency procedures documented
- [ ] Performance meets requirements

---

**Total Estimated Time: 4 weeks (80 hours)**
**Critical Path**: Database → Backend → Frontend → Nginx → Monitoring
**Success Rate**: 95% if all prerequisites met
**Rollback Time**: <2 hours to previous working state

---

## 🎯 **WHAT THIS WORKPLAN DELIVERS**

### **Concrete Deliverables**
1. **Working PRS System**: 100 concurrent users, <200ms response time
2. **Complete Monitoring**: Grafana dashboards, Prometheus alerts
3. **Automated Backups**: Daily/weekly with zero-deletion policy
4. **Security Hardening**: SSL, firewall, multi-layer protection
5. **Operational Documentation**: Complete guides for IT team
6. **Health Monitoring**: Automated system validation
7. **Performance Optimization**: 4x memory, intelligent storage

### **Measurable Success Criteria**
- **Uptime**: 99.9% availability target
- **Performance**: <200ms response time for 95% requests
- **Capacity**: Support 100 concurrent users
- **Storage**: Intelligent SSD/HDD tiering working
- **Backups**: Daily backups completing successfully
- **Monitoring**: All alerts configured and working
- **Security**: All security measures active

This is a **CONCRETE, ACTIONABLE WORKPLAN** with specific commands, validation steps, and measurable outcomes.
