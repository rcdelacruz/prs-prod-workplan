#!/bin/bash

# PRS On-Premises Daily Backup Script
# Adapted from EC2 setup for TimescaleDB and dual storage
# Implements zero-deletion policy with intelligent storage tiering

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/mnt/ssd/backups/daily"
ARCHIVE_DIR="/mnt/hdd/backups/daily-archive"
LOG_FILE="/var/log/prs-backup.log"

# Database configuration
DB_NAME="prs_production"
DB_USER="prs_user"
DB_HOST="localhost"
DB_PORT="5432"

# Docker container names
POSTGRES_CONTAINER="prs-onprem-postgres-timescale"
REDIS_CONTAINER="prs-onprem-redis"
BACKEND_CONTAINER="prs-onprem-backend"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as correct user
check_user() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running"
        exit 1
    fi
    
    # Check if containers are running
    for container in $POSTGRES_CONTAINER $REDIS_CONTAINER $BACKEND_CONTAINER; do
        if ! docker ps | grep -q "$container"; then
            log_error "Container $container is not running"
            exit 1
        fi
    done
    
    # Check storage space
    SSD_USAGE=$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')
    HDD_USAGE=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$SSD_USAGE" -gt 85 ]; then
        log_warning "SSD usage is high: ${SSD_USAGE}%"
    fi
    
    if [ "$HDD_USAGE" -gt 80 ]; then
        log_warning "HDD usage is high: ${HDD_USAGE}%"
    fi
    
    log_success "Prerequisites check passed"
}

# Create backup directories
create_backup_dirs() {
    log "Creating backup directories..."
    
    mkdir -p "$BACKUP_DIR/$BACKUP_DATE"
    mkdir -p "$ARCHIVE_DIR"
    mkdir -p "/mnt/hdd/timescaledb-chunks"
    mkdir -p "/mnt/ssd/redis-backups"
    mkdir -p "/mnt/hdd/redis-archive"
    
    log_success "Backup directories created"
}

# Backup TimescaleDB (Hot Data)
backup_timescaledb_hot() {
    log "Starting TimescaleDB hot data backup..."
    
    # Create incremental backup of hot data (SSD tablespace)
    if docker exec "$POSTGRES_CONTAINER" pg_basebackup \
        -h localhost -U "$DB_USER" -D "/tmp/backup_$BACKUP_DATE" \
        -Ft -z -P -W --no-password; then
        
        # Copy backup from container to host
        docker cp "$POSTGRES_CONTAINER:/tmp/backup_$BACKUP_DATE" "$BACKUP_DIR/"
        
        # Clean up container backup
        docker exec "$POSTGRES_CONTAINER" rm -rf "/tmp/backup_$BACKUP_DATE"
        
        log_success "TimescaleDB hot data backup completed"
    else
        log_error "TimescaleDB hot data backup failed"
        return 1
    fi
}

# Backup TimescaleDB metadata
backup_timescaledb_metadata() {
    log "Backing up TimescaleDB metadata..."
    
    # Backup chunk information
    if docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c \
        "COPY (SELECT * FROM timescaledb_information.chunks) TO '/tmp/chunks_$BACKUP_DATE.csv' CSV HEADER;"; then
        docker cp "$POSTGRES_CONTAINER:/tmp/chunks_$BACKUP_DATE.csv" "$BACKUP_DIR/$BACKUP_DATE/"
        docker exec "$POSTGRES_CONTAINER" rm "/tmp/chunks_$BACKUP_DATE.csv"
    else
        log_warning "Failed to backup chunk metadata"
    fi
    
    # Backup compression policies
    if docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c \
        "COPY (SELECT * FROM timescaledb_information.compression_settings) TO '/tmp/compression_$BACKUP_DATE.csv' CSV HEADER;"; then
        docker cp "$POSTGRES_CONTAINER:/tmp/compression_$BACKUP_DATE.csv" "$BACKUP_DIR/$BACKUP_DATE/"
        docker exec "$POSTGRES_CONTAINER" rm "/tmp/compression_$BACKUP_DATE.csv"
    else
        log_warning "Failed to backup compression settings"
    fi
    
    # Backup hypertable information
    if docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c \
        "COPY (SELECT * FROM timescaledb_information.hypertables) TO '/tmp/hypertables_$BACKUP_DATE.csv' CSV HEADER;"; then
        docker cp "$POSTGRES_CONTAINER:/tmp/hypertables_$BACKUP_DATE.csv" "$BACKUP_DIR/$BACKUP_DATE/"
        docker exec "$POSTGRES_CONTAINER" rm "/tmp/hypertables_$BACKUP_DATE.csv"
    else
        log_warning "Failed to backup hypertable information"
    fi
    
    log_success "TimescaleDB metadata backup completed"
}

# Backup Redis data
backup_redis() {
    log "Starting Redis backup..."
    
    # Trigger Redis save
    if docker exec "$REDIS_CONTAINER" redis-cli BGSAVE; then
        # Wait for background save to complete
        sleep 10
        
        # Copy Redis data files
        docker cp "$REDIS_CONTAINER:/data/dump.rdb" "/mnt/ssd/redis-backups/dump_$BACKUP_DATE.rdb"
        
        if [ -f "/mnt/ssd/redis-backups/dump_$BACKUP_DATE.rdb" ]; then
            log_success "Redis backup completed"
        else
            log_error "Redis backup file not found"
            return 1
        fi
    else
        log_error "Redis backup failed"
        return 1
    fi
}

