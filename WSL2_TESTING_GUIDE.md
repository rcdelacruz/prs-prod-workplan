# 🐧 WSL2 Ubuntu Testing Guide for PRS On-Premises Deployment

## 🎯 Overview

Test the complete PRS on-premises deployment on WSL2 Ubuntu to validate everything works before deploying to actual production hardware.

## 🛠️ WSL2 Setup Requirements

### **1. WSL2 Ubuntu Installation**
```powershell
# In Windows PowerShell (as Administrator)
wsl --install Ubuntu-24.04
# or if WSL already installed:
wsl --install -d Ubuntu-24.04
```

### **2. WSL2 Configuration for Testing**
```bash
# In WSL2 Ubuntu terminal
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y docker.io docker-compose-v2 curl wget git htop tree
```

### **3. Docker Setup in WSL2**
```bash
# Start Docker service
sudo service docker start

# Add user to docker group
sudo usermod -aG docker $USER

# Restart WSL2 to apply group changes
exit
# Then restart WSL2 from Windows
```

## 📁 WSL2 Storage Simulation

Since WSL2 doesn't have separate SSD/HDD mounts, we'll simulate them:

```bash
# Create simulated storage directories
sudo mkdir -p /mnt/{ssd,hdd}
sudo mkdir -p /mnt/ssd/{postgresql-data,redis-data,uploads,logs,nginx-cache,prometheus-data,grafana-data,portainer-data}
sudo mkdir -p /mnt/hdd/{postgresql-cold,backups,archives,logs-archive,postgres-wal-archive,postgres-backups}

# Set ownership
sudo chown -R $USER:$USER /mnt/{ssd,hdd}
chmod -R 755 /mnt/{ssd,hdd}

# Verify setup
df -h /mnt/ssd /mnt/hdd
```

## 🌐 Network Configuration for WSL2

### **1. Get WSL2 IP Address**
```bash
# Find WSL2 IP address
ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1

# Example output: 172.20.144.2
# Use this IP instead of 192.168.16.100
```

### **2. Update Environment for WSL2**
```bash
# Clone the workplan
git clone https://github.com/your-repo/prod-workplan.git
cd prod-workplan

# Setup environment for WSL2 testing
./scripts/setup-env.sh

# Edit .env file for WSL2
nano 02-docker-configuration/.env

# Update these values:
# SERVER_IP=172.20.144.2  (your WSL2 IP)
# DOMAIN=prs.local
# CORS_ORIGIN=http://172.20.144.2,https://172.20.144.2
```

## 🚀 WSL2 Deployment Testing

### **Method 1: Full Deployment Test**
```bash
# Run complete deployment
./scripts/deploy-onprem.sh deploy

# This will:
# - Install all dependencies
# - Setup simulated storage
# - Configure firewall (WSL2 compatible)
# - Build Docker images
# - Start all services
# - Initialize database
```

### **Method 2: Step-by-Step Testing**
```bash
# 1. Setup system
./scripts/deploy-onprem.sh setup

# 2. Build images
./scripts/deploy-onprem.sh build

# 3. Start services
./scripts/deploy-onprem.sh start

# 4. Initialize database
./scripts/deploy-onprem.sh init-db

# 5. Check status
./scripts/deploy-onprem.sh status
```

## 🔍 WSL2 Validation

### **1. Service Health Check**
```bash
# Get your WSL2 IP
WSL_IP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)

# Test all endpoints
curl -f http://$WSL_IP/
curl -f http://$WSL_IP/api/health
curl -f http://$WSL_IP:3001/  # Grafana
curl -f http://$WSL_IP:9090/  # Prometheus
curl -f http://$WSL_IP:8080/  # Adminer
curl -f http://$WSL_IP:9000/  # Portainer

# Run health check
./scripts/deploy-onprem.sh health
```

### **2. Performance Testing**
```bash
# Install Apache Bench
sudo apt install -y apache2-utils

# Test performance
ab -n 100 -c 10 http://$WSL_IP/
ab -n 50 -c 5 http://$WSL_IP/api/health
```

### **3. Database Testing**
```bash
# Test database connectivity
docker exec prs-onprem-postgres-timescale pg_isready -U prs_user

# Test TimescaleDB
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "SELECT timescaledb_version();"

# Test admin login
# Use credentials from ADMIN_CREDENTIALS.txt
```

## 🌐 Access from Windows

