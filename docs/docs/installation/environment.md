# Environment Setup

## Overview

This guide covers the complete environment setup for the PRS on-premises deployment, including system preparation, dependency installation, and initial configuration.

## System Preparation

### System Requirements

**Supported Operating Systems:**
- Ubuntu 20.04 LTS or later (Recommended: Ubuntu 22.04 LTS)
- CentOS 8 or later
- RHEL 8 or later
- Debian 11 or later

### Updates

```bash
# Update package lists and system
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y curl wget git vim htop tree unzip

# Install build tools
sudo apt install -y build-essential software-properties-common apt-transport-https ca-certificates gnupg lsb-release
```

### Setup

```bash
# Create deployment user (if not exists)
sudo useradd -m -s /bin/bash prs-deploy
sudo usermod -aG sudo prs-deploy

# Setup SSH key authentication
sudo mkdir -p /home/prs-deploy/.ssh
sudo cp ~/.ssh/authorized_keys /home/prs-deploy/.ssh/
sudo chown -R prs-deploy:prs-deploy /home/prs-deploy/.ssh
sudo chmod 700 /home/prs-deploy/.ssh
sudo chmod 600 /home/prs-deploy/.ssh/authorized_keys

# Switch to deployment user
sudo su - prs-deploy
```

## Docker Installation

### Docker Engine

```bash
# Remove old Docker versions
sudo apt remove docker docker-engine docker.io containerd runc

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Verify installation
docker --version
docker run hello-world
```

### Docker Compose

```bash
# Download Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Make executable
sudo chmod +x /usr/local/bin/docker-compose

# Create symlink for easier access
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify installation
docker-compose --version
```

### Configuration

```bash
# Configure Docker daemon
sudo tee /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "default-address-pools": [
    {
      "base": "172.20.0.0/16",
      "size": 24
    }
  ]
}
EOF

# Restart Docker
sudo systemctl restart docker
sudo systemctl enable docker
```

## Repository Setup

### Deployment Repository

```bash
# Navigate to deployment directory
cd /opt

# Clone deployment repository
sudo git clone https://github.com/your-org/prs-deployment.git
sudo chown -R $USER:$USER /opt/prs-deployment
cd /opt/prs-deployment

# Verify repository structure
tree -L 2
```

### Repository Configuration

```bash
# Copy repository configuration template
cp scripts/repo-config.example.sh scripts/repo-config.sh

# Edit repository configuration
nano scripts/repo-config.sh
```

**Repository Configuration:**
```bash
#!/bin/bash

# Repository Configuration for PRS Deployment

# Base directory for repositories
export REPOS_BASE_DIR="/opt/prs"

# Repository names
export BACKEND_REPO_NAME="prs-backend-a"
export FRONTEND_REPO_NAME="prs-frontend-a"

# Repository URLs
export BACKEND_REPO_URL="https://github.com/your-org/prs-backend-a.git"
export FRONTEND_REPO_URL="https://github.com/your-org/prs-frontend-a.git"

# Branch configuration
export BACKEND_BRANCH="main"
export FRONTEND_BRANCH="main"

# Build configuration
export NODE_ENV="production"
export BUILD_TARGET="production"
```

## Environment Configuration

### Environment Setup

```bash
# Run automated environment setup
cd /opt/prs-deployment/scripts
chmod +x setup-env.sh
./setup-env.sh
```

The script will:
1. Create environment file from template
2. Generate secure passwords and secrets
3. Configure basic settings
4. Prompt for custom configuration

### Environment Configuration

```bash
# Copy environment template
cp 02-docker-configuration/.env.example 02-docker-configuration/.env

# Edit environment file
nano 02-docker-configuration/.env
```

### Environment Variables

#### and Network Configuration

```bash
# Domain configuration
DOMAIN=your-domain.com
SERVER_IP=192.168.0.100
NETWORK_SUBNET=192.168.0.0/20
NETWORK_GATEWAY=192.168.0.1

# SSL configuration
SSL_EMAIL=admin@your-domain.com
ENABLE_SSL=true
```

#### Configuration

