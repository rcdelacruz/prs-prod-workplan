# Quick Start Guide - PRS Deployment

## Overview

This guide will get you from zero to a fully operational PRS system in **2-3 hours** using the proven `deploy-onprem.sh` script with helpful configuration tools.

### What You'll Get

- **Complete PRS application stack** with all services running
- **SSL/TLS security** with GoDaddy or Let's Encrypt support
- **Enterprise backup system** with optional NAS integration
- **Comprehensive monitoring** with Grafana dashboards
- **Automated maintenance** and health checks
- **Office network security** configuration

### Simple 3-Step Process

| Step | Duration | Description |
|------|----------|-------------|
| **1. Configure** | 10-15 min | Use helper script to set up configuration |
| **2. Deploy** | 1-2 hours | Run deploy-onprem.sh for complete deployment |
| **3. Automate** | 15-30 min | Set up backup and monitoring automation |

**Total Time: 2-3 hours**

!!! danger "Prerequisites Required"
    **STOP!** You must complete [Prerequisites](prerequisites.md) first. The deployment will fail without proper server setup (storage mounts, user account, etc.).

!!! success "Proven Approach"
    This guide uses the existing, battle-tested `deploy-onprem.sh` script that handles all the complex deployment logic. We simply add configuration helpers and post-deployment automation.

!!! info "Office Network Ready"
    Optimized for office environments with GoDaddy SSL support and network-restricted monitoring access.

---

## Step 1: Configuration (10-15 minutes)

### Prerequisites

!!! warning "Complete Prerequisites First"
    **[📖 Read Prerequisites Guide](prerequisites.md)** - Essential server setup required before proceeding.

**Critical requirements verified by deploy script:**
- **Ubuntu 24.04 LTS** server (22.04 supported)
- **System updated** (`sudo apt update && sudo apt upgrade -y`)
- **GitHub CLI installed** and authenticated (`gh auth login`)
- **16GB+ RAM** (checked by script)
- **Storage mounts** `/mnt/ssd` and `/mnt/hdd` (required)
- **Non-root user** with sudo access (script fails if root)
- **Domain name** configured (e.g., prs.citylandcondo.com)
- **Network connectivity** and static IP in 192.168.0.0/20 range

**Quick verification:**
```bash
# Run this to check if you're ready
./check-prerequisites.sh
```

### Quick Configuration

```bash
# Navigate to the PRS deployment directory
cd /opt/prs-deployment/scripts

# Run the configuration helper
./quick-setup-helper.sh
```

