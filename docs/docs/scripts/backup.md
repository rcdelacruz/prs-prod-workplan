# Backup Scripts

## Overview

This guide covers all backup-related scripts in the PRS on-premises deployment, including automated backup procedures, restoration scripts, backup management utilities, and **NAS (Network Attached Storage) integration** for enterprise-grade backup redundancy.

## NAS Integration

The PRS backup system now includes comprehensive NAS integration for off-site backup storage, providing enhanced disaster recovery capabilities and compliance with enterprise backup requirements.

### NAS Features

- **Multi-protocol support**: CIFS/SMB and NFS
- **Automatic mounting/unmounting** of NAS shares
- **Dual retention policies**: Local (30 days) + NAS (90 days)
- **Backup verification** and integrity checking
- **Graceful degradation** if NAS is unavailable
- **Enterprise security** with encryption and secure credentials

### NAS Configuration

#### Step 1: Configure NAS Settings

```bash
# Copy the NAS configuration template
cp /opt/prs-deployment/scripts/nas-config.example.sh /opt/prs-deployment/scripts/nas-config.sh

# Edit with your NAS details
nano /opt/prs-deployment/scripts/nas-config.sh

# Secure the configuration file
chmod 600 /opt/prs-deployment/scripts/nas-config.sh
chown root:root /opt/prs-deployment/scripts/nas-config.sh
```

#### Step 2: NAS Configuration Examples

**Synology NAS (CIFS/SMB):**
```bash
export BACKUP_TO_NAS="true"
export NAS_HOST="synology.local"
export NAS_SHARE="backup"
export NAS_USERNAME="backup_user"
export NAS_PASSWORD="your_secure_password"
export NAS_MOUNT_PATH="/mnt/nas"
```

**QNAP NAS (CIFS/SMB):**
```bash
export BACKUP_TO_NAS="true"
export NAS_HOST="qnap.local"
export NAS_SHARE="Backup"
export NAS_USERNAME="admin"
export NAS_PASSWORD="your_secure_password"
export NAS_MOUNT_PATH="/mnt/nas"
```

**FreeNAS/TrueNAS (NFS):**
```bash
export BACKUP_TO_NAS="true"
export NAS_HOST="truenas.local"
export NAS_SHARE="/mnt/pool1/backups"
export NAS_MOUNT_PATH="/mnt/nas"
# No username/password needed for NFS
```

#### Step 3: Test NAS Connection

```bash
# Test NAS connectivity and functionality
/opt/prs-deployment/scripts/test-nas-connection.sh
```

#### Step 4: Environment Variables

Add to your `.env` file:
```bash
# NAS Backup Configuration
BACKUP_TO_NAS=true
NAS_HOST=your-nas-hostname
NAS_SHARE=backups
NAS_USERNAME=backup_user
NAS_PASSWORD=secure_password
NAS_MOUNT_PATH=/mnt/nas
NAS_RETENTION_DAYS=90
```

## Core Backup Scripts

### Full Database Backup Script with NAS Integration

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/backup-full.sh
# Comprehensive database backup with verification and NAS integration

set -euo pipefail

# Configuration
LOCAL_BACKUP_DIR="/mnt/hdd/postgres-backups/daily"
NAS_BACKUP_DIR="${NAS_MOUNT_PATH:-/mnt/nas}/postgres-backups/daily"
RETENTION_DAYS=30
NAS_RETENTION_DAYS=90
COMPRESSION_LEVEL=9
ENCRYPT_KEY="backup@prs.client-domain.com"
LOG_FILE="/var/log/prs-backup.log"

# NAS Configuration
NAS_ENABLED="${BACKUP_TO_NAS:-true}"
NAS_HOST="${NAS_HOST:-}"
NAS_SHARE="${NAS_SHARE:-backups}"
NAS_USERNAME="${NAS_USERNAME:-}"
NAS_PASSWORD="${NAS_PASSWORD:-}"
NAS_MOUNT_PATH="${NAS_MOUNT_PATH:-/mnt/nas}"

# Database connection settings (from docker-compose)
PGHOST="prs-onprem-postgres-timescale"
PGPORT="5432"
PGUSER="${POSTGRES_USER:-prs_user}"
PGDATABASE="${POSTGRES_DB:-prs_production}"

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_message "ERROR: $1"
    exit 1
}

