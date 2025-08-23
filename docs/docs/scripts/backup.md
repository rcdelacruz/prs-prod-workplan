# Backup Scripts

## Overview

This guide covers all backup-related scripts in the PRS on-premises deployment, including automated backup procedures, restoration scripts, and backup management utilities.

## Core Backup Scripts

### Full Database Backup Script

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/backup-full.sh
# Comprehensive database backup with verification

set -euo pipefail

# Configuration
BACKUP_DIR="/mnt/hdd/postgres-backups/daily"
RETENTION_DAYS=30
COMPRESSION_LEVEL=9
ENCRYPT_KEY="backup@your-domain.com"
LOG_FILE="/var/log/prs-backup.log"

# Database connection
PGHOST="postgres"
PGPORT="5432"
PGUSER="prs_admin"
PGDATABASE="prs_production"

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_message "ERROR: $1"
    exit 1
}

# Main backup function
main() {
    local DATE=$(date +%Y%m%d_%H%M%S)
    local BACKUP_FILE="$BACKUP_DIR/prs_full_backup_${DATE}.sql"
    
    log_message "Starting full database backup"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR" || error_exit "Failed to create backup directory"
    
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
    log_message "Backup completed: $BACKUP_FILE ($(numfmt --to=iec $FINAL_SIZE))"
    
    # Cleanup old backups
    log_message "Cleaning up old backups (retention: $RETENTION_DAYS days)"
    find "$BACKUP_DIR" -name "prs_full_backup_*.sql*" -mtime +$RETENTION_DAYS -delete
    
    # Send notification
    if command -v mail >/dev/null 2>&1; then
        echo "Database backup completed successfully at $(date)" | \
        mail -s "PRS Database Backup Success" admin@your-domain.com
    fi
    
    log_message "Full backup process completed successfully"
}

# Execute main function
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
    if [ -d "/mnt/ssd/uploads" ]; then
        tar -czf "$APP_BACKUP_DIR/uploads.tar.gz" -C /mnt/ssd uploads/
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
    find /mnt/ssd/logs -name "*.log" -mtime -7 | \
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
    mv /mnt/ssd/postgresql-hot /mnt/ssd/postgresql-hot.backup.$(date +%Y%m%d_%H%M%S)
    
    # Create new data directory
    mkdir -p /mnt/ssd/postgresql-hot
    chown 999:999 /mnt/ssd/postgresql-hot
    
    # Restore base backup
    log_message "Restoring base backup"
    # ... (restoration logic similar to restore-database.sh)
    
    # Configure recovery
    cat > /tmp/recovery.conf << EOF
restore_command = 'cp $RECOVERY_DIR/%f %p'
recovery_target_time = '$RECOVERY_TIME'
recovery_target_action = 'promote'
EOF
    
    cp /tmp/recovery.conf /mnt/ssd/postgresql-hot/
    
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

---

!!! success "Backup Scripts Ready"
    Your PRS deployment now has comprehensive backup scripts covering database backups, application data, restoration procedures, and backup management.

!!! tip "Automation"
    Schedule these scripts with cron for automated backup operations and regular verification of backup integrity.

!!! warning "Testing Required"
    Always test backup and restoration procedures in a non-production environment before relying on them for disaster recovery.
