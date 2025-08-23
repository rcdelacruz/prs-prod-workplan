# Prerequisites and Server Setup

!!! danger "Critical: Complete Before Quick Start"
    These prerequisites **must** be completed before running the Quick Start Guide. The `deploy-onprem.sh` script will **fail** without proper server setup.

## What the Deploy Script Handles vs. What You Must Do

### Deploy Script Handles Automatically:
- Docker installation and configuration
- Package installation (curl, wget, git, htop, etc.)
- Storage directory creation and permissions
- Firewall configuration (UFW rules)
- SSL certificate generation (self-signed)
- Service deployment and initialization

### You Must Setup First:
- **Server hardware and OS installation**
- **Storage mount points** (`/mnt/ssd` and `/mnt/hdd`)
- **Network configuration** (static IP, DNS)
- **Domain DNS records** (pointing to server)
- **Non-root user account** with sudo access

---

## Hardware Requirements

| Component | Minimum | Recommended | Purpose |
|-----------|---------|-------------|---------|
| **CPU** | 4 cores | 8+ cores | Application processing |
| **RAM** | 16GB | 32GB | Database and caching |
| **SSD Storage** | 100GB | 200GB+ | Hot data (database, cache) |
| **HDD Storage** | 500GB | 1TB+ | Backups and archives |
| **Network** | 1Gbps | 1Gbps+ | Office network connectivity |

## Operating System

**Required:** Ubuntu 24.04 LTS (deploy script optimized for this)
**Supported:** Ubuntu 22.04 LTS (with warnings)
**Installation:** Clean server installation (not desktop)

---

## Critical Setup Steps

### 1. Storage Mount Points (REQUIRED)

The deploy script **checks for these mount points** and will **fail** if they don't exist:

```bash
# Create mount points
sudo mkdir -p /mnt/ssd /mnt/hdd

# Example: Mount SSD for hot data
sudo mount /dev/nvme0n1p1 /mnt/ssd

# Example: Mount HDD for backups
sudo mount /dev/sdb1 /mnt/hdd

# Make mounts permanent
echo "/dev/nvme0n1p1 /mnt/ssd ext4 defaults 0 2" | sudo tee -a /etc/fstab
echo "/dev/sdb1 /mnt/hdd ext4 defaults 0 2" | sudo tee -a /etc/fstab

# Verify mounts
df -h /mnt/ssd /mnt/hdd
```

!!! danger "Deploy Script Requirement"
    The `check_prerequisites()` function will exit with error if `/mnt/ssd` or `/mnt/hdd` don't exist.

### 2. User Account Setup (REQUIRED)

```bash
# Create deployment user (if not using existing user)
sudo adduser prsadmin

# Add user to sudo group
sudo usermod -aG sudo prsadmin

# Switch to deployment user
su - prsadmin
```

!!! warning "Do Not Run as Root"
    The deploy script **checks** `if [[ $EUID -eq 0 ]]` and will **exit with error** if run as root.

### 3. Network Configuration

```bash
# Set static IP for office network
sudo nano /etc/netplan/00-installer-config.yaml
```

Example configuration:
```yaml
network:
  version: 2
  ethernets:
    ens18:  # Adjust interface name
      dhcp4: false
      addresses:
        - 192.168.0.100/20  # Your server IP within 192.168.0.0/20 range
      gateway4: 192.168.0.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

Apply configuration:
```bash
sudo netplan apply
```

### 4. Domain DNS Setup

#### For GoDaddy Domain (Recommended):
1. **Point domain to server IP** in GoDaddy DNS
2. **Create A record**: `prs.citylandcondo.com` → `192.168.0.100`
3. **SSL automation** available post-deployment

#### For Local Domain:
1. **Use local DNS** or hosts file
2. **Example**: `prs.office.local` → `192.168.0.100`
3. **Self-signed certificates** will be used

---

## Prerequisites Verification

**Run this verification script before Quick Start:**

```bash
#!/bin/bash
# Save as check-prerequisites.sh

echo "Checking PRS Deployment Prerequisites..."
echo ""

# Check OS
echo "Operating System:"
lsb_release -d

# Check RAM (deploy script requires 16GB+)
echo ""
echo "Memory:"
TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -lt 15 ]; then
    echo "FAIL: Insufficient RAM: ${TOTAL_RAM}GB (16GB required)"
