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
1. **Point domain to office public IP** in GoDaddy DNS
2. **Create A record**: `prs.citylandcondo.com` → `[Office Public IP]` (NOT 192.168.0.100)
3. **Configure port forwarding**: Port 80 → 192.168.0.100:80 (temporary, for SSL cert generation)
4. **Optional internal DNS**: `prs.citylandcondo.com` → `192.168.0.100` (for office network performance)
5. **SSL automation** available post-deployment with IT coordination

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
chmod +x check-prerequisites.sh
./check-prerequisites.sh
```

---

## Essential System Preparation

### 1. System Updates (REQUIRED)

```bash
# Update package lists and upgrade system
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y curl wget git nano htop

# Reboot if kernel was updated
sudo reboot
```

### 2. GitHub CLI Installation (REQUIRED)

```bash
# Install GitHub CLI for repository access
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh

# Authenticate with GitHub
gh auth login
```

!!! warning "GitHub Authentication Required"
    The deploy script needs access to private repositories. You must complete `gh auth login` before deployment.

### 3. Clone PRS Deployment Repository (REQUIRED)

```bash
# Create base directory
sudo mkdir -p /opt/prs
sudo chown $USER:$USER /opt/prs

# Clone the deployment repository
cd /opt/prs
git clone https://github.com/stratpoint-engineering/prs-deployment.git

# Navigate to scripts directory
cd prs-deployment/scripts

# Make scripts executable
chmod +x *.sh
```

!!! info "Repository Structure"
    The deploy script expects `/opt/prs` as the base directory and will create additional application repositories there during deployment. The `prs-deployment` repository contains all the deployment scripts and configuration.

---

## Ready for Quick Start

Once you've completed:

1. **System updates** and GitHub CLI installation
2. **Storage mount points** setup (`/mnt/ssd` and `/mnt/hdd`)
3. **Network configuration** (static IP in 192.168.0.0/20 range)
4. **Domain DNS** pointing to your server
5. **Non-root user** with sudo access
6. **Prerequisites verification** (./check-prerequisites.sh)

**You're ready for the [Quick Start Guide](quick-start.md)!**

!!! success "What the Deploy Script Handles"
    After prerequisites are met, the deploy script automatically handles:
    - Docker installation and configuration
    - Package installation (curl, wget, git, htop, etc.)
    - Storage directory creation and permissions
    - Firewall configuration (UFW rules for 192.168.0.0/20)
    - SSL certificate generation (self-signed initially)
    - Service deployment and initialization

!!! tip "Time Investment"
    Proper prerequisite setup takes 30-60 minutes but prevents deployment failures and saves hours of troubleshooting later.