# NAS mounting function
mount_nas() {
    if [ "$NAS_ENABLED" != "true" ]; then
        log_message "NAS backup disabled, skipping NAS mount"
        return 0
    fi

    if [ -z "$NAS_HOST" ]; then
        log_message "WARNING: NAS_HOST not configured, skipping NAS backup"
        return 1
    fi

    log_message "Mounting NAS for backup storage"
    mkdir -p "$NAS_MOUNT_PATH"

    if mountpoint -q "$NAS_MOUNT_PATH"; then
        log_message "NAS already mounted at $NAS_MOUNT_PATH"
        return 0
    fi

    # Mount NAS (supports both CIFS/SMB and NFS)
    if [ -n "$NAS_USERNAME" ] && [ -n "$NAS_PASSWORD" ]; then
        # CIFS/SMB mount
        mount -t cifs "//$NAS_HOST/$NAS_SHARE" "$NAS_MOUNT_PATH" \
            -o username="$NAS_USERNAME",password="$NAS_PASSWORD",uid=0,gid=0,file_mode=0600,dir_mode=0700
    else
        # NFS mount
        mount -t nfs "$NAS_HOST:/$NAS_SHARE" "$NAS_MOUNT_PATH"
    fi

    log_message "NAS mounted successfully at $NAS_MOUNT_PATH"
}

# Copy backup to NAS
copy_to_nas() {
    local backup_file="$1"

    if [ "$NAS_ENABLED" != "true" ] || ! mountpoint -q "$NAS_MOUNT_PATH"; then
        return 0
    fi

    log_message "Copying backup to NAS"
    mkdir -p "$NAS_BACKUP_DIR"

    local backup_filename=$(basename "$backup_file")
    local nas_backup_file="$NAS_BACKUP_DIR/$backup_filename"

    if cp "$backup_file" "$nas_backup_file"; then
        log_message "Backup copied to NAS: $nas_backup_file"

        # Copy checksum file if it exists
        if [ -f "${backup_file}.sha256" ]; then
            cp "${backup_file}.sha256" "${nas_backup_file}.sha256"
        fi

        # Verify NAS copy
        local local_size=$(stat -c%s "$backup_file")
        local nas_size=$(stat -c%s "$nas_backup_file")

        if [ "$local_size" -eq "$nas_size" ]; then
            log_message "NAS copy verified: $(numfmt --to=iec $nas_size)"
        else
            log_message "ERROR: NAS copy size mismatch"
            return 1
        fi
    else
        log_message "ERROR: Failed to copy backup to NAS"
        return 1
    fi
}

# Main backup function
main() {
    local DATE=$(date +%Y%m%d_%H%M%S)
    local BACKUP_FILE="$LOCAL_BACKUP_DIR/prs_full_backup_${DATE}.sql"

    log_message "Starting full database backup with NAS integration"

    # Mount NAS if enabled
    if [ "$NAS_ENABLED" = "true" ]; then
        mount_nas || log_message "WARNING: NAS mount failed, continuing with local backup only"
    fi

    # Create local backup directory
    mkdir -p "$LOCAL_BACKUP_DIR" || error_exit "Failed to create local backup directory"

    # Pre-backup checks
    log_message "Performing pre-backup checks"

    # Check database connectivity
    if ! docker exec prs-onprem-postgres-timescale pg_isready -U "$PGUSER"; then
        error_exit "Database not ready"
    fi

    # Check available space (require 5GB free)
    local AVAILABLE_SPACE=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 5000000 ]; then
        error_exit "Insufficient disk space for backup"
    fi

    # Create backup
    log_message "Creating database backup: $BACKUP_FILE"
    if ! docker exec prs-onprem-postgres-timescale pg_dump \
        -U "$PGUSER" \
        -d "$PGDATABASE" \
        --verbose \
        --format=custom \
        --compress=9 \
        --no-owner \
        --no-privileges \
        > "$BACKUP_FILE"; then
        error_exit "Database backup failed"
    fi

    # Verify backup size
    local BACKUP_SIZE=$(stat -c%s "$BACKUP_FILE")
    if [ "$BACKUP_SIZE" -lt 1000000 ]; then  # At least 1MB
        error_exit "Backup file too small, possible corruption"
    fi

    # Compress backup
    log_message "Compressing backup"
    gzip -"$COMPRESSION_LEVEL" "$BACKUP_FILE"
    BACKUP_FILE="${BACKUP_FILE}.gz"

    # Generate checksum
    log_message "Generating checksum"
    sha256sum "$BACKUP_FILE" > "${BACKUP_FILE}.sha256"

    # Encrypt backup (if GPG key available)
    if command -v gpg >/dev/null 2>&1 && gpg --list-keys "$ENCRYPT_KEY" >/dev/null 2>&1; then
        log_message "Encrypting backup"
        gpg --trust-model always --encrypt -r "$ENCRYPT_KEY" "$BACKUP_FILE"
        rm "$BACKUP_FILE"
        BACKUP_FILE="${BACKUP_FILE}.gpg"
    fi

    # Final verification
    local FINAL_SIZE=$(stat -c%s "$BACKUP_FILE")
    log_message "Local backup completed: $BACKUP_FILE ($(numfmt --to=iec $FINAL_SIZE))"

    # Copy to NAS
    if [ "$NAS_ENABLED" = "true" ]; then
        copy_to_nas "$BACKUP_FILE" || log_message "WARNING: NAS copy failed"
    fi

    # Cleanup old local backups
    log_message "Cleaning up old local backups (retention: $RETENTION_DAYS days)"
    find "$LOCAL_BACKUP_DIR" -name "prs_full_backup_*.sql*" -mtime +$RETENTION_DAYS -delete

    # Cleanup old NAS backups
    if [ "$NAS_ENABLED" = "true" ] && mountpoint -q "$NAS_MOUNT_PATH"; then
        log_message "Cleaning up old NAS backups (retention: $NAS_RETENTION_DAYS days)"
        find "$NAS_BACKUP_DIR" -name "prs_full_backup_*.sql*" -mtime +$NAS_RETENTION_DAYS -delete 2>/dev/null || true
    fi

    # Send notification
    if command -v mail >/dev/null 2>&1; then
        local backup_status="Local backup completed"
        if [ "$NAS_ENABLED" = "true" ] && mountpoint -q "$NAS_MOUNT_PATH"; then
            backup_status="Local and NAS backup completed"
        fi

        echo "PRS Database backup completed successfully at $(date). Status: $backup_status" | \
        mail -s "PRS Database Backup Success" "${ADMIN_EMAIL:-admin@prs.client-domain.com}"
    fi

    # Unmount NAS
    if [ "$NAS_ENABLED" = "true" ] && mountpoint -q "$NAS_MOUNT_PATH"; then
        umount "$NAS_MOUNT_PATH" || log_message "WARNING: Failed to unmount NAS"
    fi

    log_message "Full backup process completed successfully"
}

