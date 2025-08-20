# ⚡ PRS On-Premises Deployment - REALISTIC 2-DAY WORKPLAN

## 🎯 **OVERVIEW**
**Total Time: 2 Days (16 hours)** for experienced team  
**Team Size: 2-3 people** (1 DevOps, 1 Developer, 1 IT Support)  
**Prerequisites: All hardware ready, network configured**

---

## 📅 **DAY 1: INFRASTRUCTURE & DEPLOYMENT (8 hours)**

### **Morning Session (4 hours): 9:00 AM - 1:00 PM**

#### **Hour 1: System Preparation (9:00-10:00 AM)**
```bash
# Quick system setup (30 minutes)
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose-v2 curl wget git

# Storage setup (15 minutes)
sudo mkdir -p /mnt/{ssd,hdd}/{postgresql-data,redis-data,uploads,logs,backups}
sudo chown -R $USER:$USER /mnt/{ssd,hdd}

# Firewall setup (15 minutes)
sudo ufw --force reset
sudo ufw allow from 192.168.0.0/20 to any port 80,443,8080,3001,9000,9090
sudo ufw --force enable
```
**Validation**: `docker --version`, `df -h /mnt/ssd`, `sudo ufw status`

#### **Hour 2: Repository & Configuration (10:00-11:00 AM)**
```bash
# Clone repos (10 minutes)
sudo mkdir -p /opt/prs && sudo chown $USER:$USER /opt/prs
cd /opt/prs
git clone https://github.com/rcdelacruz/prs-backend-a.git &
git clone https://github.com/rcdelacruz/prs-frontend-a.git &
wait

# Copy workplan (5 minutes)
cp -r /path/to/prod-workplan /opt/prs/

# Generate secrets (10 minutes)
cd /opt/prs/prod-workplan/02-docker-configuration
cp .env.onprem.example .env

# Generate all secrets at once
cat > secrets.txt << EOF
JWT_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32)
OTP_KEY=$(openssl rand -base64 16)
PASS_SECRET=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
POSTGRES_PASSWORD=$(openssl rand -base64 32)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
EOF

# Update .env file (25 minutes)
# Replace all CHANGE_THIS_* placeholders with generated secrets
# Update DOMAIN, SERVER_IP, email settings
```
**Validation**: `cat .env | grep -v "CHANGE_THIS"` (should return nothing)

#### **Hour 3: SSL & Docker Images (11:00 AM-12:00 PM)**
```bash
# Quick SSL setup (15 minutes)
mkdir -p /opt/prs/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/prs/ssl/server.key \
  -out /opt/prs/ssl/server.crt \
  -subj "/C=PH/ST=Metro Manila/L=Manila/O=Client/CN=prs.client-domain.com"

# Build images in parallel (45 minutes)
cd /opt/prs
docker build -t prs-backend:latest prs-backend-a &
docker build -t prs-frontend:latest prs-frontend-a &
wait
```
**Validation**: `docker images | grep prs`

#### **Hour 4: Database Deployment (12:00-1:00 PM)**
```bash
# Start database (10 minutes)
cd /opt/prs/prod-workplan/02-docker-configuration
docker compose -f docker-compose.onprem.yml up -d postgres

# Wait for database to be ready (5 minutes)
sleep 30
docker exec prs-onprem-postgres-timescale pg_isready -U prs_user

# Initialize TimescaleDB (10 minutes)
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"

# Run migrations (25 minutes)
docker compose -f docker-compose.onprem.yml up -d backend
sleep 30
docker exec prs-onprem-backend npm run migrate
docker exec prs-onprem-backend npm run seed:admin

# Start Redis (10 minutes)
docker compose -f docker-compose.onprem.yml up -d redis redis-worker
```
**Validation**: `docker ps | wc -l` (should show 4+ containers)

### **Afternoon Session (4 hours): 2:00 PM - 6:00 PM**

#### **Hour 5: Application Services (2:00-3:00 PM)**
```bash
# Start frontend and nginx (20 minutes)
docker compose -f docker-compose.onprem.yml up -d frontend nginx

# Start monitoring (20 minutes)
docker compose -f docker-compose.onprem.yml --profile monitoring up -d

# Start management tools (20 minutes)
docker compose -f docker-compose.onprem.yml up -d adminer portainer
```
**Validation**: `docker ps | wc -l` (should show 11+ containers)

#### **Hour 6: Service Validation (3:00-4:00 PM)**
```bash
# Test all endpoints (30 minutes)
curl -f https://192.168.16.100/                    # Frontend
curl -f https://192.168.16.100/api/health          # Backend
curl -f http://192.168.16.100:3001/                # Grafana
curl -f http://192.168.16.100:9090/                # Prometheus
curl -f http://192.168.16.100:8080/                # Adminer
curl -f http://192.168.16.100:9000/                # Portainer

# Database connectivity test (15 minutes)
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "SELECT version();"
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "SELECT timescaledb_version();"

# Performance test (15 minutes)
sudo apt install -y apache2-utils
ab -n 50 -c 5 https://192.168.16.100/
```
**Validation**: All curl commands return 200, ab test completes without errors

#### **Hour 7: Backup Setup (4:00-5:00 PM)**
```bash
# Install backup scripts (15 minutes)
sudo mkdir -p /opt/prs/backup-scripts
sudo cp /opt/prs/prod-workplan/09-scripts-adaptation/*.sh /opt/prs/backup-scripts/
sudo chmod +x /opt/prs/backup-scripts/*.sh

# Test backup (30 minutes)
/opt/prs/backup-scripts/daily-backup.sh

# Schedule backups (15 minutes)
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/prs/backup-scripts/daily-backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 1 * * 0 /opt/prs/backup-scripts/weekly-backup.sh") | crontab -
```
**Validation**: `crontab -l`, backup files exist in `/mnt/ssd/backups/`

