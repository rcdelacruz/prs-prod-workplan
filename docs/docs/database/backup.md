# Database Backup

## Overview

This guide covers comprehensive database backup strategies for the PRS on-premises deployment, including automated backups, point-in-time recovery, and disaster recovery procedures.

## Backup Strategy

### Backup Types

#### Full Backups
- **Frequency**: Daily at 2:00 AM
- **Retention**: 30 days local, 90 days offsite
- **Size**: Complete database dump
- **Recovery Time**: 15-30 minutes

#### Incremental Backups
- **Frequency**: Every 6 hours
- **Retention**: 7 days
- **Size**: Changes since last backup
- **Recovery Time**: 5-15 minutes

#### WAL Archiving
- **Frequency**: Continuous
- **Retention**: 7 days
- **Size**: Transaction logs
- **Recovery Time**: Point-in-time recovery

### Backup Architecture

```mermaid
graph TB
    subgraph "Production Database"
        DB[TimescaleDB<br/>PostgreSQL 15] --> WAL[WAL Files<br/>Continuous]
        DB --> FULL[Full Backup<br/>Daily]
        DB --> INCR[Incremental Backup<br/>6 Hours]
    end
    
    subgraph "Local Storage"
        WAL --> WALDIR[/mnt/hdd/wal-archive]
        FULL --> FULLDIR[/mnt/hdd/postgres-backups/daily]
        INCR --> INCRDIR[/mnt/hdd/postgres-backups/incremental]
    end
    
    subgraph "Backup Processing"
        FULLDIR --> COMPRESS[Compression<br/>gzip -9]
        INCRDIR --> COMPRESS
        COMPRESS --> ENCRYPT[Encryption<br/>GPG]
        ENCRYPT --> VERIFY[Integrity Check<br/>SHA256]
    end
    
    subgraph "Offsite Storage"
        VERIFY --> OFFSITE[Remote Backup<br/>rsync/S3]
        VERIFY --> TAPE[Tape Backup<br/>Monthly]
    end
    
    style DB fill:#e3f2fd,stroke:#1976d2,stroke-width:2px
    style COMPRESS fill:#e8f5e8,stroke:#4caf50,stroke-width:2px
    style ENCRYPT fill:#fff3e0,stroke:#ff9800,stroke-width:2px
    style OFFSITE fill:#f3e5f5,stroke:#9c27b0,stroke-width:2px
```

## Automated Backup Configuration

### Backup Scripts

#### Full Backup Script

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/backup-full.sh

set -euo pipefail

# Configuration
BACKUP_DIR="/mnt/hdd/postgres-backups/daily"
RETENTION_DAYS=30
COMPRESSION_LEVEL=9
ENCRYPT_KEY="backup@your-domain.com"

# Database connection
PGHOST="localhost"
PGPORT="5432"
PGUSER="prs_admin"
PGDATABASE="prs_production"

# Logging
LOG_FILE="/var/log/prs-backup.log"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/prs_full_backup_${DATE}.sql"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Create backup directory
mkdir -p "$BACKUP_DIR"

log_message "Starting full database backup"

# Pre-backup checks
log_message "Checking database connectivity"
if ! docker exec prs-onprem-postgres-timescale pg_isready -U "$PGUSER"; then
    log_message "ERROR: Database not ready"
    exit 1
fi

# Check available space
AVAILABLE_SPACE=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
REQUIRED_SPACE=5000000  # 5GB in KB

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    log_message "ERROR: Insufficient disk space for backup"
    exit 1
fi

# Create backup
log_message "Creating database backup: $BACKUP_FILE"
docker exec prs-onprem-postgres-timescale pg_dump \
    -U "$PGUSER" \
    -d "$PGDATABASE" \
    --verbose \
    --format=custom \
    --compress=9 \
    --no-owner \
    --no-privileges \
    > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    log_message "Database backup completed successfully"
else
    log_message "ERROR: Database backup failed"
    exit 1
fi

# Compress backup
log_message "Compressing backup"
gzip -"$COMPRESSION_LEVEL" "$BACKUP_FILE"
BACKUP_FILE="${BACKUP_FILE}.gz"

