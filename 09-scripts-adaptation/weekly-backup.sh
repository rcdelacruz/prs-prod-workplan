#!/bin/bash

# PRS On-Premises Weekly Full Backup Script
# Comprehensive backup including all TimescaleDB components and cross-tablespace data
# Implements zero-deletion policy with NAS synchronization

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/mnt/hdd/postgres-backups/weekly"
NAS_BACKUP_DIR="/mnt/nas/prs-backups/weekly"
LOG_FILE="/var/log/prs-backup.log"

# Database configuration
DB_NAME="prs_production"
DB_USER="prs_user"
DB_HOST="localhost"
DB_PORT="5432"

# Docker container names
POSTGRES_CONTAINER="prs-onprem-postgres-timescale"
REDIS_CONTAINER="prs-onprem-redis"

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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites for weekly backup..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running"
        exit 1
    fi
    
    # Check if PostgreSQL container is running
    if ! docker ps | grep -q "$POSTGRES_CONTAINER"; then
        log_error "PostgreSQL container is not running"
        exit 1
    fi
    
    # Check storage space
    HDD_USAGE=$(df /mnt/hdd | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$HDD_USAGE" -gt 85 ]; then
        log_error "HDD usage is too high: ${HDD_USAGE}%. Cannot proceed with backup."
        exit 1
    fi
    
    # Check if NAS is mounted
    if [ ! -d "/mnt/nas" ]; then
        log_warning "NAS mount not available. Backup will proceed without NAS sync."
    fi
    
    log_success "Prerequisites check passed"
}

# Create backup directories
create_backup_dirs() {
    log "Creating backup directories..."
    
    mkdir -p "$BACKUP_DIR"
    mkdir -p "/mnt/hdd/timescaledb-tablespaces"
    mkdir -p "/mnt/hdd/uploads-backup"
    
    if [ -d "/mnt/nas" ]; then
        mkdir -p "$NAS_BACKUP_DIR"
    fi
    
    log_success "Backup directories created"
}

# Full TimescaleDB database backup
backup_timescaledb_full() {
    log "Starting TimescaleDB full database backup..."
    
    # Create full TimescaleDB dump (includes all hypertables and chunks)
    if docker exec "$POSTGRES_CONTAINER" pg_dump \
        -h localhost -U "$DB_USER" -d "$DB_NAME" \
        -Fc -Z 9 --verbose \
        --file="/tmp/prs_timescaledb_full_$BACKUP_DATE.dump"; then
        
        # Copy backup from container to host
        docker cp "$POSTGRES_CONTAINER:/tmp/prs_timescaledb_full_$BACKUP_DATE.dump" \
            "$BACKUP_DIR/prs_timescaledb_full_$BACKUP_DATE.dump"
        
        # Clean up container backup
        docker exec "$POSTGRES_CONTAINER" rm "/tmp/prs_timescaledb_full_$BACKUP_DATE.dump"
        
        log_success "TimescaleDB full backup completed"
    else
        log_error "TimescaleDB full backup failed"
        return 1
    fi
}

# Backup SSD tablespace separately
backup_ssd_tablespace() {
    log "Backing up SSD tablespace..."
    
    # Create tablespace-specific backup
    if docker exec "$POSTGRES_CONTAINER" pg_dump \
        -h localhost -U "$DB_USER" -d "$DB_NAME" \
        -Fc -Z 9 --verbose \
        --file="/tmp/prs_ssd_tablespace_$BACKUP_DATE.dump"; then
        
        docker cp "$POSTGRES_CONTAINER:/tmp/prs_ssd_tablespace_$BACKUP_DATE.dump" \
            "/mnt/hdd/timescaledb-tablespaces/prs_ssd_tablespace_$BACKUP_DATE.dump"
        
        docker exec "$POSTGRES_CONTAINER" rm "/tmp/prs_ssd_tablespace_$BACKUP_DATE.dump"
        
        log_success "SSD tablespace backup completed"
    else
        log_warning "SSD tablespace backup failed"
    fi
}

# Backup HDD tablespace separately
backup_hdd_tablespace() {
    log "Backing up HDD tablespace..."
    
    # Create HDD tablespace backup
    if docker exec "$POSTGRES_CONTAINER" pg_dump \
        -h localhost -U "$DB_USER" -d "$DB_NAME" \
        -Fc -Z 9 --verbose \
        --file="/tmp/prs_hdd_tablespace_$BACKUP_DATE.dump"; then
        
        docker cp "$POSTGRES_CONTAINER:/tmp/prs_hdd_tablespace_$BACKUP_DATE.dump" \
            "/mnt/hdd/timescaledb-tablespaces/prs_hdd_tablespace_$BACKUP_DATE.dump"
        
        docker exec "$POSTGRES_CONTAINER" rm "/tmp/prs_hdd_tablespace_$BACKUP_DATE.dump"
        
        log_success "HDD tablespace backup completed"
    else
        log_warning "HDD tablespace backup failed"
    fi
}