# Execute main function
main "$@"
```

### NAS Connection Test Script

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/test-nas-connection.sh
# Test NAS connectivity and backup functionality for PRS deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/prs-nas-test.log"

# Load NAS configuration
if [ -f "$SCRIPT_DIR/nas-config.sh" ]; then
    source "$SCRIPT_DIR/nas-config.sh"
else
    echo "ERROR: nas-config.sh not found. Please copy nas-config.example.sh to nas-config.sh and configure it."
    exit 1
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

test_nas_connectivity() {
    log_message "Testing NAS connectivity"

    # Test network connectivity
    if ping -c 3 "$NAS_HOST" >/dev/null 2>&1; then
        log_message "✅ Network connectivity to NAS successful"
    else
        log_message "❌ Network connectivity to NAS failed"
        return 1
    fi

    # Test specific ports
    if [ -n "$NAS_USERNAME" ]; then
        # Test SMB/CIFS ports
        if timeout 5 bash -c "</dev/tcp/$NAS_HOST/445" 2>/dev/null; then
            log_message "✅ SMB/CIFS port 445 accessible"
        else
            log_message "❌ SMB/CIFS port 445 not accessible"
            return 1
        fi
    else
        # Test NFS port
        if timeout 5 bash -c "</dev/tcp/$NAS_HOST/2049" 2>/dev/null; then
            log_message "✅ NFS port 2049 accessible"
        else
            log_message "❌ NFS port 2049 not accessible"
            return 1
        fi
    fi
}

test_nas_mount() {
    log_message "Testing NAS mount functionality"

    mkdir -p "$NAS_MOUNT_PATH"

    if [ -n "$NAS_USERNAME" ] && [ -n "$NAS_PASSWORD" ]; then
        # CIFS/SMB mount
        if mount -t cifs "//$NAS_HOST/$NAS_SHARE" "$NAS_MOUNT_PATH" \
            -o username="$NAS_USERNAME",password="$NAS_PASSWORD",uid=0,gid=0; then
            log_message "✅ CIFS/SMB mount successful"
        else
            log_message "❌ CIFS/SMB mount failed"
            return 1
        fi
    else
        # NFS mount
        if mount -t nfs "$NAS_HOST:/$NAS_SHARE" "$NAS_MOUNT_PATH"; then
            log_message "✅ NFS mount successful"
        else
            log_message "❌ NFS mount failed"
            return 1
        fi
    fi
}

test_nas_read_write() {
    log_message "Testing NAS read/write functionality"

    local test_file="$NAS_MOUNT_PATH/prs-test-$(date +%s).txt"
    local test_data="PRS NAS Test - $(date)"

    # Write test
    if echo "$test_data" > "$test_file"; then
        log_message "✅ NAS file write successful"
    else
        log_message "❌ NAS file write failed"
        return 1
    fi

    # Read test
    if [ "$(cat "$test_file")" = "$test_data" ]; then
        log_message "✅ NAS file read successful"
    else
        log_message "❌ NAS file read failed"
        return 1
    fi

    # Cleanup
    rm -f "$test_file"
}

main() {
    log_message "Starting NAS connection test"

    if test_nas_connectivity && test_nas_mount && test_nas_read_write; then
        log_message "🎉 All NAS tests passed successfully!"

        # Cleanup
        if mountpoint -q "$NAS_MOUNT_PATH"; then
            umount "$NAS_MOUNT_PATH"
        fi

        echo "✅ Your NAS is ready for PRS backup integration"
    else
        log_message "❌ NAS tests failed"
        exit 1
    fi
}

main "$@"
```