```bash
# PostgreSQL configuration
POSTGRES_DB=prs_production
POSTGRES_USER=prs_admin
POSTGRES_PASSWORD=your_secure_password_here
POSTGRES_PORT=5432

# Database performance settings
POSTGRES_MAX_CONNECTIONS=150
POSTGRES_SHARED_BUFFERS=2GB
POSTGRES_EFFECTIVE_CACHE_SIZE=4GB
POSTGRES_WORK_MEM=32MB
POSTGRES_MAINTENANCE_WORK_MEM=512MB
```

#### Secrets

```bash
# Generate secure secrets
JWT_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32)
OTP_KEY=$(openssl rand -base64 16)
PASS_SECRET=$(openssl rand -base64 32)

# Redis configuration
REDIS_PASSWORD=$(openssl rand -base64 32)
REDIS_MEMORY_LIMIT=2g
```

#### API Configuration

```bash
# Cityland API integration
CITYLAND_API_URL=https://your-api-endpoint.com
CITYLAND_ACCOUNTING_URL=https://your-accounting-endpoint.com
CITYLAND_API_USERNAME=your_api_username
CITYLAND_API_PASSWORD=your_api_password
```

#### Configuration

```bash
# Grafana configuration
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
GRAFANA_PORT=3001

# Prometheus configuration
PROMETHEUS_RETENTION_TIME=30d
PROMETHEUS_RETENTION_SIZE=10GB

# Enable monitoring
PROMETHEUS_ENABLED=true
ENABLE_METRICS=true
ENABLE_HEALTH_CHECKS=true
```

## Storage Setup

### Storage Setup

```bash
# Run storage setup script
cd /opt/prs-deployment/scripts
sudo ./setup-storage.sh
```

### Storage Setup

```bash
# Create SSD storage directories
sudo mkdir -p /mnt/hdd/{postgresql-hot,redis-data,uploads,logs,nginx-cache,prometheus-data,grafana-data,portainer-data}

# Create HDD storage directories
sudo mkdir -p /mnt/hdd/{postgresql-cold,postgres-backups,app-logs-archive,redis-backups,prometheus-archive}

# Set ownership for PostgreSQL
sudo chown -R 999:999 /mnt/hdd/postgresql-hot /mnt/hdd/postgresql-cold /mnt/hdd/postgres-backups

# Set ownership for Redis
sudo chown -R 999:999 /mnt/hdd/redis-data /mnt/hdd/redis-backups

# Set ownership for Grafana
sudo chown -R 472:472 /mnt/hdd/grafana-data

# Set ownership for Prometheus
sudo chown -R 65534:65534 /mnt/hdd/prometheus-data /mnt/hdd/prometheus-archive

# Set ownership for Nginx
sudo chown -R www-data:www-data /mnt/hdd/nginx-cache /mnt/hdd/uploads

# Set ownership for application logs
sudo chown -R 1000:1000 /mnt/hdd/logs /mnt/hdd/app-logs-archive

# Set permissions
sudo chmod 700 /mnt/hdd/postgresql-hot /mnt/hdd/postgresql-cold
sudo chmod 755 /mnt/hdd/redis-data /mnt/hdd/uploads /mnt/hdd/logs
sudo chmod 755 /mnt/hdd/postgres-backups /mnt/hdd/app-logs-archive
```

### Storage Setup

```bash
# Check storage structure
tree /mnt/hdd /mnt/hdd

# Check permissions
ls -la /mnt/hdd/
ls -la /mnt/hdd/

# Check disk space
df -h /mnt/hdd /mnt/hdd
```

## Security Setup

### Configuration

```bash
# Install and configure UFW
sudo apt install ufw

# Reset firewall rules
sudo ufw --force reset

# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (restrict to admin network)
sudo ufw allow from 192.168.0.201/24 to any port 22

# Allow HTTP/HTTPS (internal network)
sudo ufw allow from 192.168.0.0/20 to any port 80
sudo ufw allow from 192.168.0.0/20 to any port 443

# Allow management interfaces (admin only)
sudo ufw allow from 192.168.0.201/24 to any port 8080  # Adminer
sudo ufw allow from 192.168.0.201/24 to any port 3001  # Grafana
sudo ufw allow from 192.168.0.201/24 to any port 9000  # Portainer
sudo ufw allow from 192.168.0.201/24 to any port 9090  # Prometheus

# Enable firewall
sudo ufw --force enable

# Check status
sudo ufw status verbose
```