#### **Hour 8: Health Check & Documentation (5:00-6:00 PM)**
```bash
# Run comprehensive health check (20 minutes)
/opt/prs/prod-workplan/99-templates-examples/health-check.sh

# Create admin credentials document (20 minutes)
cat > /opt/prs/ADMIN_CREDENTIALS.txt << EOF
=== PRS On-Premises Admin Credentials ===
Application URL: https://192.168.16.100/
Admin Email: admin@client-domain.com
Admin Password: [from ROOT_USER_PASSWORD in .env]

Grafana: http://192.168.16.100:3001/
Grafana Admin: admin
Grafana Password: [from GRAFANA_ADMIN_PASSWORD in .env]

Adminer: http://192.168.16.100:8080/
Database: prs_production
User: prs_user
Password: [from POSTGRES_PASSWORD in .env]

Portainer: http://192.168.16.100:9000/
EOF

# Final system status (20 minutes)
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
df -h /mnt/ssd /mnt/hdd
free -h
```
**Validation**: Health check passes, all services running, credentials documented

---

## 📅 **DAY 2: OPTIMIZATION & GO-LIVE (8 hours)**

### **Morning Session (4 hours): 9:00 AM - 1:00 PM**

#### **Hour 9: Performance Optimization (9:00-10:00 AM)**
```bash
# System optimization (30 minutes)
sudo tee /etc/sysctl.d/99-prs.conf > /dev/null <<EOF
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
vm.swappiness = 10
vm.dirty_ratio = 15
EOF
sudo sysctl -p /etc/sysctl.d/99-prs.conf

# Database optimization (30 minutes)
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "VACUUM ANALYZE;"
```

#### **Hour 10: Monitoring Configuration (10:00-11:00 AM)**
```bash
# Configure Grafana dashboards (45 minutes)
# Login to http://192.168.16.100:3001/
# Import system dashboard
# Configure alerts

# Test alerting (15 minutes)
# Trigger test alert and verify email delivery
```

#### **Hour 11: Load Testing (11:00 AM-12:00 PM)**
```bash
# Comprehensive load test (45 minutes)
ab -n 1000 -c 20 https://192.168.16.100/
ab -n 500 -c 10 https://192.168.16.100/api/health

# Monitor during load test (15 minutes)
# Check Grafana dashboards
# Verify no errors in logs
```

#### **Hour 12: User Acceptance Testing (12:00-1:00 PM)**
```bash
# Functional testing checklist (60 minutes)
# - Admin login
# - User registration  
# - File upload
# - Report generation
# - All main features
```

### **Afternoon Session (4 hours): 2:00 PM - 6:00 PM**

#### **Hour 13: Security Validation (2:00-3:00 PM)**
```bash
# Security checks (45 minutes)
sudo ufw status verbose
openssl x509 -in /opt/prs/ssl/server.crt -noout -dates
nmap -p 80,443,8080,3001,9000,9090 192.168.16.100

# Penetration testing (15 minutes)
# Basic security scan
```

#### **Hour 14: Backup Validation (3:00-4:00 PM)**
```bash
# Test backup restoration (45 minutes)
# Create test backup
# Simulate restore procedure
# Verify data integrity

# Backup monitoring (15 minutes)
# Verify backup alerts work
# Check backup storage usage
```

#### **Hour 15: Documentation & Training (4:00-5:00 PM)**
```bash
# Create operational runbook (45 minutes)
# Document all procedures
# Create troubleshooting guide
# Prepare IT team handover

# Knowledge transfer (15 minutes)
# Brief IT team on operations
# Share credentials and procedures
```

#### **Hour 16: Go-Live & Final Validation (5:00-6:00 PM)**
```bash
# Final health check (20 minutes)
/opt/prs/prod-workplan/99-templates-examples/health-check.sh

# Performance validation (20 minutes)
ab -n 100 -c 10 https://192.168.16.100/

# Go-live checklist (20 minutes)
# - All services healthy
# - Monitoring active
# - Backups scheduled
# - IT team trained
# - Users can access system
```

---

## ✅ **SUCCESS CRITERIA (End of Day 2)**

### **Technical Validation**
- [ ] All 11 services running and healthy
- [ ] HTTPS accessible from client network (192.168.0.0/20)
- [ ] Response time <200ms for 95% of requests
- [ ] Database queries <100ms
- [ ] Health check script passes with 0 errors
- [ ] Load test handles 20 concurrent users

### **Operational Validation**
- [ ] Monitoring dashboards showing data
- [ ] Alerts configured and tested
- [ ] Backups completing successfully
- [ ] IT team trained on operations
- [ ] Admin credentials documented
- [ ] Troubleshooting guide available

### **Performance Validation**
- [ ] Memory usage <75% under load
- [ ] SSD usage <80%, HDD usage <70%
- [ ] No error rates >1%
- [ ] System stable under load

---

## 🚨 **REALISTIC EXPECTATIONS**

**This 2-day timeline assumes:**
- ✅ Hardware already configured and ready
- ✅ Network and firewall rules pre-configured by IT
- ✅ Experienced team (DevOps + Developer + IT)
- ✅ No major issues or complications
- ✅ All prerequisites met

**If issues arise, add +1 day for troubleshooting**

**Total: 2-3 days for complete production deployment**