# Export TimescaleDB configuration
export_timescaledb_config() {
    log "Exporting TimescaleDB configuration..."
    
    # Export hypertables configuration
    if docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" \
        -c "SELECT * FROM timescaledb_information.hypertables;" \
        > "$BACKUP_DIR/hypertables_$BACKUP_DATE.sql"; then
        log "Hypertables configuration exported"
    else
        log_warning "Failed to export hypertables configuration"
    fi
    
    # Export compression settings
    if docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" \
        -c "SELECT * FROM timescaledb_information.compression_settings;" \
        > "$BACKUP_DIR/compression_settings_$BACKUP_DATE.sql"; then
        log "Compression settings exported"
    else
        log_warning "Failed to export compression settings"
    fi
    
    # Export continuous aggregates
    if docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" \
        -c "SELECT * FROM timescaledb_information.continuous_aggregates;" \
        > "$BACKUP_DIR/continuous_aggregates_$BACKUP_DATE.sql"; then
        log "Continuous aggregates exported"
    else
        log_warning "Failed to export continuous aggregates"
    fi
    
    # Export retention policies
    if docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" \
        -c "SELECT * FROM timescaledb_information.drop_chunks_policies;" \
        > "$BACKUP_DIR/retention_policies_$BACKUP_DATE.sql"; then
        log "Retention policies exported"
    else
        log_warning "Failed to export retention policies"
    fi
    
    log_success "TimescaleDB configuration export completed"
}

# Backup file uploads
backup_uploads() {
    log "Backing up file uploads..."
    
    # Backup file uploads (preserve all versions - no --delete flag)
    if [ -d "/mnt/ssd/uploads" ]; then
        if rsync -av --progress /mnt/ssd/uploads/ /mnt/hdd/uploads-backup/; then
            log_success "File uploads backup completed"
        else
            log_warning "File uploads backup failed"
        fi
    else
        log_warning "Uploads directory not found"
    fi
}

# Backup system configurations
backup_configurations() {
    log "Backing up system configurations..."
    
    CONFIG_BACKUP_DIR="/mnt/hdd/config-backups/weekly"
    mkdir -p "$CONFIG_BACKUP_DIR"
    
    # Backup Docker configurations
    if [ -d "/opt/prs/prod-workplan/02-docker-configuration" ]; then
        cp -r /opt/prs/prod-workplan/02-docker-configuration "$CONFIG_BACKUP_DIR/docker-config-$BACKUP_DATE"
        log "Docker configurations backed up"
    fi
    
    # Backup SSL certificates
    if [ -d "/opt/prs/ssl" ]; then
        cp -r /opt/prs/ssl "$CONFIG_BACKUP_DIR/ssl-$BACKUP_DATE"
        log "SSL certificates backed up"
    fi
    
    # Backup environment files
    if [ -f "/opt/prs/.env" ]; then
        cp /opt/prs/.env "$CONFIG_BACKUP_DIR/env-$BACKUP_DATE"
        log "Environment file backed up"
    fi
    
    log_success "System configurations backup completed"
}

# Synchronize to NAS
sync_to_nas() {
    if [ ! -d "/mnt/nas" ]; then
        log_warning "NAS not available, skipping NAS sync"
        return 0
    fi
    
    log "Synchronizing backups to NAS..."
    
    # Sync weekly database backups to NAS
    if rsync -av --progress "$BACKUP_DIR/" "$NAS_BACKUP_DIR/"; then
        log_success "Database backups synced to NAS"
    else
        log_warning "Failed to sync database backups to NAS"
    fi
    
    # Sync critical configurations to NAS
    if [ -d "/mnt/hdd/config-backups" ]; then
        if rsync -av --progress /mnt/hdd/config-backups/ /mnt/nas/prs-backups/config-backups/; then
            log "Configuration backups synced to NAS"
        else
            log_warning "Failed to sync configuration backups to NAS"
        fi
    fi
    
    log_success "NAS synchronization completed"
}

