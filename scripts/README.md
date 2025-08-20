# 🚀 PRS On-Premises Deployment Scripts

## 📋 Overview

These scripts provide automated deployment for PRS on-premises infrastructure, similar to the EC2 `deploy-ec2.sh` script but optimized for on-premises deployment with 16GB RAM and dual storage.

## 🛠️ Scripts

### `deploy-onprem.sh` - Main Deployment Script
**The equivalent of your EC2 `deploy-ec2.sh` script**

```bash
# Full deployment (one command does everything)
./deploy-onprem.sh deploy

# Other commands
./deploy-onprem.sh start      # Start services
./deploy-onprem.sh stop       # Stop services  
./deploy-onprem.sh restart    # Restart services
./deploy-onprem.sh status     # Show status
./deploy-onprem.sh health     # Run health check
./deploy-onprem.sh backup     # Run backup
```

### `setup-env.sh` - Environment Setup
**Quick environment file setup with auto-generated secrets**

```bash
# Generate .env file with secure secrets
./setup-env.sh
```

## ⚡ Quick Start (3 Commands)

```bash
# 1. Setup environment file
./scripts/setup-env.sh

# 2. Customize settings (optional)
nano 02-docker-configuration/.env

# 3. Deploy everything
./scripts/deploy-onprem.sh deploy
```

**That's it! Your PRS system will be running at https://192.168.16.100/**

## 📊 What `deploy-onprem.sh deploy` Does

1. **Prerequisites Check** - Verifies 16GB RAM, storage mounts, network
2. **System Setup** - Installs Docker, dependencies, configures firewall
3. **Storage Setup** - Creates SSD/HDD directory structure
4. **SSL Setup** - Generates certificates for HTTPS
5. **Repository Clone** - Downloads latest backend/frontend code
6. **Image Building** - Builds Docker images for both apps
7. **Service Deployment** - Starts all 11 services in correct order
8. **Database Init** - Runs migrations, creates admin user
9. **Status Display** - Shows running services and access URLs

## 🎯 Service Management

```bash
# Check what's running
./deploy-onprem.sh status

# Restart everything
./deploy-onprem.sh restart

# Stop everything
./deploy-onprem.sh stop

# Start everything
./deploy-onprem.sh start
```

## 🔍 Monitoring & Maintenance

```bash
# Run health check
./deploy-onprem.sh health

# Run backup
./deploy-onprem.sh backup

# Check logs
docker logs prs-onprem-backend
docker logs prs-onprem-postgres-timescale
```

## 🌐 Access URLs

After deployment, access these URLs:

- **Application**: https://192.168.16.100/
- **Grafana**: http://192.168.16.100:3001/
- **Prometheus**: http://192.168.16.100:9090/
- **Adminer**: http://192.168.16.100:8080/
- **Portainer**: http://192.168.16.100:9000/

## 🔐 Admin Credentials

After running `setup-env.sh`, credentials are saved in `ADMIN_CREDENTIALS.txt`:

```
Application: admin@local / [generated-password]
Grafana: admin / [generated-password]
Database: prs_user / [generated-password]
```

## 🚨 Troubleshooting

### Common Issues

**Services won't start:**
```bash
# Check Docker
sudo systemctl status docker

# Check logs
docker logs prs-onprem-backend
```

**Can't access HTTPS:**
```bash
# Check firewall
sudo ufw status

# Check nginx
docker logs prs-onprem-nginx
```

**Database issues:**
```bash
# Check database
docker exec prs-onprem-postgres-timescale pg_isready -U prs_user

# Check migrations
docker exec prs-onprem-backend npm run migrate
```

### Reset Everything

```bash
# Stop and remove everything
./deploy-onprem.sh stop
docker system prune -a

# Start fresh
./deploy-onprem.sh deploy
```

## 📁 File Structure

```
scripts/
├── deploy-onprem.sh          # Main deployment script (like deploy-ec2.sh)
├── setup-env.sh              # Environment setup with secrets
└── README.md                 # This file

Generated files:
├── 02-docker-configuration/.env     # Environment variables
└── ADMIN_CREDENTIALS.txt            # Access credentials
```

## 🔄 Comparison with EC2 Script

| Feature | EC2 `deploy-ec2.sh` | On-Premises `deploy-onprem.sh` |
|---------|--------------------|---------------------------------|
| **One-command deploy** | ✅ | ✅ |
| **Service management** | ✅ | ✅ |
| **Health checks** | ✅ | ✅ |
| **Status display** | ✅ | ✅ |
| **Network setup** | Cloudflare Tunnel | Internal network + SSL |
| **Storage** | Single EBS | Dual SSD/HDD |
| **Memory** | 4GB | 16GB optimized |
| **Users** | 30 concurrent | 100 concurrent |

## 💡 Pro Tips

1. **Always run `setup-env.sh` first** to generate secure secrets
2. **Customize the .env file** for your specific domain and settings
3. **Use `status` command** to check system health regularly
4. **Run `health` command** for comprehensive system validation
5. **Use `backup` command** to test backup procedures

---

**Just like your EC2 script, but optimized for on-premises! 🚀**