### Incremental Backup Script

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/backup-incremental.sh
# Incremental backup using WAL files

set -euo pipefail

BACKUP_DIR="/mnt/hdd/postgres-backups/incremental"
WAL_ARCHIVE_DIR="/mnt/hdd/wal-archive"
RETENTION_DAYS=7
LOG_FILE="/var/log/prs-backup.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

main() {
    local DATE=$(date +%Y%m%d_%H%M%S)
    local INCREMENTAL_FILE="$BACKUP_DIR/prs_incremental_backup_${DATE}.tar.gz"

    log_message "Starting incremental backup"

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Find WAL files since last full backup
    local LAST_FULL_BACKUP=$(ls -t /mnt/hdd/postgres-backups/daily/prs_full_backup_*.sql* 2>/dev/null | head -1)

    if [ -z "$LAST_FULL_BACKUP" ]; then
        log_message "No full backup found, running full backup first"
        /opt/prs-deployment/scripts/backup-full.sh
        return 0
    fi

    log_message "Base backup: $LAST_FULL_BACKUP"

    # Create incremental backup with WAL files newer than last full backup
    log_message "Creating incremental backup: $INCREMENTAL_FILE"

    if find "$WAL_ARCHIVE_DIR" -name "*.wal" -newer "$LAST_FULL_BACKUP" -print0 | \
       tar --null -czf "$INCREMENTAL_FILE" --files-from=-; then
        log_message "Incremental backup completed successfully"
    else
        log_message "ERROR: Incremental backup failed"
        return 1
    fi

    # Generate checksum
    sha256sum "$INCREMENTAL_FILE" > "${INCREMENTAL_FILE}.sha256"

    # Cleanup old incremental backups
    find "$BACKUP_DIR" -name "prs_incremental_backup_*.tar.gz*" -mtime +$RETENTION_DAYS -delete

    local BACKUP_SIZE=$(stat -c%s "$INCREMENTAL_FILE")
    log_message "Incremental backup completed: $INCREMENTAL_FILE ($(numfmt --to=iec $BACKUP_SIZE))"
}

main "$@"
```

### Application Data Backup Script

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/backup-application-data.sh
# Backup application files and uploads

set -euo pipefail

BACKUP_DIR="/mnt/hdd/app-backups"
RETENTION_DAYS=14
LOG_FILE="/var/log/prs-backup.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

main() {
    local DATE=$(date +%Y%m%d_%H%M%S)
    local APP_BACKUP_DIR="$BACKUP_DIR/$DATE"

    log_message "Starting application data backup"

    # Create backup directory
    mkdir -p "$APP_BACKUP_DIR"

    # Backup uploads directory
    log_message "Backing up uploads directory"
    if [ -d "/mnt/hdd/uploads" ]; then
        tar -czf "$APP_BACKUP_DIR/uploads.tar.gz" -C /mnt/hdd uploads/
        log_message "Uploads backup completed"
    fi

    # Backup configuration
    log_message "Backing up configuration"
    tar -czf "$APP_BACKUP_DIR/configuration.tar.gz" \
        -C /opt/prs-deployment 02-docker-configuration/

    # Backup SSL certificates
    log_message "Backing up SSL certificates"
    if [ -d "/opt/prs-deployment/02-docker-configuration/ssl" ]; then
        tar -czf "$APP_BACKUP_DIR/ssl-certificates.tar.gz" \
            -C /opt/prs-deployment/02-docker-configuration ssl/
    fi

    # Backup logs (recent only)
    log_message "Backing up recent logs"
    find /mnt/hdd/logs -name "*.log" -mtime -7 | \
    tar -czf "$APP_BACKUP_DIR/recent-logs.tar.gz" --files-from=-

    # Generate manifest
    cat > "$APP_BACKUP_DIR/manifest.txt" << EOF
PRS Application Data Backup
Date: $(date)
Hostname: $(hostname)
Backup Contents:
- uploads.tar.gz: User uploaded files
- configuration.tar.gz: Docker configuration
- ssl-certificates.tar.gz: SSL certificates
- recent-logs.tar.gz: Application logs (7 days)

Backup Size: $(du -sh "$APP_BACKUP_DIR" | cut -f1)
EOF

    # Cleanup old backups
    find "$BACKUP_DIR" -maxdepth 1 -type d -name "20*" -mtime +$RETENTION_DAYS -exec rm -rf {} \;

    log_message "Application data backup completed: $APP_BACKUP_DIR"
}

main "$@"
```