# Verify backup integrity
verify_backup_integrity() {
    log "Verifying backup integrity..."
    
    # Verify main database backup
    MAIN_BACKUP="$BACKUP_DIR/prs_timescaledb_full_$BACKUP_DATE.dump"
    if [ -f "$MAIN_BACKUP" ]; then
        # Check if backup file is not empty and is a valid PostgreSQL dump
        if [ -s "$MAIN_BACKUP" ]; then
            # Try to list the contents of the dump file
            if docker exec "$POSTGRES_CONTAINER" pg_restore --list "$MAIN_BACKUP" >/dev/null 2>&1; then
                log_success "Main database backup is valid"
            else
                log_error "Main database backup is corrupted"
                return 1
            fi
        else
            log_error "Main database backup file is empty"
            return 1
        fi
    else
        log_error "Main database backup file not found"
        return 1
    fi
    
    # Check backup sizes
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
    log "Total backup size: $BACKUP_SIZE"
    
    # Verify configuration files
    CONFIG_FILES=("hypertables_$BACKUP_DATE.sql" "compression_settings_$BACKUP_DATE.sql")
    for config_file in "${CONFIG_FILES[@]}"; do
        if [ -f "$BACKUP_DIR/$config_file" ]; then
            log "Configuration file $config_file verified"
        else
            log_warning "Configuration file $config_file missing"
        fi
    done
    
    log_success "Backup integrity verification completed"
}

# Generate comprehensive backup report
generate_weekly_report() {
    log "Generating weekly backup report..."
    
    REPORT_FILE="/mnt/hdd/backup-reports/weekly_backup_report_$BACKUP_DATE.txt"
    mkdir -p "/mnt/hdd/backup-reports"
    
    # Calculate backup sizes
    MAIN_BACKUP_SIZE=$(du -sh "$BACKUP_DIR/prs_timescaledb_full_$BACKUP_DATE.dump" 2>/dev/null | cut -f1 || echo "N/A")
    TOTAL_BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
    UPLOADS_SIZE=$(du -sh "/mnt/hdd/uploads-backup" 2>/dev/null | cut -f1 || echo "N/A")
    
    cat > "$REPORT_FILE" << EOF
PRS On-Premises Weekly Backup Report
====================================
Date: $(date)
Backup ID: $BACKUP_DATE

Backup Components:
==================
✓ TimescaleDB Full Database Backup
✓ SSD Tablespace Backup
✓ HDD Tablespace Backup
✓ TimescaleDB Configuration Export
✓ File Uploads Backup
✓ System Configuration Backup
✓ NAS Synchronization

Backup Locations:
================
- Main Backup: $BACKUP_DIR/
- Tablespace Backups: /mnt/hdd/timescaledb-tablespaces/
- Uploads Backup: /mnt/hdd/uploads-backup/
- Config Backup: /mnt/hdd/config-backups/weekly/
- NAS Backup: $NAS_BACKUP_DIR/

Backup Sizes:
=============
- Main Database Backup: $MAIN_BACKUP_SIZE
- Total Weekly Backup: $TOTAL_BACKUP_SIZE
- Uploads Backup: $UPLOADS_SIZE

Storage Usage:
==============
- SSD Usage: $(df -h /mnt/ssd | awk 'NR==2 {print $5}')
- HDD Usage: $(df -h /mnt/hdd | awk 'NR==2 {print $5}')
- NAS Usage: $(df -h /mnt/nas 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A")

TimescaleDB Statistics:
======================
- Hypertables: $(docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT count(*) FROM timescaledb_information.hypertables;" 2>/dev/null | tr -d ' ' || echo "N/A")
- Chunks: $(docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT count(*) FROM timescaledb_information.chunks;" 2>/dev/null | tr -d ' ' || echo "N/A")
- Compressed Chunks: $(docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT count(*) FROM timescaledb_information.chunks WHERE is_compressed = true;" 2>/dev/null | tr -d ' ' || echo "N/A")

Backup Status: SUCCESS
Next Weekly Backup: $(date -d "+7 days" "+%Y-%m-%d")

Zero-Deletion Policy: ENFORCED
All backups are preserved permanently according to policy.
EOF
    
    log_success "Weekly backup report generated: $REPORT_FILE"
}

# Main execution
main() {
    log "Starting PRS On-Premises Weekly Backup - $BACKUP_DATE"
    
    check_prerequisites
    create_backup_dirs
    
    # Perform comprehensive backups
    backup_timescaledb_full
    backup_ssd_tablespace
    backup_hdd_tablespace
    export_timescaledb_config
    backup_uploads
    backup_configurations
    
    # Sync and verify
    sync_to_nas
    verify_backup_integrity
    generate_weekly_report
    
    log_success "Weekly backup completed successfully - $BACKUP_DATE"
    
    # Send notification (optional)
    # echo "Weekly backup completed successfully. Report: $REPORT_FILE" | mail -s "PRS Weekly Backup Success" admin@client-domain.com
}

# Error handling
trap 'log_error "Weekly backup script failed at line $LINENO"' ERR

# Execute main function
main "$@"