# Generate checksum
log_message "Generating checksum"
sha256sum "$BACKUP_FILE" > "${BACKUP_FILE}.sha256"

# Encrypt backup (optional)
if command -v gpg >/dev/null 2>&1 && gpg --list-keys "$ENCRYPT_KEY" >/dev/null 2>&1; then
    log_message "Encrypting backup"
    gpg --trust-model always --encrypt -r "$ENCRYPT_KEY" "$BACKUP_FILE"
    rm "$BACKUP_FILE"
    BACKUP_FILE="${BACKUP_FILE}.gpg"
fi

# Verify backup integrity
log_message "Verifying backup integrity"
BACKUP_SIZE=$(stat -c%s "$BACKUP_FILE")
if [ "$BACKUP_SIZE" -gt 1000000 ]; then  # At least 1MB
    log_message "Backup verification successful (Size: $(numfmt --to=iec $BACKUP_SIZE))"
else
    log_message "ERROR: Backup file too small, possible corruption"
    exit 1
fi

# Cleanup old backups
log_message "Cleaning up old backups (retention: $RETENTION_DAYS days)"
find "$BACKUP_DIR" -name "prs_full_backup_*.sql*" -mtime +$RETENTION_DAYS -delete

# Log backup completion
log_message "Full backup completed: $BACKUP_FILE"
log_message "Backup size: $(numfmt --to=iec $BACKUP_SIZE)"

# Send notification (optional)
if command -v mail >/dev/null 2>&1; then
    echo "Database backup completed successfully at $(date)" | \
    mail -s "PRS Database Backup Success" admin@your-domain.com
fi
```

#### Incremental Backup Script

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/backup-incremental.sh

set -euo pipefail

# Configuration
BACKUP_DIR="/mnt/hdd/postgres-backups/incremental"
BASE_BACKUP_DIR="/mnt/hdd/postgres-backups/daily"
RETENTION_DAYS=7

# Logging
LOG_FILE="/var/log/prs-backup.log"
DATE=$(date +%Y%m%d_%H%M%S)

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Create backup directory
mkdir -p "$BACKUP_DIR"

log_message "Starting incremental backup"

# Find latest full backup
LATEST_FULL=$(ls -t "$BASE_BACKUP_DIR"/prs_full_backup_*.sql* 2>/dev/null | head -1)
if [ -z "$LATEST_FULL" ]; then
    log_message "ERROR: No full backup found, running full backup first"
    /opt/prs-deployment/scripts/backup-full.sh
    exit 0
fi

log_message "Base backup: $LATEST_FULL"

# Create incremental backup using WAL files
INCREMENTAL_FILE="$BACKUP_DIR/prs_incremental_backup_${DATE}.tar"

log_message "Creating incremental backup: $INCREMENTAL_FILE"

# Archive WAL files since last backup
LAST_BACKUP_TIME=$(stat -c %Y "$LATEST_FULL")
find /mnt/hdd/wal-archive -name "*.wal" -newer "$LATEST_FULL" -print0 | \
tar --null -czf "$INCREMENTAL_FILE" --files-from=-

if [ $? -eq 0 ]; then
    log_message "Incremental backup completed successfully"
else
    log_message "ERROR: Incremental backup failed"
    exit 1
fi

# Generate checksum
sha256sum "$INCREMENTAL_FILE" > "${INCREMENTAL_FILE}.sha256"

# Cleanup old incremental backups
find "$BACKUP_DIR" -name "prs_incremental_backup_*.tar*" -mtime +$RETENTION_DAYS -delete

log_message "Incremental backup completed: $INCREMENTAL_FILE"
```

### WAL Archiving Configuration

#### PostgreSQL Configuration

```sql
-- Enable WAL archiving
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET archive_mode = 'on';
ALTER SYSTEM SET archive_command = 'cp %p /mnt/hdd/wal-archive/%f';
ALTER SYSTEM SET archive_timeout = '300s';
ALTER SYSTEM SET max_wal_senders = 3;
ALTER SYSTEM SET wal_keep_segments = 64;

-- Reload configuration
SELECT pg_reload_conf();
```