## Restoration Scripts

### Database Restoration Script

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/restore-database.sh
# Restore database from backup

set -euo pipefail

BACKUP_FILE="$1"
TARGET_DB="${2:-prs_production}"
LOG_FILE="/var/log/prs-restore.log"

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup-file> [target-database]"
    echo "Available backups:"
    ls -la /mnt/hdd/postgres-backups/daily/
    exit 1
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

main() {
    log_message "Starting database restoration"
    log_message "Backup file: $BACKUP_FILE"
    log_message "Target database: $TARGET_DB"

    # Verify backup file exists
    if [ ! -f "$BACKUP_FILE" ]; then
        log_message "ERROR: Backup file not found: $BACKUP_FILE"
        exit 1
    fi

    # Verify checksum if available
    if [ -f "${BACKUP_FILE}.sha256" ]; then
        log_message "Verifying backup integrity"
        if sha256sum -c "${BACKUP_FILE}.sha256"; then
            log_message "Backup integrity verified"
        else
            log_message "ERROR: Backup integrity check failed"
            exit 1
        fi
    fi

    # Stop application services
    log_message "Stopping application services"
    docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml \
        stop frontend backend worker

    # Wait for connections to close
    sleep 10

    # Terminate existing connections
    log_message "Terminating existing database connections"
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -c "
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = '$TARGET_DB' AND pid <> pg_backend_pid();
    "

    # Drop and recreate database
    log_message "Recreating target database"
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -c "DROP DATABASE IF EXISTS $TARGET_DB;"
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -c "CREATE DATABASE $TARGET_DB;"

    # Restore database
    log_message "Restoring database from backup"

    if [[ "$BACKUP_FILE" == *.gpg ]]; then
        # Decrypt and restore
        log_message "Decrypting and restoring encrypted backup"
        gpg --quiet --decrypt "$BACKUP_FILE" | \
        gunzip | \
        docker exec -i prs-onprem-postgres-timescale pg_restore \
            -U prs_admin -d "$TARGET_DB" --clean --if-exists --verbose
    elif [[ "$BACKUP_FILE" == *.gz ]]; then
        # Decompress and restore
        log_message "Decompressing and restoring backup"
        gunzip -c "$BACKUP_FILE" | \
        docker exec -i prs-onprem-postgres-timescale pg_restore \
            -U prs_admin -d "$TARGET_DB" --clean --if-exists --verbose
    else
        # Direct restore
        log_message "Restoring uncompressed backup"
        docker exec -i prs-onprem-postgres-timescale pg_restore \
            -U prs_admin -d "$TARGET_DB" --clean --if-exists --verbose < "$BACKUP_FILE"
    fi

    if [ $? -eq 0 ]; then
        log_message "Database restoration completed successfully"
    else
        log_message "ERROR: Database restoration failed"
        exit 1
    fi

    # Verify restoration
    log_message "Verifying restoration"
    TABLE_COUNT=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d "$TARGET_DB" -t -c "
    SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';
    " | xargs)

    log_message "Restored $TABLE_COUNT tables"

    if [ "$TABLE_COUNT" -gt 10 ]; then
        log_message "Restoration verification passed"
    else
        log_message "WARNING: Low table count, possible incomplete restoration"
    fi

    # Restart application services
    log_message "Restarting application services"
    docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml \
        start frontend backend worker

    log_message "Database restoration process completed"
}

