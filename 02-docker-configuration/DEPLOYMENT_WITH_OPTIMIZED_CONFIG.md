# Using the Optimized Environment Configuration

## 🚀 Quick Deployment Steps

### 1. **Backup Your Current Configuration**
```bash
cd ~/prs-prod-workplan/02-docker-configuration
cp .env .env.backup.$(date +%Y%m%d_%H%M%S)
```

### 2. **Use the Optimized Configuration**
```bash
# Replace your current .env with the optimized version
cp .env.production.optimized .env
```

### 3. **Customize Required Settings**
Edit the `.env` file to customize these **CRITICAL** settings for your environment:

```bash
nano .env
```

**🔴 MUST CHANGE - Security Settings:**
```bash
# Database passwords
POSTGRES_PASSWORD=YourSecureDbPassword123!
REDIS_PASSWORD=YourSecureRedisPassword456!

# Application secrets (generate strong random values)
JWT_SECRET=your-super-secure-jwt-secret-key-min-32-chars-long
ENCRYPTION_KEY=your-32-character-encryption-key
OTP_KEY=your-otp-secret-key
PASS_SECRET=your-password-hashing-secret

# Admin credentials
ROOT_USER_PASSWORD=YourSecureAdminPassword789!
GRAFANA_ADMIN_PASSWORD=YourSecureGrafanaPassword!
```

**🟡 SHOULD CHANGE - Network Settings:**
```bash
# Your server's IP address
SERVER_IP=192.168.0.100  # Change to your actual server IP
DOMAIN=prs.company.local  # Change to your domain

# CORS origins (match your domain/IP)
CORS_ORIGIN=https://prs.company.local,https://192.168.0.100
```

**🟢 MAY CHANGE - API Integration:**
```bash
# External API endpoints (if you have them)
CITYLAND_API_URL=https://api.cityland.local
CITYLAND_API_USERNAME=api_user
CITYLAND_API_PASSWORD=api_password
```

### 4. **Prepare Storage Directories**
```bash
# Run the storage setup script
~/prs-prod-workplan/scripts/setup-storage.sh
```

### 5. **Deploy with Docker Compose**
```bash
cd ~/prs-prod-workplan/02-docker-configuration

# Start the optimized stack
docker-compose -f docker-compose.onprem.yml up -d

# Or with specific profiles (monitoring optional)
docker-compose -f docker-compose.onprem.yml --profile monitoring up -d
```

## 📊 **What the Optimized Config Provides**

### **Memory Optimization (16GB RAM)**
- **PostgreSQL:** 8GB memory limit, 3GB shared buffers
- **Redis:** 3GB memory with smart eviction
- **Backend:** 6GB memory for high concurrency
- **Monitoring:** 2GB Prometheus, 1GB Grafana

### **Performance Settings**
- **Database Connections:** 200 max connections, 10-30 pool size
- **Node.js:** 4GB heap size for optimal performance
- **Connection Timeouts:** Optimized for production use
- **Cache Settings:** 2-hour TTL, smart caching enabled

### **Production Security**
- **SSL/TLS:** Enabled for all connections
- **Rate Limiting:** API protection (200 requests/15min)
- **Session Security:** 2-hour sessions, 5 max login attempts
- **Security Headers:** All production security headers enabled

### **Monitoring & Alerting**
- **Health Checks:** All services monitored
- **Metrics:** Prometheus collection enabled
- **Audit Logs:** Complete audit trail
- **Log Retention:** 60 days Prometheus, 200MB log rotation

## 🔧 **Alternative Deployment Options**

### **Option A: Use Specific Environment File**
Instead of replacing `.env`, you can specify the file directly:

```bash
# Deploy with specific env file
docker-compose -f docker-compose.onprem.yml --env-file .env.production.optimized up -d
```

### **Option B: Environment-Specific Deployment**
```bash
# Create production environment
cp .env.production.optimized .env.production

# Deploy with production config
docker-compose -f docker-compose.onprem.yml --env-file .env.production up -d
```