### **1. Port Forwarding (if needed)**
```powershell
# In Windows PowerShell (as Administrator)
# Forward WSL2 ports to Windows
netsh interface portproxy add v4tov4 listenport=80 listenaddress=0.0.0.0 connectport=80 connectaddress=172.20.144.2
netsh interface portproxy add v4tov4 listenport=3001 listenport=3001 connectaddress=172.20.144.2
netsh interface portproxy add v4tov4 listenport=9090 listenport=9090 connectaddress=172.20.144.2

# Check forwarding rules
netsh interface portproxy show all
```

### **2. Access URLs from Windows**
```
Application: http://172.20.144.2/ (or http://localhost/ if port forwarded)
Grafana: http://172.20.144.2:3001/
Prometheus: http://172.20.144.2:9090/
Adminer: http://172.20.144.2:8080/
Portainer: http://172.20.144.2:9000/
```

## 🔧 WSL2-Specific Adaptations

### **1. Firewall Handling**
```bash
# WSL2 doesn't use UFW the same way
# The deploy script will handle this automatically
# But you can disable firewall for testing:
sudo ufw --force reset
sudo ufw default allow incoming
sudo ufw default allow outgoing
```

### **2. Memory Simulation**
```bash
# WSL2 might not have 16GB allocated
# Check available memory
free -h

# If less than 16GB, edit .wslconfig in Windows:
# C:\Users\YourUsername\.wslconfig
[wsl2]
memory=16GB
processors=4
```

### **3. Storage Performance**
```bash
# Test storage performance
# SSD simulation
dd if=/dev/zero of=/mnt/ssd/test bs=1M count=100
# HDD simulation  
dd if=/dev/zero of=/mnt/hdd/test bs=1M count=100

# Clean up
rm /mnt/ssd/test /mnt/hdd/test
```

## 🧪 Testing Scenarios

### **1. Basic Functionality Test**
```bash
# 1. Deploy system
./scripts/deploy-onprem.sh deploy

# 2. Wait for services to start
sleep 60

# 3. Test login
# Use credentials from ADMIN_CREDENTIALS.txt

# 4. Test file upload
# Upload a test file through the web interface

# 5. Test database
# Check if data is being stored correctly
```

### **2. Load Testing**
```bash
# Simulate multiple users
ab -n 1000 -c 20 http://$WSL_IP/

# Monitor during load test
docker stats
htop
```

### **3. Backup Testing**
```bash
# Test backup functionality
./scripts/deploy-onprem.sh backup

# Verify backup files
ls -la /mnt/ssd/backups/daily/
ls -la /mnt/hdd/backups/
```

## 🚨 Common WSL2 Issues & Solutions

### **Issue 1: Docker won't start**
```bash
# Solution
sudo service docker start
sudo systemctl enable docker
```

### **Issue 2: Permission denied**
```bash
# Solution
sudo chown -R $USER:$USER /mnt/{ssd,hdd}
sudo usermod -aG docker $USER
# Restart WSL2
```

### **Issue 3: Can't access from Windows**
```bash
# Check WSL2 IP
ip addr show eth0

# Update Windows hosts file if needed
# C:\Windows\System32\drivers\etc\hosts
# Add: 172.20.144.2 prs.local
```

### **Issue 4: Out of memory**
```bash
# Check memory usage
free -h
docker stats

# Reduce memory limits in .env if needed
# POSTGRES_MEMORY_LIMIT=2g
# BACKEND_MEMORY_LIMIT=1g
```

## ✅ WSL2 Testing Checklist

- [ ] WSL2 Ubuntu 24.04 installed
- [ ] Docker installed and running
- [ ] Storage directories created (/mnt/ssd, /mnt/hdd)
- [ ] Environment file configured for WSL2 IP
- [ ] All services deployed and running
- [ ] Web interface accessible from Windows
- [ ] Database connectivity working
- [ ] Monitoring dashboards accessible
- [ ] Backup functionality tested
- [ ] Performance testing completed

## 🎯 Expected Results

After successful WSL2 testing:
- ✅ **All 11 services running** in Docker containers
- ✅ **Web interface accessible** from Windows browser
- ✅ **Database operations working** (login, data storage)
- ✅ **Monitoring active** (Grafana showing metrics)
- ✅ **Backups functional** (files created in backup directories)
- ✅ **Performance acceptable** (response times <500ms)

## 🚀 Next Steps

Once WSL2 testing is successful:
1. **Document any issues** encountered and solutions
2. **Validate all features** work as expected
3. **Test backup/restore** procedures
4. **Prepare for production deployment** on actual hardware
5. **Create deployment checklist** based on WSL2 experience

---

**WSL2 testing gives you confidence that the deployment will work on real hardware! 🎯**