else
    echo "PASS: RAM: ${TOTAL_RAM}GB"
fi

# Check storage mounts (CRITICAL - deploy script checks these)
echo ""
echo "Storage Mounts:"
if [ -d "/mnt/ssd" ]; then
    echo "PASS: /mnt/ssd exists"
    df -h /mnt/ssd 2>/dev/null || echo "   (not mounted)"
else
    echo "FAIL: /mnt/ssd missing - DEPLOY WILL FAIL"
fi

if [ -d "/mnt/hdd" ]; then
    echo "PASS: /mnt/hdd exists"
    df -h /mnt/hdd 2>/dev/null || echo "   (not mounted)"
else
    echo "FAIL: /mnt/hdd missing - DEPLOY WILL FAIL"
fi

# Check user (deploy script checks this)
echo ""
echo "User Account:"
if [ "$EUID" -eq 0 ]; then
    echo "FAIL: Running as root - DEPLOY WILL FAIL"
else
    echo "PASS: Running as non-root user: $USER"
fi

# Check network
echo ""
echo "Network:"
ip addr show | grep "inet " | grep -v "127.0.0.1"

echo ""
echo "Prerequisites Check Complete!"
echo ""
if [ -d "/mnt/ssd" ] && [ -d "/mnt/hdd" ] && [ "$EUID" -ne 0 ] && [ "$TOTAL_RAM" -ge 15 ]; then
    echo "PASS: Ready for Quick Start deployment!"
else
    echo "FAIL: Fix the issues above before proceeding with deployment."
fi
```

**Save and run:**
```bash
# Install Docker (Ubuntu/Debian)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installation
docker --version
docker-compose --version
```

**Required Versions:**
- Docker: 20.10+
- Docker Compose: 2.0+

### Version Control

```bash
# Install Git (Ubuntu/Debian)
sudo apt update
sudo apt install git

# Verify installation
git --version
```

**Required Version:** Git 2.25+

### Certificate Tools

```bash
# Install OpenSSL and certificate tools
sudo apt install openssl ca-certificates

# Install Certbot for Let's Encrypt (optional)
sudo apt install certbot
```

## Network Configuration

### Requirements

| Requirement | Specification | Purpose |
|-------------|---------------|---------|
| **Internal Network** | 192.168.0.0/20 | Client access network |
| **Server IP** | 192.168.0.100 | Fixed server address |
| **Service Network** | 172.20.0.0/24 | Container networking |
| **Internet Access** | Required | Updates and external APIs |
| **DNS Resolution** | Required | Domain name resolution |

### Configuration

**Required Open Ports:**

| Port | Protocol | Service | Access |
|------|----------|---------|---------|
| 22 | TCP | SSH | Admin access |
| 80 | TCP | HTTP | Web access |
| 443 | TCP | HTTPS | Secure web access |
| 3001 | TCP | Grafana | Monitoring (internal) |
| 8080 | TCP | Adminer | Database admin (internal) |
| 9000 | TCP | Portainer | Container admin (internal) |
| 9090 | TCP | Prometheus | Metrics (internal) |

### Configuration

**Required DNS Records:**
```
your-domain.com        A    192.168.0.100
grafana.your-domain.com A   192.168.0.100
admin.your-domain.com   A   192.168.0.100
```

## Storage Configuration

### Mount Points

**Required Mount Points:**
```bash
# SSD Storage (RAID1)
/mnt/ssd    # 470GB for hot data

# HDD Storage (RAID5)
/mnt/hdd    # 2.4TB for cold data and backups
```

### Preparation

```bash
# Create mount points
sudo mkdir -p /mnt/ssd /mnt/hdd

# Configure RAID (example for SSD RAID1)
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb /dev/sdc

# Format filesystems
sudo mkfs.ext4 /dev/md0
sudo mkfs.ext4 /dev/md1

# Add to fstab for persistent mounting
echo "/dev/md0 /mnt/ssd ext4 defaults,noatime,discard 0 2" | sudo tee -a /etc/fstab
echo "/dev/md1 /mnt/hdd ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab

# Mount filesystems
sudo mount -a
```

### Permissions

```bash
# Set proper ownership
sudo chown -R $USER:$USER /mnt/ssd /mnt/hdd