main "$@"
```

### Point-in-Time Recovery Script

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/restore-point-in-time.sh
# Point-in-time recovery using WAL files

set -euo pipefail

RECOVERY_TIME="$1"
RECOVERY_DIR="/tmp/prs-recovery-$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/prs-restore.log"

if [ -z "$RECOVERY_TIME" ]; then
    echo "Usage: $0 'YYYY-MM-DD HH:MM:SS'"
    echo "Example: $0 '2024-08-22 14:30:00'"
    exit 1
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

main() {
    log_message "Starting point-in-time recovery to: $RECOVERY_TIME"

    # Create recovery directory
    mkdir -p "$RECOVERY_DIR"

    # Find appropriate base backup
    local RECOVERY_TIMESTAMP=$(date -d "$RECOVERY_TIME" +%s)
    local BASE_BACKUP=""

    for backup in $(ls -t /mnt/hdd/postgres-backups/daily/prs_full_backup_*.sql*); do
        local BACKUP_DATE=$(echo "$backup" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
        local BACKUP_TIMESTAMP=$(date -d "${BACKUP_DATE:0:8} ${BACKUP_DATE:9:2}:${BACKUP_DATE:11:2}:${BACKUP_DATE:13:2}" +%s)

        if [ "$BACKUP_TIMESTAMP" -le "$RECOVERY_TIMESTAMP" ]; then
            BASE_BACKUP="$backup"
            break
        fi
    done

    if [ -z "$BASE_BACKUP" ]; then
        log_message "ERROR: No suitable base backup found for recovery time"
        exit 1
    fi

    log_message "Using base backup: $BASE_BACKUP"

    # Copy base backup
    cp "$BASE_BACKUP" "$RECOVERY_DIR/"

    # Collect required WAL files
    log_message "Collecting WAL files for recovery"
    find /mnt/hdd/wal-archive -name "*.wal" -newer "$BASE_BACKUP" -exec cp {} "$RECOVERY_DIR/" \;

    # Stop current database
    log_message "Stopping current database"
    docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml stop postgres

    # Backup current data directory
    log_message "Backing up current data directory"
    mv /mnt/hdd/postgresql-hot /mnt/hdd/postgresql-hot.backup.$(date +%Y%m%d_%H%M%S)

    # Create new data directory
    mkdir -p /mnt/hdd/postgresql-hot
    chown 999:999 /mnt/hdd/postgresql-hot

    # Restore base backup
    log_message "Restoring base backup"
    # ... (restoration logic similar to restore-database.sh)

    # Configure recovery
    cat > /tmp/recovery.conf << EOF
restore_command = 'cp $RECOVERY_DIR/%f %p'
recovery_target_time = '$RECOVERY_TIME'
recovery_target_action = 'promote'
EOF

    cp /tmp/recovery.conf /mnt/hdd/postgresql-hot/

    # Start database in recovery mode
    log_message "Starting database in recovery mode"
    docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml up -d postgres

    # Monitor recovery
    log_message "Monitoring recovery progress"
    while docker exec prs-onprem-postgres-timescale test -f /var/lib/postgresql/data/recovery.conf; do
        log_message "Recovery in progress..."
        sleep 10
    done

    log_message "Point-in-time recovery completed to: $RECOVERY_TIME"

    # Cleanup
    rm -rf "$RECOVERY_DIR"
    rm -f /tmp/recovery.conf
}

main "$@"
```

## Backup Management Scripts

### Backup Verification Script

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/verify-backups.sh
# Verify backup integrity and completeness

set -euo pipefail

BACKUP_DIR="/mnt/hdd/postgres-backups/daily"
LOG_FILE="/var/log/prs-backup-verification.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

main() {
    log_message "Starting backup verification"

    local VERIFIED=0
    local FAILED=0

    # Check all backups from last 7 days
    for backup in $(find "$BACKUP_DIR" -name "prs_full_backup_*.sql*" -mtime -7); do
        log_message "Verifying backup: $backup"

        # Check file size
        local SIZE=$(stat -c%s "$backup")
        if [ "$SIZE" -lt 1000000 ]; then
            log_message "ERROR: Backup file too small: $backup"
            ((FAILED++))
            continue
        fi

        # Check checksum if available
        if [ -f "${backup}.sha256" ]; then
            if sha256sum -c "${backup}.sha256" >/dev/null 2>&1; then
                log_message "Checksum verification passed: $backup"
            else
                log_message "ERROR: Checksum verification failed: $backup"
                ((FAILED++))
                continue
            fi
        fi

        # Test restoration to temporary database
        log_message "Testing restoration: $backup"
        if test_restore "$backup"; then
            log_message "Restoration test passed: $backup"
            ((VERIFIED++))
        else
            log_message "ERROR: Restoration test failed: $backup"
            ((FAILED++))
        fi
    done

    log_message "Backup verification completed: $VERIFIED verified, $FAILED failed"

    if [ "$FAILED" -gt 0 ]; then
        echo "Backup verification found $FAILED failed backups" | \
        mail -s "PRS Backup Verification Alert" admin@your-domain.com
    fi
}