## 📋 **Pre-Deployment Checklist**

### **System Requirements ✅**
- [ ] System optimizations applied (kernel params, limits)
- [ ] Docker service running and optimized
- [ ] Storage directories prepared (`setup-storage.sh`)
- [ ] Firewall configured (ports 80, 443, 22 open)

### **Configuration ✅**
- [ ] Database passwords changed from defaults
- [ ] JWT and encryption secrets generated
- [ ] Admin passwords set
- [ ] Server IP and domain configured
- [ ] External API endpoints configured (if needed)

### **Network ✅**
- [ ] DNS resolution working for your domain
- [ ] SSL certificates available (or Let's Encrypt configured)
- [ ] Internal network access configured (192.168.0.0/20)

## 🚦 **Deployment Commands**

### **Full Production Deployment**
```bash
cd ~/prs-prod-workplan/02-docker-configuration

# 1. Prepare environment
cp .env.production.optimized .env
nano .env  # Edit secrets and network settings

# 2. Setup storage
~/prs-prod-workplan/scripts/setup-storage.sh

# 3. Deploy all services
docker-compose -f docker-compose.onprem.yml --profile monitoring up -d

# 4. Check status
docker-compose -f docker-compose.onprem.yml ps
```

### **Core Services Only (No Monitoring)**
```bash
cd ~/prs-prod-workplan/02-docker-configuration

# Deploy core PRS services only
docker-compose -f docker-compose.onprem.yml up -d
```

### **Development/Testing Deployment**
```bash
cd ~/prs-prod-workplan/02-docker-configuration

# Use development settings (lower resource usage)
docker-compose -f docker-compose.onprem.yml --env-file .env.dev.example up -d
```

## 🔍 **Monitoring Your Deployment**

### **Check Service Health**
```bash
# View all containers
docker-compose -f docker-compose.onprem.yml ps

# Check logs
docker-compose -f docker-compose.onprem.yml logs -f [service_name]

# Run health check
~/prs-prod-workplan/scripts/system-health-check.sh
```

### **Access Monitoring Dashboards**
- **Application:** `https://your-server-ip/` or `https://your-domain/`
- **Database Admin:** `https://your-server-ip:8080/` (Adminer)
- **Monitoring:** `https://your-server-ip:3001/` (Grafana)
- **Metrics:** `https://your-server-ip:9090/` (Prometheus)
- **Container Management:** `https://your-server-ip:9000/` (Portainer)

## 🛠️ **Troubleshooting**

### **Common Issues**

#### **1. Container Won't Start**
```bash
# Check logs
docker-compose -f docker-compose.onprem.yml logs [service_name]

# Check system resources
~/prs-prod-workplan/scripts/system-health-check.sh
```

#### **2. Database Connection Issues**
```bash
# Test database connectivity
docker-compose -f docker-compose.onprem.yml exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT version();"
```

#### **3. Permission Issues**
```bash
# Fix storage permissions
sudo chown -R 999:999 /mnt/ssd/postgresql-data
sudo chown -R 999:999 /mnt/ssd/redis-data
```

#### **4. Network Issues**
```bash
# Check Docker network
docker network ls
docker network inspect prs_onprem_network
```

### **Rollback Procedure**
If you need to revert to the original configuration:

```bash
cd ~/prs-prod-workplan/02-docker-configuration

# Stop services
docker-compose -f docker-compose.onprem.yml down

# Restore original config
cp .env.backup.* .env  # Use your backup file

# Restart with original config
docker-compose -f docker-compose.onprem.yml up -d
```

## 📞 **Support**

If you encounter issues:

1. **Check Logs:** `docker-compose logs -f`
2. **Run Health Check:** `./scripts/system-health-check.sh`
3. **Review Documentation:** `SERVER_OPTIMIZATION_REPORT.md`
4. **System Status:** `systemctl status docker`

---

**✅ Your optimized configuration is ready for production deployment!**

The `.env.production.optimized` file contains all the performance and security optimizations needed for your 16GB server with 100+ concurrent users.