### Hardening

```bash
# Install fail2ban
sudo apt install fail2ban

# Configure fail2ban
sudo tee /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

# Start fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### Certificate Preparation

```bash
# Create SSL directory
sudo mkdir -p /opt/prs-deployment/02-docker-configuration/ssl

# Set permissions
sudo chmod 755 /opt/prs-deployment/02-docker-configuration/ssl

# Option 1: Copy existing certificates
sudo cp /path/to/your/certificate.crt /opt/prs-deployment/02-docker-configuration/ssl/
sudo cp /path/to/your/private.key /opt/prs-deployment/02-docker-configuration/ssl/
sudo cp /path/to/your/ca-bundle.crt /opt/prs-deployment/02-docker-configuration/ssl/

# Option 2: Generate self-signed certificate (development only)
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/prs-deployment/02-docker-configuration/ssl/private.key \
  -out /opt/prs-deployment/02-docker-configuration/ssl/certificate.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=your-domain.com"
```

## System Optimization

### Parameters

```bash
# Optimize for database workloads
sudo tee -a /etc/sysctl.conf << EOF
# Memory management
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 2
vm.overcommit_ratio = 80

# Network optimization
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.somaxconn = 65536
net.core.netdev_max_backlog = 5000

# File system
fs.file-max = 2097152
fs.nr_open = 1048576
EOF

# Apply changes
sudo sysctl -p
```

### Limits

```bash
# Increase file descriptor limits
sudo tee -a /etc/security/limits.conf << EOF
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536
EOF

# Update systemd limits
sudo tee /etc/systemd/system.conf.d/limits.conf << EOF
[Manager]
DefaultLimitNOFILE=65536
EOF
```

## Environment Validation

### Validation

```bash
# Check system resources
free -h
df -h
lscpu
lsblk

# Check network configuration
ip addr show
ip route show
ping -c 4 8.8.8.8

# Check Docker installation
docker --version
docker-compose --version
docker run hello-world
```

### Validation

```bash
# Check storage mounts
mount | grep -E "(ssd|hdd)"

# Check storage permissions
ls -la /mnt/hdd/
ls -la /mnt/hdd/

# Test storage performance
sudo fio --name=test --filename=/mnt/hdd/test --size=1G --rw=randwrite --bs=4k --numjobs=1 --time_based --runtime=30
```

### Validation

```bash
# Check firewall status
sudo ufw status verbose

# Check fail2ban status
sudo systemctl status fail2ban

# Check SSL certificates
openssl x509 -in /opt/prs-deployment/02-docker-configuration/ssl/certificate.crt -text -noout
```

### File Validation

```bash
# Check environment file
cat /opt/prs-deployment/02-docker-configuration/.env | grep -v PASSWORD

# Validate required variables
grep -E "(DOMAIN|POSTGRES_DB|JWT_SECRET)" /opt/prs-deployment/02-docker-configuration/.env
```

## Pre-Deployment Checklist

- [ ] **Operating System**: Ubuntu 20.04+ installed and updated
- [ ] **Docker**: Docker and Docker Compose installed and working
- [ ] **Storage**: SSD and HDD storage mounted and configured
- [ ] **Network**: Network interfaces configured and tested
- [ ] **Security**: Firewall and fail2ban configured
- [ ] **SSL**: SSL certificates available and configured
- [ ] **Environment**: Environment variables configured
- [ ] **Repositories**: Repository configuration completed
- [ ] **Permissions**: File and directory permissions set correctly
- [ ] **Performance**: System optimization applied

---

!!! success "Environment Ready"
    Once all validation steps pass, your environment is ready for Docker configuration and deployment.

!!! tip "Next Steps"
    Proceed to [Docker Configuration](docker.md) to configure the container environment.