#### WAL Archive Management

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/wal-archive-cleanup.sh

WAL_ARCHIVE_DIR="/mnt/hdd/wal-archive"
RETENTION_DAYS=7
LOG_FILE="/var/log/prs-backup.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "Starting WAL archive cleanup"

# Remove old WAL files
DELETED_COUNT=$(find "$WAL_ARCHIVE_DIR" -name "*.wal" -mtime +$RETENTION_DAYS -delete -print | wc -l)

log_message "Deleted $DELETED_COUNT old WAL files"

# Check WAL archive size
ARCHIVE_SIZE=$(du -sh "$WAL_ARCHIVE_DIR" | cut -f1)
log_message "Current WAL archive size: $ARCHIVE_SIZE"

# Alert if archive is too large
ARCHIVE_SIZE_BYTES=$(du -sb "$WAL_ARCHIVE_DIR" | cut -f1)
MAX_SIZE_BYTES=$((10 * 1024 * 1024 * 1024))  # 10GB

if [ "$ARCHIVE_SIZE_BYTES" -gt "$MAX_SIZE_BYTES" ]; then
    log_message "WARNING: WAL archive size exceeds 10GB"
    echo "WAL archive size is $ARCHIVE_SIZE, exceeding 10GB limit" | \
    mail -s "WAL Archive Size Warning" admin@your-domain.com
fi
```

## Backup Scheduling

### Cron Configuration

```bash
# Add backup jobs to crontab
(crontab -l 2>/dev/null; cat << 'EOF'
# PRS Database Backup Schedule

# Full backup daily at 2:00 AM
0 2 * * * /opt/prs-deployment/scripts/backup-full.sh

# Incremental backup every 6 hours
0 */6 * * * /opt/prs-deployment/scripts/backup-incremental.sh

# WAL archive cleanup daily at 3:00 AM
0 3 * * * /opt/prs-deployment/scripts/wal-archive-cleanup.sh

# Backup verification daily at 4:00 AM
0 4 * * * /opt/prs-deployment/scripts/backup-verify.sh

# Offsite backup daily at 5:00 AM
0 5 * * * /opt/prs-deployment/scripts/backup-offsite.sh
EOF
) | crontab -
```

### Backup Verification

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/backup-verify.sh

BACKUP_DIR="/mnt/hdd/postgres-backups/daily"
LOG_FILE="/var/log/prs-backup.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "Starting backup verification"

# Find latest backup
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/prs_full_backup_*.sql* 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    log_message "ERROR: No backup found for verification"
    exit 1
fi

log_message "Verifying backup: $LATEST_BACKUP"

# Verify checksum
if [ -f "${LATEST_BACKUP}.sha256" ]; then
    if sha256sum -c "${LATEST_BACKUP}.sha256" >/dev/null 2>&1; then
        log_message "Checksum verification passed"
    else
        log_message "ERROR: Checksum verification failed"
        exit 1
    fi
else
    log_message "WARNING: No checksum file found"
fi

# Test backup restore (to temporary database)
log_message "Testing backup restore"

# Create test database
docker exec prs-onprem-postgres-timescale psql -U prs_admin -c "DROP DATABASE IF EXISTS prs_backup_test;"
docker exec prs-onprem-postgres-timescale psql -U prs_admin -c "CREATE DATABASE prs_backup_test;"

# Restore backup to test database
if [[ "$LATEST_BACKUP" == *.gpg ]]; then
    # Decrypt and restore
    gpg --quiet --decrypt "$LATEST_BACKUP" | \
    gunzip | \
    docker exec -i prs-onprem-postgres-timescale pg_restore -U prs_admin -d prs_backup_test --clean --if-exists
else
    # Direct restore
    gunzip -c "$LATEST_BACKUP" | \
    docker exec -i prs-onprem-postgres-timescale pg_restore -U prs_admin -d prs_backup_test --clean --if-exists
fi

if [ $? -eq 0 ]; then
    log_message "Backup restore test successful"
    
    # Verify data integrity
    TABLE_COUNT=$(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_backup_test -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | xargs)
    log_message "Restored $TABLE_COUNT tables"
    
    if [ "$TABLE_COUNT" -gt 10 ]; then
        log_message "Data integrity check passed"
    else
        log_message "WARNING: Low table count, possible incomplete restore"
    fi
else
    log_message "ERROR: Backup restore test failed"
    exit 1
fi

# Cleanup test database
docker exec prs-onprem-postgres-timescale psql -U prs_admin -c "DROP DATABASE prs_backup_test;"

log_message "Backup verification completed successfully"
```

