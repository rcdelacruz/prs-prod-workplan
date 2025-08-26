# Storage Configuration Examples

This document provides storage configuration examples for different server setups.

## 🔧 Configuration Overview

The PRS deployment system supports configurable storage paths through environment variables in `.env`:

```bash
# Storage Tier Paths (customize for your server setup)
STORAGE_SSD_PATH=/mnt/ssd                    # Fast storage for hot data
STORAGE_HDD_PATH=/mnt/hdd                    # Cold storage for old data
STORAGE_NAS_PATH=/mnt/nas                    # Network storage for backup/DR
```

## 📁 Common Server Configurations

### 1. Standard Linux Server (Default)
```bash
# .env configuration
STORAGE_SSD_PATH=/mnt/ssd
STORAGE_HDD_PATH=/mnt/hdd
STORAGE_NAS_PATH=/mnt/nas

# Mount points
/dev/nvme0n1p1 → /mnt/ssd    # NVMe SSD
/dev/sda1      → /mnt/hdd    # SATA HDD
//nas-server/share → /mnt/nas # CIFS/NFS mount
```

### 2. Ubuntu Server with Different Mount Points
```bash
# .env configuration
STORAGE_SSD_PATH=/media/nvme
STORAGE_HDD_PATH=/media/storage
STORAGE_NAS_PATH=/media/backup

# Mount points
/dev/nvme0n1p1 → /media/nvme     # NVMe SSD
/dev/sdb1      → /media/storage  # Large HDD
//backup-nas/prs → /media/backup # Network backup
```

### 3. CentOS/RHEL Server
```bash
# .env configuration
STORAGE_SSD_PATH=/opt/ssd
STORAGE_HDD_PATH=/opt/hdd
STORAGE_NAS_PATH=/opt/nas

# Mount points
/dev/nvme0n1p1 → /opt/ssd    # Fast storage
/dev/sda1      → /opt/hdd    # Bulk storage
nfs-server:/export/prs → /opt/nas # NFS mount
```

### 4. Single Disk Server (No Tiered Storage)
```bash
# .env configuration - Use same path for SSD and HDD
STORAGE_SSD_PATH=/var/lib/prs/hot
STORAGE_HDD_PATH=/var/lib/prs/cold
STORAGE_NAS_PATH=/mnt/backup

# All data on single disk with logical separation
/dev/sda1 → / (includes /var/lib/prs)
//backup-server/share → /mnt/backup
```

### 5. Cloud Server (AWS/Azure/GCP)
```bash
# .env configuration
STORAGE_SSD_PATH=/mnt/ebs-ssd
STORAGE_HDD_PATH=/mnt/ebs-hdd
STORAGE_NAS_PATH=/mnt/s3fs

# Cloud storage mounts
/dev/nvme1n1 → /mnt/ebs-ssd    # GP3 SSD volume
/dev/xvdf    → /mnt/ebs-hdd    # SC1 HDD volume
s3fs-bucket  → /mnt/s3fs       # S3 bucket mount
```

### 6. Docker Volume Configuration
```bash
# .env configuration - Using Docker volumes
STORAGE_SSD_PATH=/var/lib/docker/volumes/prs-ssd/_data
STORAGE_HDD_PATH=/var/lib/docker/volumes/prs-hdd/_data
STORAGE_NAS_PATH=/var/lib/docker/volumes/prs-nas/_data

# Docker volumes
docker volume create prs-ssd
docker volume create prs-hdd
docker volume create prs-nas
```

## 🛠️ Setup Instructions

### Step 1: Identify Your Storage Layout
```bash
# Check available disks
lsblk

# Check mount points
df -h

# Check disk types
lsblk -d -o name,rota
# rota=1: HDD, rota=0: SSD
```

### Step 2: Configure Storage Paths
```bash
# Edit the .env file
nano /opt/prs/prs-deployment/02-docker-configuration/.env

# Update storage paths according to your setup
STORAGE_SSD_PATH=/your/ssd/path
STORAGE_HDD_PATH=/your/hdd/path
STORAGE_NAS_PATH=/your/nas/path
```

### Step 3: Validate Configuration
```bash
# Run storage validation
./scripts/validate-storage-paths.sh

# This will:
# - Check if paths exist
# - Create missing directories
# - Set proper permissions
# - Test write performance
# - Generate configuration summary
```

### Step 4: Deploy with Custom Paths
```bash
# Deploy with validated configuration
./scripts/deploy-onprem.sh deploy
```

## 🔍 Troubleshooting

### Common Issues

#### 1. Permission Denied
```bash
# Fix ownership
sudo chown -R 999:999 /your/postgres/path
sudo chown -R $USER:$USER /your/app/path
```

#### 2. Mount Point Not Available
```bash
# Check if mounted
mountpoint /your/mount/path

# Mount manually if needed
sudo mount /dev/device /your/mount/path
```

#### 3. Insufficient Space
```bash
# Check available space
df -h /your/storage/path

# Clean up if needed
sudo du -sh /your/storage/path/*
```

### Validation Commands
```bash
# Test storage paths
./scripts/validate-storage-paths.sh

# Test all scripts
./scripts/test-all-scripts.sh

# Check deployment state
./scripts/deploy-onprem.sh check-state
```

## 📊 Performance Considerations

### SSD Storage (Hot Data)
- **Recommended**: NVMe SSD for best performance
- **Minimum**: SATA SSD
- **Size**: 100GB+ for database hot data
- **IOPS**: 3000+ for production workloads

### HDD Storage (Cold Data)
- **Recommended**: 7200 RPM SATA HDD
- **Minimum**: 5400 RPM HDD
- **Size**: 500GB+ for long-term storage
- **Purpose**: Archived data, backups, logs

### NAS Storage (Backup/DR)
- **Protocol**: CIFS/SMB or NFS
- **Network**: Gigabit Ethernet minimum
- **Redundancy**: RAID 1/5/6 recommended
- **Purpose**: Disaster recovery, off-site backup

## 🔐 Security Considerations

### File Permissions
```bash
# PostgreSQL data directories
chmod 700 /your/postgres/paths
chown 999:999 /your/postgres/paths

# Application directories
chmod 755 /your/app/paths
chown $USER:$USER /your/app/paths

# Backup directories
chmod 750 /your/backup/paths
chown $USER:backup /your/backup/paths
```

### Network Storage Security
```bash
# Use credentials file for CIFS
echo "username=user" > /etc/cifs-credentials
echo "password=pass" >> /etc/cifs-credentials
chmod 600 /etc/cifs-credentials

# Mount with credentials
mount -t cifs //server/share /mnt/nas -o credentials=/etc/cifs-credentials
```

## 📝 Configuration Validation Checklist

- [ ] Storage paths exist and are accessible
- [ ] Proper permissions set (PostgreSQL: 999:999, App: user:user)
- [ ] Sufficient disk space available
- [ ] Mount points persistent across reboots (/etc/fstab)
- [ ] Network storage accessible and authenticated
- [ ] Backup paths configured and tested
- [ ] Performance meets requirements (SSD: fast, HDD: adequate)

## 🚀 Next Steps

1. **Configure your .env file** with appropriate storage paths
2. **Run validation script**: `./scripts/validate-storage-paths.sh`
3. **Test all scripts**: `./scripts/test-all-scripts.sh`
4. **Deploy system**: `./scripts/deploy-onprem.sh deploy`
5. **Monitor storage usage**: Regular capacity monitoring
