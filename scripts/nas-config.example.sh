#!/bin/bash
# /opt/prs-deployment/scripts/nas-config.example.sh
# NAS Configuration Example for PRS Backup Integration
# Copy this file to nas-config.sh and customize for your environment

# =============================================================================
# NAS BACKUP CONFIGURATION
# =============================================================================

# Enable/Disable NAS backup integration
export BACKUP_TO_NAS="true"

# =============================================================================
# NAS CONNECTION SETTINGS
# =============================================================================

# NAS Server Configuration
export NAS_HOST="192.168.1.100"          # IP address or hostname of your NAS
export NAS_SHARE="backups"                # Share name on the NAS for backups

# Authentication (for CIFS/SMB shares)
export NAS_USERNAME="backup_user"         # Username for NAS access
export NAS_PASSWORD="secure_password"     # Password for NAS access

# Mount Point
export NAS_MOUNT_PATH="/mnt/nas"          # Local mount point for NAS

# =============================================================================
# BACKUP RETENTION POLICIES
# =============================================================================

# Local backup retention (days)
export LOCAL_RETENTION_DAYS=30

# NAS backup retention (days) - typically longer than local
export NAS_RETENTION_DAYS=90

# =============================================================================
# NAS TYPE SPECIFIC CONFIGURATIONS
# =============================================================================

# For CIFS/SMB NAS (Synology, QNAP, Windows shares)
# Uncomment and configure the following:
# export NAS_TYPE="cifs"
# export NAS_DOMAIN="WORKGROUP"           # Windows domain if applicable
# export NAS_VERSION="3.0"               # SMB version (1.0, 2.0, 2.1, 3.0)

# For NFS NAS
# Uncomment and configure the following:
# export NAS_TYPE="nfs"
# export NFS_OPTIONS="rw,sync,hard,intr"  # NFS mount options

# =============================================================================
# SECURITY SETTINGS
# =============================================================================

# File permissions on NAS
export NAS_FILE_MODE="0600"              # File permissions (owner read/write only)
export NAS_DIR_MODE="0700"               # Directory permissions (owner access only)

# Encryption settings
export ENCRYPT_NAS_BACKUPS="true"        # Encrypt backups before copying to NAS
export GPG_RECIPIENT="backup@prs.client-domain.com"  # GPG key for encryption

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

# Email notifications
export ADMIN_EMAIL="admin@prs.client-domain.com"

# Alert thresholds
export NAS_SPACE_WARNING_THRESHOLD=85    # Warn when NAS is 85% full
export NAS_SPACE_CRITICAL_THRESHOLD=95   # Critical alert when NAS is 95% full

# =============================================================================
# BACKUP VERIFICATION
# =============================================================================

# Enable backup verification
export VERIFY_NAS_BACKUPS="true"         # Verify backup integrity after copy
export VERIFY_CHECKSUM="true"            # Generate and verify checksums

# =============================================================================
# EXAMPLE CONFIGURATIONS FOR POPULAR NAS SYSTEMS
# =============================================================================

# Synology NAS Example:
# export NAS_HOST="synology.local"
# export NAS_SHARE="backup"
# export NAS_USERNAME="backup_user"
# export NAS_PASSWORD="your_password"

# QNAP NAS Example:
# export NAS_HOST="qnap.local"
# export NAS_SHARE="Backup"
# export NAS_USERNAME="admin"
# export NAS_PASSWORD="your_password"

# FreeNAS/TrueNAS Example (NFS):
# export NAS_HOST="truenas.local"
# export NAS_SHARE="/mnt/pool1/backups"
# export NAS_TYPE="nfs"

# Windows Server Share Example:
# export NAS_HOST="fileserver.domain.com"
# export NAS_SHARE="Backups$"
# export NAS_USERNAME="DOMAIN\\backup_user"
# export NAS_PASSWORD="your_password"
# export NAS_DOMAIN="DOMAIN"

# =============================================================================
# USAGE INSTRUCTIONS
# =============================================================================

# 1. Copy this file to nas-config.sh:
#    cp nas-config.example.sh nas-config.sh

# 2. Edit nas-config.sh with your NAS details:
#    nano nas-config.sh

# 3. Source the configuration in your backup scripts:
#    source /opt/prs-deployment/scripts/nas-config.sh

# 4. Test the NAS connection:
#    ./test-nas-connection.sh

# 5. Run a test backup:
#    ./backup-full.sh

# =============================================================================
# SECURITY NOTES
# =============================================================================

# - Store credentials securely and restrict file permissions:
#   chmod 600 nas-config.sh
#   chown root:root nas-config.sh

# - Consider using key-based authentication for NFS
# - Use strong passwords for CIFS/SMB authentication
# - Enable encryption for sensitive backup data
# - Regularly rotate backup credentials
# - Monitor NAS access logs for unauthorized access

echo "NAS configuration loaded successfully"
echo "NAS Host: $NAS_HOST"
echo "NAS Share: $NAS_SHARE"
echo "Backup to NAS: $BACKUP_TO_NAS"