# Backup application logs
backup_logs() {
    log "Backing up application logs..."
    
    # Create log backup directory
    mkdir -p "$BACKUP_DIR/$BACKUP_DATE/logs"
    
    # Backup Docker container logs
    for container in $POSTGRES_CONTAINER $REDIS_CONTAINER $BACKEND_CONTAINER; do
        if docker logs "$container" > "$BACKUP_DIR/$BACKUP_DATE/logs/${container}_$BACKUP_DATE.log" 2>&1; then
            log "Backed up logs for $container"
        else
            log_warning "Failed to backup logs for $container"
        fi
    done
    
    # Backup system logs
    if [ -d "/mnt/ssd/logs" ]; then
        cp -r /mnt/ssd/logs/* "$BACKUP_DIR/$BACKUP_DATE/logs/" 2>/dev/null || true
    fi
    
    log_success "Application logs backup completed"
}

# Archive old backups (Zero-deletion policy)
archive_old_backups() {
    log "Archiving old backups to HDD..."
    
    # Move backups older than 7 days to HDD archive (no deletion)
    find "$BACKUP_DIR" -type d -name "20*" -mtime +7 -exec mv {} "$ARCHIVE_DIR/" \; 2>/dev/null || true
    
    # Move old Redis backups to HDD archive
    find "/mnt/ssd/redis-backups" -name "dump_*.rdb" -mtime +7 -exec mv {} "/mnt/hdd/redis-archive/" \; 2>/dev/null || true
    
    # Archive application logs
    find "/mnt/ssd/logs" -name "*.log" -mtime +7 -exec mv {} "/mnt/hdd/logs-archive/" \; 2>/dev/null || true
    
    log_success "Old backups archived to HDD"
}

# Verify backup integrity
verify_backup() {
    log "Verifying backup integrity..."
    
    BACKUP_PATH="$BACKUP_DIR/$BACKUP_DATE"
    
    # Check if backup directory exists and has content
    if [ ! -d "$BACKUP_PATH" ] || [ -z "$(ls -A "$BACKUP_PATH")" ]; then
        log_error "Backup directory is empty or missing"
        return 1
    fi
    
    # Check backup size
    BACKUP_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
    log "Backup size: $BACKUP_SIZE"
    
    # Verify PostgreSQL backup files
    if [ -f "$BACKUP_PATH/base.tar.gz" ]; then
        if tar -tzf "$BACKUP_PATH/base.tar.gz" >/dev/null 2>&1; then
            log "PostgreSQL backup archive is valid"
        else
            log_error "PostgreSQL backup archive is corrupted"
            return 1
        fi
    fi
    
    # Verify Redis backup
    if [ -f "/mnt/ssd/redis-backups/dump_$BACKUP_DATE.rdb" ]; then
        log "Redis backup file exists"
    else
        log_warning "Redis backup file not found"
    fi
    
    log_success "Backup integrity verification completed"
}

# Generate backup report
generate_report() {
    log "Generating backup report..."
    
    REPORT_FILE="/mnt/hdd/backup-reports/daily_backup_report_$BACKUP_DATE.txt"
    mkdir -p "/mnt/hdd/backup-reports"
    
    cat > "$REPORT_FILE" << EOF
PRS On-Premises Daily Backup Report
===================================
Date: $(date)
Backup ID: $BACKUP_DATE

Backup Locations:
- Hot Backup: $BACKUP_DIR/$BACKUP_DATE
- Archive Location: $ARCHIVE_DIR
- Redis Backup: /mnt/ssd/redis-backups/dump_$BACKUP_DATE.rdb

Backup Contents:
- TimescaleDB hot data (SSD tablespace)
- TimescaleDB metadata (chunks, compression, hypertables)
- Redis persistence data
- Application logs
- Container logs

Storage Usage:
- SSD Usage: $(df -h /mnt/ssd | awk 'NR==2 {print $5}')
- HDD Usage: $(df -h /mnt/hdd | awk 'NR==2 {print $5}')

Backup Size: $(du -sh "$BACKUP_DIR/$BACKUP_DATE" | cut -f1)

Status: SUCCESS
EOF
    
    log_success "Backup report generated: $REPORT_FILE"
}

# Main execution
main() {
    log "Starting PRS On-Premises Daily Backup - $BACKUP_DATE"
    
    check_user
    check_prerequisites
    create_backup_dirs
    
    # Perform backups
    backup_timescaledb_hot
    backup_timescaledb_metadata
    backup_redis
    backup_logs
    
    # Archive and verify
    archive_old_backups
    verify_backup
    generate_report
    
    log_success "Daily backup completed successfully - $BACKUP_DATE"
    
    # Send notification (optional)
    # echo "Daily backup completed successfully" | mail -s "PRS Backup Success" admin@client-domain.com
}

# Error handling
trap 'log_error "Backup script failed at line $LINENO"' ERR

# Execute main function
main "$@"