## Point-in-Time Recovery

### Recovery Preparation

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/prepare-recovery.sh

RECOVERY_TIME="$1"
RECOVERY_DIR="/tmp/prs-recovery-$(date +%Y%m%d_%H%M%S)"

if [ -z "$RECOVERY_TIME" ]; then
    echo "Usage: $0 'YYYY-MM-DD HH:MM:SS'"
    echo "Example: $0 '2024-08-22 14:30:00'"
    exit 1
fi

echo "Preparing point-in-time recovery to: $RECOVERY_TIME"
echo "Recovery directory: $RECOVERY_DIR"

# Create recovery directory
mkdir -p "$RECOVERY_DIR"

# Find appropriate base backup
RECOVERY_TIMESTAMP=$(date -d "$RECOVERY_TIME" +%s)
BASE_BACKUP=""

for backup in $(ls -t /mnt/hdd/postgres-backups/daily/prs_full_backup_*.sql*); do
    BACKUP_DATE=$(echo "$backup" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
    BACKUP_TIMESTAMP=$(date -d "${BACKUP_DATE:0:8} ${BACKUP_DATE:9:2}:${BACKUP_DATE:11:2}:${BACKUP_DATE:13:2}" +%s)
    
    if [ "$BACKUP_TIMESTAMP" -le "$RECOVERY_TIMESTAMP" ]; then
        BASE_BACKUP="$backup"
        break
    fi
done

if [ -z "$BASE_BACKUP" ]; then
    echo "ERROR: No suitable base backup found for recovery time"
    exit 1
fi

echo "Using base backup: $BASE_BACKUP"

# Copy base backup
cp "$BASE_BACKUP" "$RECOVERY_DIR/"

# Collect required WAL files
echo "Collecting WAL files for recovery..."
WAL_START_TIME=$(stat -c %Y "$BASE_BACKUP")

find /mnt/hdd/wal-archive -name "*.wal" -newer "$BASE_BACKUP" -exec cp {} "$RECOVERY_DIR/" \;

echo "Recovery preparation completed"
echo "Recovery files available in: $RECOVERY_DIR"
echo ""
echo "To perform recovery:"
echo "1. Stop the database"
echo "2. Restore base backup"
echo "3. Configure recovery.conf"
echo "4. Start database in recovery mode"
```

### Recovery Execution

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/execute-recovery.sh

RECOVERY_TIME="$1"
RECOVERY_DIR="$2"

if [ -z "$RECOVERY_TIME" ] || [ -z "$RECOVERY_DIR" ]; then
    echo "Usage: $0 'YYYY-MM-DD HH:MM:SS' /path/to/recovery/dir"
    exit 1
fi

echo "WARNING: This will replace the current database!"
echo "Recovery time: $RECOVERY_TIME"
echo "Recovery directory: $RECOVERY_DIR"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Recovery cancelled"
    exit 0
fi

# Stop database
echo "Stopping database..."
docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml stop postgres

# Backup current data directory
echo "Backing up current data directory..."
sudo mv /mnt/ssd/postgresql-hot /mnt/ssd/postgresql-hot.backup.$(date +%Y%m%d_%H%M%S)

# Create new data directory
sudo mkdir -p /mnt/ssd/postgresql-hot
sudo chown 999:999 /mnt/ssd/postgresql-hot

# Initialize new database cluster
docker run --rm \
    -v /mnt/ssd/postgresql-hot:/var/lib/postgresql/data \
    -e POSTGRES_DB=prs_production \
    -e POSTGRES_USER=prs_admin \
    -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    timescale/timescaledb:latest-pg15 \
    initdb

# Restore base backup
echo "Restoring base backup..."
BASE_BACKUP=$(ls "$RECOVERY_DIR"/prs_full_backup_*.sql*)

if [[ "$BASE_BACKUP" == *.gpg ]]; then
    gpg --quiet --decrypt "$BASE_BACKUP" | gunzip > /tmp/restore.sql
else
    gunzip -c "$BASE_BACKUP" > /tmp/restore.sql
fi

# Start database temporarily for restore
docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml up -d postgres

# Wait for database to be ready
sleep 30
while ! docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin; do
    echo "Waiting for database..."
    sleep 5
done

# Restore data
docker exec -i prs-onprem-postgres-timescale pg_restore -U prs_admin -d prs_production --clean --if-exists < /tmp/restore.sql

# Stop database for WAL recovery
docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml stop postgres

# Configure recovery
cat > /tmp/recovery.conf << EOF
restore_command = 'cp $RECOVERY_DIR/%f %p'
recovery_target_time = '$RECOVERY_TIME'
recovery_target_action = 'promote'
EOF

sudo cp /tmp/recovery.conf /mnt/ssd/postgresql-hot/

# Start database in recovery mode
echo "Starting database in recovery mode..."
docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml up -d postgres

# Monitor recovery
echo "Monitoring recovery progress..."
while docker exec prs-onprem-postgres-timescale test -f /var/lib/postgresql/data/recovery.conf; do
    echo "Recovery in progress..."
    sleep 10
done

echo "Point-in-time recovery completed!"
echo "Database recovered to: $RECOVERY_TIME"

# Cleanup
rm -f /tmp/restore.sql /tmp/recovery.conf
```

## Offsite Backup

### Remote Backup Configuration

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/backup-offsite.sh

# Configuration
LOCAL_BACKUP_DIR="/mnt/hdd/postgres-backups"
REMOTE_HOST="backup-server.your-domain.com"
REMOTE_USER="backup"
REMOTE_DIR="/backup/prs-production"
LOG_FILE="/var/log/prs-backup.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_message "Starting offsite backup sync"

# Sync daily backups
log_message "Syncing daily backups"
rsync -avz --delete \
    --include="prs_full_backup_*" \
    --exclude="*" \
    "$LOCAL_BACKUP_DIR/daily/" \
    "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/daily/"

if [ $? -eq 0 ]; then
    log_message "Daily backup sync completed"
else
    log_message "ERROR: Daily backup sync failed"
fi

# Sync incremental backups (last 7 days only)
log_message "Syncing incremental backups"
find "$LOCAL_BACKUP_DIR/incremental" -name "prs_incremental_backup_*" -mtime -7 | \
rsync -avz --files-from=- / \
    "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/incremental/"

# Verify remote backups
log_message "Verifying remote backups"
REMOTE_COUNT=$(ssh "$REMOTE_USER@$REMOTE_HOST" "find $REMOTE_DIR/daily -name 'prs_full_backup_*' | wc -l")
LOCAL_COUNT=$(find "$LOCAL_BACKUP_DIR/daily" -name "prs_full_backup_*" | wc -l)

if [ "$REMOTE_COUNT" -eq "$LOCAL_COUNT" ]; then
    log_message "Remote backup verification successful ($REMOTE_COUNT files)"
else
    log_message "WARNING: Remote backup count mismatch (Local: $LOCAL_COUNT, Remote: $REMOTE_COUNT)"
fi

log_message "Offsite backup sync completed"
```

---

!!! success "Backup System Ready"
    Your PRS database now has comprehensive backup coverage with automated daily backups, point-in-time recovery, and offsite storage.

!!! tip "Recovery Testing"
    Regularly test backup restoration procedures to ensure backups are valid and recovery processes work correctly.

!!! warning "Backup Monitoring"
    Monitor backup jobs daily and ensure adequate storage space is available for backup retention requirements.