test_restore() {
    local backup_file="$1"
    local test_db="prs_backup_test_$(date +%s)"

    # Create test database
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -c "CREATE DATABASE $test_db;" >/dev/null 2>&1

    # Attempt restoration
    if [[ "$backup_file" == *.gpg ]]; then
        gpg --quiet --decrypt "$backup_file" | gunzip | \
        docker exec -i prs-onprem-postgres-timescale pg_restore -U prs_admin -d "$test_db" >/dev/null 2>&1
    elif [[ "$backup_file" == *.gz ]]; then
        gunzip -c "$backup_file" | \
        docker exec -i prs-onprem-postgres-timescale pg_restore -U prs_admin -d "$test_db" >/dev/null 2>&1
    else
        docker exec -i prs-onprem-postgres-timescale pg_restore -U prs_admin -d "$test_db" < "$backup_file" >/dev/null 2>&1
    fi

    local result=$?

    # Cleanup test database
    docker exec prs-onprem-postgres-timescale psql -U prs_admin -c "DROP DATABASE $test_db;" >/dev/null 2>&1

    return $result
}

main "$@"
```

### Backup Cleanup Script

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/cleanup-backups.sh
# Clean up old backups based on retention policies

set -euo pipefail

LOG_FILE="/var/log/prs-backup-cleanup.log"

# Retention policies (days)
DAILY_RETENTION=30
INCREMENTAL_RETENTION=7
APP_BACKUP_RETENTION=14
WAL_RETENTION=7

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

main() {
    log_message "Starting backup cleanup"

    # Clean daily backups
    log_message "Cleaning daily backups (retention: $DAILY_RETENTION days)"
    DELETED=$(find /mnt/hdd/postgres-backups/daily -name "prs_full_backup_*" -mtime +$DAILY_RETENTION -delete -print | wc -l)
    log_message "Deleted $DELETED old daily backups"

    # Clean incremental backups
    log_message "Cleaning incremental backups (retention: $INCREMENTAL_RETENTION days)"
    DELETED=$(find /mnt/hdd/postgres-backups/incremental -name "prs_incremental_backup_*" -mtime +$INCREMENTAL_RETENTION -delete -print | wc -l)
    log_message "Deleted $DELETED old incremental backups"

    # Clean application backups
    log_message "Cleaning application backups (retention: $APP_BACKUP_RETENTION days)"
    DELETED=$(find /mnt/hdd/app-backups -maxdepth 1 -type d -name "20*" -mtime +$APP_BACKUP_RETENTION -exec rm -rf {} \; -print | wc -l)
    log_message "Deleted $DELETED old application backup directories"

    # Clean WAL archives
    log_message "Cleaning WAL archives (retention: $WAL_RETENTION days)"
    DELETED=$(find /mnt/hdd/wal-archive -name "*.wal" -mtime +$WAL_RETENTION -delete -print | wc -l)
    log_message "Deleted $DELETED old WAL files"

    # Report storage savings
    log_message "Backup cleanup completed"

    # Check remaining storage
    BACKUP_USAGE=$(du -sh /mnt/hdd/postgres-backups | cut -f1)
    WAL_USAGE=$(du -sh /mnt/hdd/wal-archive | cut -f1)
    APP_USAGE=$(du -sh /mnt/hdd/app-backups | cut -f1)

    log_message "Current backup storage usage:"
    log_message "  Database backups: $BACKUP_USAGE"
    log_message "  WAL archives: $WAL_USAGE"
    log_message "  Application backups: $APP_USAGE"
}

main "$@"
```

## NAS Setup and Configuration Guide

### Supported NAS Systems

The PRS backup system supports the following NAS systems:

| NAS System | Protocol | Authentication | Notes |
|------------|----------|----------------|-------|
| Synology DSM | CIFS/SMB | Username/Password | Recommended for small-medium deployments |
| QNAP QTS | CIFS/SMB | Username/Password | Enterprise features available |
| FreeNAS/TrueNAS | NFS | None (IP-based) | High performance, enterprise-grade |
| Windows Server | CIFS/SMB | Domain/Local | Active Directory integration |
| Linux NFS | NFS | None (IP-based) | Lightweight, high performance |

### NAS Configuration Examples

#### Synology NAS Setup

1. **Create Backup User:**
   - Control Panel > User > Create > backup_user
   - Assign to "administrators" group for backup access