The helper will prompt you for:
- **Domain name** (e.g., prs.citylandcondo.com)
- **Admin email** for notifications
- **SSL method** (GoDaddy/Let's Encrypt/Self-signed)
- **Database passwords** (auto-generated)
- **NAS settings** (optional)

!!! tip "GoDaddy SSL"
    If your domain is `*.citylandcondo.com`, the system will automatically use the existing GoDaddy SSL automation.

---

## Step 2: Deployment (1-2 hours)

### Run the Deployment

The proven `deploy-onprem.sh` script handles the complete deployment:

```bash
# Run the complete deployment (1-2 hours)
sudo ./deploy-onprem.sh deploy
```

This **idempotent** command will:
- **Install all dependencies** (Docker, packages, etc.)
- **Configure storage** (SSD/HDD setup with proper permissions)
- **Set up SSL certificates** (self-signed initially)
- **Configure firewall** for office network access (192.168.0.0/20)
- **Clone and build** application repositories
- **Deploy all services** (PostgreSQL+TimescaleDB, Redis, Nginx, etc.)
- **Initialize database** and create admin user
- **Start monitoring** services (Grafana, Prometheus, Node Exporter)

!!! info "Idempotent Design"
    The script can be run multiple times safely. It will skip completed steps and only perform necessary changes.

### Monitor Progress

```bash
# Check what's been completed
./deploy-onprem.sh check-state

# Watch service status
watch docker ps

# View deployment logs
tail -f /var/log/prs-deploy.log

# Check specific service logs
docker logs prs-onprem-backend --tail 50
docker logs prs-onprem-postgres-timescale --tail 50
```

### Verify Deployment

After deployment completes:

```bash
# Check comprehensive system status
./deploy-onprem.sh status

# Run health check
./deploy-onprem.sh health

# Test application access
curl -k https://your-domain.com/api/health

# Connect to database (optional)
./deploy-onprem.sh db-connect
```

### Optional: GoDaddy SSL Setup

If your domain is `*.citylandcondo.com`, set up proper SSL certificates:

```bash
# Run GoDaddy SSL automation
./ssl-automation-citylandcondo.sh

# Restart services to use new certificates
./deploy-onprem.sh restart
```

---

## Step 3: Automation Setup (15-30 minutes)

### Set Up Backup Automation

```bash
# Configure automated backups
./setup-backup-automation.sh
```

This sets up:
- **Daily database backups** at 2:00 AM
- **Daily application backups** at 3:00 AM
- **Daily backup verification** at 4:00 AM
- **Weekly maintenance** on Sundays at 1:00 AM
- **NAS connectivity monitoring** (if configured)

### Set Up Monitoring Automation

```bash
# Configure automated monitoring
./setup-monitoring-automation.sh
```

This sets up:
- **System performance monitoring** every 5 minutes
- **Application health checks** every 10 minutes
- **Database performance monitoring** every 15 minutes
- **Daily monitoring reports** at 8:00 AM
- **Security hardening** (fail2ban, automatic updates)

---

## 🎉 Deployment Complete!

### Access Your System

| Service | URL | Access |
|---------|-----|--------|
| **Main Application** | `https://your-domain.com` | Public |
| **Grafana Monitoring** | `http://server-ip:3000` | Office Network Only |
| **Adminer (Database)** | `http://server-ip:8080` | Office Network Only |
| **Portainer (Containers)** | `http://server-ip:9000` | Office Network Only |

!!! note "Service Access"
    The deploy script shows exact URLs after completion. Use `./deploy-onprem.sh status` to see current access information.

### System Status

Your PRS system now includes:
- ✅ **High-performance application stack**
- ✅ **Enterprise-grade security** with SSL/TLS
- ✅ **Automated backup system** with optional NAS integration
- ✅ **Comprehensive monitoring** and alerting
- ✅ **Automated maintenance** procedures
- ✅ **Office network security** configuration

### Daily Operations

```bash
# Check system health
./system-health-check.sh

# View service status
docker ps

# Check backup status
ls -la /mnt/hdd/postgres-backups/daily/

# View monitoring logs
tail -f /var/log/prs-monitoring.log

# Manual backup
./backup-full.sh
```

### Maintenance Schedule

| Task | Frequency | Automated |
|------|-----------|-----------|
| Database Backup | Daily 2:00 AM | ✅ |
| Application Backup | Daily 3:00 AM | ✅ |
| Backup Verification | Daily 4:00 AM | ✅ |
| System Monitoring | Every 5-15 min | ✅ |
| Weekly Maintenance | Sunday 1:00 AM | ✅ |
| Security Updates | Weekly | ✅ |

---

## 🔧 Troubleshooting

### Common Issues

#### Configuration Helper Issues

**Problem: Permission denied**
```bash
# Make sure script is executable
chmod +x ./quick-setup-helper.sh
sudo ./quick-setup-helper.sh
```

**Problem: Domain not accessible**
- Check DNS configuration
- Verify firewall allows ports 80/443
- For office networks, ensure domain points to server IP

#### Deployment Issues

**Problem: deploy-onprem.sh fails**
```bash
# Check what's been completed
./deploy-onprem.sh check-state

# View deployment status
./deploy-onprem.sh status

# Check Docker status
sudo systemctl status docker

# Reset deployment state if needed
./deploy-onprem.sh reset-state
```

**Problem: Services won't start**
```bash
# Check comprehensive status
./deploy-onprem.sh status

# View service logs
docker logs prs-onprem-backend --tail 100
docker logs prs-onprem-postgres-timescale --tail 100

# Restart specific services
./deploy-onprem.sh restart

# Stop and start services
./deploy-onprem.sh stop
./deploy-onprem.sh start
```

#### SSL Certificate Issues

**Problem: GoDaddy SSL automation fails**
```bash
# Check if domain is correct
echo $DOMAIN

# Manually run SSL script
./ssl-automation-citylandcondo.sh

# Fall back to self-signed
# Edit .env file and set SSL_METHOD=3
```

**Problem: Let's Encrypt fails**
```bash
# Check domain DNS
nslookup your-domain.com

# Ensure ports 80/443 are open
sudo ufw status

# Try manual certificate generation
sudo certbot certonly --standalone -d your-domain.com
```

#### NAS Backup Issues

**Problem: NAS connectivity fails**
```bash
# Test NAS connection
./test-nas-connection.sh

# Check network connectivity
ping your-nas-ip

# Verify credentials in nas-config.sh
cat nas-config.sh
```

#### Performance Issues

**Problem: System running slowly**
```bash
# Check system resources
htop
df -h

# Check Docker resource usage
docker stats

# Optimize database
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "VACUUM ANALYZE;"
```

### Getting Help

#### Log Locations

| Component | Log Location |
|-----------|--------------|
| **Deployment** | `/var/log/prs-deploy.log` |
| **Application** | `docker logs prs-onprem-backend` |
| **Database** | `docker logs prs-onprem-postgres-timescale` |
| **Backup** | `/var/log/prs-backup.log` |
| **Monitoring** | `/var/log/prs-monitoring.log` |

#### Useful Commands

```bash
# Comprehensive system status
./deploy-onprem.sh status

# Check deployment state
./deploy-onprem.sh check-state

# Run health checks
./deploy-onprem.sh health

# Connect to database
./deploy-onprem.sh db-connect

# View all available commands
./deploy-onprem.sh help

# Check service logs
docker logs prs-onprem-backend --tail 50

# Manual backup test
./backup-full.sh

# System resource usage
htop && df -h
```

#### Reset and Restart

**Service restart:**
```bash
# Restart all services
./deploy-onprem.sh restart

# Stop and start services
./deploy-onprem.sh stop
./deploy-onprem.sh start
```

**Complete reset (if needed):**
```bash
# Reset deployment state
./deploy-onprem.sh reset-state

# Clean Docker resources
docker system prune -f

# Re-run deployment
./deploy-onprem.sh deploy
```

---

!!! success "Quick Start Complete"
    🎉 **Your PRS system is now fully deployed and operational!**

    **What you accomplished:**
    - ✅ Complete enterprise PRS application stack
    - ✅ SSL/TLS security with automated certificate management
    - ✅ Enterprise backup system with optional NAS integration
    - ✅ Comprehensive monitoring with Grafana dashboards
    - ✅ Automated maintenance and health checks
    - ✅ Office network security configuration

    **Total deployment time: 2-3 hours**

    Your system is production-ready and optimized for office network use!

!!! tip "Next Steps"
    1. **Access Grafana** at `:3000` to configure monitoring dashboards
    2. **Test backup system** by running `./backup-full.sh`
    3. **Create user accounts** in the application
    4. **Configure email notifications** for alerts
    5. **Review security settings** and adjust firewall rules as needed

!!! info "Support Resources"
    - **Documentation**: `/opt/prs-deployment/docs/`
    - **Scripts**: `/opt/prs-deployment/scripts/`
    - **Configuration**: `/opt/prs-deployment/02-docker-configuration/`
    - **Logs**: `/var/log/prs-*.log`