# Set permissions
sudo chmod 755 /mnt/ssd /mnt/hdd
```

## Security Prerequisites

### Certificates

**Option 1: Existing Certificates**
- Valid SSL certificate for your domain
- Private key file
- Certificate chain/bundle

**Option 2: Let's Encrypt (Automated)**
- Domain ownership verification
- DNS configuration completed
- Certbot installed

### Hardening

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install security tools
sudo apt install fail2ban ufw

# Configure basic firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
```

### Access

```bash
# Create deployment user (if needed)
sudo useradd -m -s /bin/bash prs-deploy
sudo usermod -aG docker,sudo prs-deploy

# Setup SSH key authentication
sudo mkdir -p /home/prs-deploy/.ssh
sudo cp ~/.ssh/authorized_keys /home/prs-deploy/.ssh/
sudo chown -R prs-deploy:prs-deploy /home/prs-deploy/.ssh
sudo chmod 700 /home/prs-deploy/.ssh
sudo chmod 600 /home/prs-deploy/.ssh/authorized_keys
```

## System Optimization

### Parameters

```bash
# Optimize for database workloads
echo "vm.swappiness = 10" | sudo tee -a /etc/sysctl.conf
echo "vm.dirty_ratio = 15" | sudo tee -a /etc/sysctl.conf
echo "vm.dirty_background_ratio = 5" | sudo tee -a /etc/sysctl.conf

# Network optimization
echo "net.core.rmem_max = 16777216" | sudo tee -a /etc/sysctl.conf
echo "net.core.wmem_max = 16777216" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_rmem = 4096 87380 16777216" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_wmem = 4096 65536 16777216" | sudo tee -a /etc/sysctl.conf

# Apply changes
sudo sysctl -p
```

### System Limits

```bash
# Increase file descriptor limits
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "root soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "root hard nofile 65536" | sudo tee -a /etc/security/limits.conf
```

## Pre-Deployment Checklist

### Validation

- [ ] **CPU**: 4+ cores available
- [ ] **RAM**: 16GB+ installed and recognized
- [ ] **SSD**: 470GB+ RAID1 configured and mounted
- [ ] **HDD**: 2.4TB+ RAID5 configured and mounted
- [ ] **Network**: 1Gbps interface configured
- [ ] **UPS**: Backup power system operational

### Validation

- [ ] **OS**: Ubuntu 20.04+ or equivalent installed
- [ ] **Docker**: Version 20.10+ installed and running
- [ ] **Docker Compose**: Version 2.0+ installed
- [ ] **Git**: Version 2.25+ installed
- [ ] **SSL Tools**: OpenSSL and certificate tools available

### Validation

- [ ] **IP Address**: Static IP 192.168.0.100 configured
- [ ] **DNS**: Domain name resolution working
- [ ] **Firewall**: Required ports open
- [ ] **Internet**: External connectivity available
- [ ] **SSL**: Certificates available or Let's Encrypt ready

### Validation

- [ ] **System Updates**: All packages updated
- [ ] **Firewall**: UFW or equivalent configured
- [ ] **SSH**: Key-based authentication configured
- [ ] **Users**: Deployment user created with proper permissions
- [ ] **Fail2ban**: Intrusion prevention configured

### Validation

- [ ] **Mount Points**: /mnt/ssd and /mnt/hdd available
- [ ] **Permissions**: Proper ownership and permissions set
- [ ] **Performance**: Storage performance tested
- [ ] **RAID**: RAID arrays healthy and monitored
- [ ] **Backup**: Backup storage accessible

## Validation Tests

### Performance Test

```bash
# CPU performance test
sysbench cpu --cpu-max-prime=20000 run

# Memory performance test
sysbench memory --memory-total-size=10G run

# Storage performance test
sudo fio --name=test --filename=/mnt/ssd/test --size=1G --rw=randwrite --bs=4k --numjobs=4 --time_based --runtime=30
```

### Connectivity Test

```bash
# Test internet connectivity
ping -c 4 8.8.8.8

# Test DNS resolution
nslookup your-domain.com

# Test port connectivity
nc -zv your-domain.com 443
```

### Functionality Test

```bash
# Test Docker installation
docker run hello-world

# Test Docker Compose
docker-compose --version

# Test container networking
docker network ls
```

---

!!! success "Prerequisites Complete"
    Once all prerequisites are met and validated, proceed to [Quick Start](quick-start.md) for rapid deployment.

!!! warning "Important"
    Ensure all validation tests pass before proceeding with the deployment to avoid issues during installation.