2. **Create Backup Share:**
   - Control Panel > Shared Folder > Create > "backup"
   - Enable SMB/AFP/NFS service

3. **Configure PRS:**
   ```bash
   export NAS_HOST="synology.local"
   export NAS_SHARE="backup"
   export NAS_USERNAME="backup_user"
   export NAS_PASSWORD="secure_password"
   ```

#### QNAP NAS Setup

1. **Enable File Services:**
   - Control Panel > Network & File Services > SMB/CIFS
   - Enable SMB service

2. **Create Backup Folder:**
   - File Station > Create Folder > "Backup"
   - Set permissions for backup user

3. **Configure PRS:**
   ```bash
   export NAS_HOST="qnap.local"
   export NAS_SHARE="Backup"
   export NAS_USERNAME="admin"
   export NAS_PASSWORD="qnap_password"
   ```

#### FreeNAS/TrueNAS Setup

1. **Create Dataset:**
   - Storage > Pools > Add Dataset > "backups"

2. **Configure NFS Share:**
   - Sharing > Unix (NFS) Shares > Add
   - Path: /mnt/pool1/backups
   - Authorized Networks: 192.168.1.0/24

3. **Configure PRS:**
   ```bash
   export NAS_HOST="truenas.local"
   export NAS_SHARE="/mnt/pool1/backups"
   # No username/password for NFS
   ```

### NAS Security Best Practices

#### 1. Network Security
- Use dedicated VLAN for backup traffic
- Configure firewall rules to restrict NAS access
- Enable NAS firewall and limit IP ranges

#### 2. Authentication Security
- Use strong passwords (minimum 12 characters)
- Create dedicated backup user accounts
- Regularly rotate backup credentials
- Enable two-factor authentication where available

#### 3. Data Security
```bash
# Enable backup encryption
export ENCRYPT_NAS_BACKUPS="true"
export GPG_RECIPIENT="backup@prs.client-domain.com"

# Use secure file permissions
export NAS_FILE_MODE="0600"
export NAS_DIR_MODE="0700"
```

### Troubleshooting NAS Issues

#### Common Connection Issues

**Problem: "Network connectivity to NAS failed"**
```bash
# Check network connectivity
ping your-nas-hostname

# Check DNS resolution
nslookup your-nas-hostname

# Check routing
traceroute your-nas-hostname
```

**Problem: "SMB/CIFS port 445 not accessible"**
```bash
# Check if SMB service is running on NAS
telnet your-nas-hostname 445

# Check firewall rules
iptables -L | grep 445

# Verify SMB service on NAS is enabled
```

**Problem: "NFS port 2049 not accessible"**
```bash
# Check NFS service
rpcinfo -p your-nas-hostname

# Test NFS mount manually
showmount -e your-nas-hostname
```

#### Authentication Issues

**Problem: "CIFS/SMB mount failed"**
```bash
# Test credentials manually
smbclient //your-nas-hostname/share -U username

# Check SMB version compatibility
mount -t cifs //nas/share /mnt/test -o username=user,vers=3.0

# Verify user permissions on NAS
```

#### Performance Issues

**Problem: "Backup copy to NAS is slow"**
```bash
# Test network bandwidth
iperf3 -c your-nas-hostname

# Check NAS performance
dd if=/dev/zero of=/mnt/nas/test bs=1M count=1000

# Monitor network utilization
iftop -i eth0
```

### Monitoring and Alerting

#### NAS Health Monitoring
```bash
# Add to crontab for regular NAS health checks
0 */6 * * * /opt/prs-deployment/scripts/test-nas-connection.sh

# Monitor NAS space usage
*/15 * * * * df -h /mnt/nas | awk 'NR==2 {if($5+0 > 85) print "NAS space warning: "$5" used"}'
```

#### Email Alerts
```bash
# Configure email alerts for NAS issues
export ADMIN_EMAIL="admin@prs.client-domain.com"
export NAS_SPACE_WARNING_THRESHOLD=85
export NAS_SPACE_CRITICAL_THRESHOLD=95
```

---

!!! success "Backup Scripts with NAS Integration Ready"
    Your PRS deployment now has comprehensive backup scripts with enterprise-grade NAS integration, covering database backups, application data, incremental backups, and restoration procedures.

!!! tip "NAS Automation"
    Use the provided NAS configuration and testing scripts to ensure reliable off-site backup storage. Regular testing of NAS connectivity is recommended.

!!! warning "Security & Compliance"
    Always encrypt sensitive backup data, use secure NAS credentials, and test restoration procedures regularly. Implement proper network security for NAS access.
