#!/bin/bash

# Storage Path Validation Script
# Validates and prepares storage paths for different server configurations

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load environment variables
load_environment() {
    if [ -f "$PROJECT_DIR/02-docker-configuration/.env" ]; then
        set -a
        source "$PROJECT_DIR/02-docker-configuration/.env"
        set +a
        log_info "Environment variables loaded"
    else
        log_error "Environment file not found: $PROJECT_DIR/02-docker-configuration/.env"
        exit 1
    fi
}

# Validate storage paths
validate_storage_paths() {
    log_info "Validating storage path configuration..."

    # Default paths if not configured
    STORAGE_HDD_PATH=${STORAGE_HDD_PATH:-/mnt/hdd}
    STORAGE_NAS_PATH=${STORAGE_NAS_PATH:-/mnt/nas}

    # Derived paths
    POSTGRES_SSD_PATH=${POSTGRES_SSD_PATH:-${STORAGE_HDD_PATH}/postgresql-hot}
    POSTGRES_HDD_PATH=${POSTGRES_HDD_PATH:-${STORAGE_HDD_PATH}/postgresql-cold}
    APP_UPLOADS_PATH=${APP_UPLOADS_PATH:-${STORAGE_HDD_PATH}/uploads}
    APP_LOGS_PATH=${APP_LOGS_PATH:-${STORAGE_HDD_PATH}/logs}
    BACKUP_LOCAL_PATH=${BACKUP_LOCAL_PATH:-${STORAGE_HDD_PATH}}
    BACKUP_NAS_PATH=${BACKUP_NAS_PATH:-${STORAGE_NAS_PATH}}

    log_info "Storage configuration:"
    echo "  SSD Path: $STORAGE_HDD_PATH"
    echo "  HDD Path: $STORAGE_HDD_PATH"
    echo "  NAS Path: $STORAGE_NAS_PATH"
    echo ""
    echo "  PostgreSQL SSD: $POSTGRES_SSD_PATH"
    echo "  PostgreSQL HDD: $POSTGRES_HDD_PATH"
    echo "  App Uploads: $APP_UPLOADS_PATH"
    echo "  App Logs: $APP_LOGS_PATH"
    echo "  Backup Local: $BACKUP_LOCAL_PATH"
    echo "  Backup NAS: $BACKUP_NAS_PATH"
}

# Check if paths exist and are writable
check_path_accessibility() {
    local path="$1"
    local description="$2"
    local required="$3"

    if [ -d "$path" ]; then
        if [ -w "$path" ]; then
            log_success "$description: $path (accessible)"
            return 0
        else
            log_warning "$description: $path (exists but not writable)"
            return 1
        fi
    else
        if [ "$required" = "true" ]; then
            log_error "$description: $path (does not exist - required)"
            return 1
        else
            log_warning "$description: $path (does not exist - will be created)"
            return 0
        fi
    fi
}

# Validate all storage paths
validate_all_paths() {
    log_info "Checking storage path accessibility..."

    local errors=0

    # Check base storage paths
    check_path_accessibility "$STORAGE_HDD_PATH" "HDD Storage" "false" || ((errors++))
    check_path_accessibility "$STORAGE_HDD_PATH" "HDD Storage" "false" || ((errors++))

    # Check NAS path (optional)
    if [ "$BACKUP_TO_NAS" = "true" ]; then
        check_path_accessibility "$STORAGE_NAS_PATH" "NAS Storage" "false" || log_warning "NAS backup will be disabled"
    fi

    # Check derived paths
    check_path_accessibility "$(dirname "$POSTGRES_SSD_PATH")" "PostgreSQL SSD Parent" "false" || ((errors++))
    check_path_accessibility "$(dirname "$POSTGRES_HDD_PATH")" "PostgreSQL HDD Parent" "false" || ((errors++))

    if [ $errors -gt 0 ]; then
        log_error "Found $errors storage path issues"
        return 1
    else
        log_success "All storage paths are accessible or will be created"
        return 0
    fi
}

# Create missing directories
create_storage_directories() {
    log_info "Creating storage directories..."

    # Create base directories
    sudo mkdir -p "$STORAGE_HDD_PATH" || log_error "Failed to create SSD directory"
    sudo mkdir -p "$STORAGE_HDD_PATH" || log_error "Failed to create HDD directory"

    # Create PostgreSQL directories
    sudo mkdir -p "$POSTGRES_SSD_PATH" || log_error "Failed to create PostgreSQL SSD directory"
    sudo mkdir -p "$POSTGRES_HDD_PATH" || log_error "Failed to create PostgreSQL HDD directory"

    # Create application directories
    sudo mkdir -p "$APP_UPLOADS_PATH" || log_error "Failed to create uploads directory"
    sudo mkdir -p "$APP_LOGS_PATH" || log_error "Failed to create logs directory"

    # Create backup directories
    sudo mkdir -p "$BACKUP_LOCAL_PATH/postgres-backups" || log_error "Failed to create backup directory"
    sudo mkdir -p "$BACKUP_LOCAL_PATH/app-backups" || log_error "Failed to create app backup directory"

    # Set proper ownership
    sudo chown -R 999:999 "$POSTGRES_SSD_PATH" || log_warning "Failed to set PostgreSQL SSD ownership"
    sudo chown -R 999:999 "$POSTGRES_HDD_PATH" || log_warning "Failed to set PostgreSQL HDD ownership"
    sudo chown -R $USER:$USER "$APP_UPLOADS_PATH" || log_warning "Failed to set uploads ownership"
    sudo chown -R $USER:$USER "$APP_LOGS_PATH" || log_warning "Failed to set logs ownership"

    log_success "Storage directories created and configured"
}

# Test storage performance
test_storage_performance() {
    log_info "Testing storage performance..."

    # Test SSD write performance
    if [ -w "$STORAGE_HDD_PATH" ]; then
        local ssd_speed=$(dd if=/dev/zero of="$STORAGE_HDD_PATH/test_file" bs=1M count=100 2>&1 | grep -o '[0-9.]\+ MB/s' || echo "unknown")
        sudo rm -f "$STORAGE_HDD_PATH/test_file"
        log_info "SSD write speed: $ssd_speed"
    fi

    # Test HDD write performance
    if [ -w "$STORAGE_HDD_PATH" ]; then
        local hdd_speed=$(dd if=/dev/zero of="$STORAGE_HDD_PATH/test_file" bs=1M count=100 2>&1 | grep -o '[0-9.]\+ MB/s' || echo "unknown")
        sudo rm -f "$STORAGE_HDD_PATH/test_file"
        log_info "HDD write speed: $hdd_speed"
    fi
}

# Generate configuration summary
generate_config_summary() {
    log_info "Generating storage configuration summary..."

    cat > "$PROJECT_DIR/STORAGE_CONFIG_SUMMARY.md" << EOF
# Storage Configuration Summary

Generated: $(date)

## Storage Paths Configuration

| Storage Tier | Path | Purpose |
|--------------|------|---------|
| **SSD (Hot)** | \`$STORAGE_HDD_PATH\` | Fast storage for active data |
| **HDD (Cold)** | \`$STORAGE_HDD_PATH\` | Slower storage for archived data |
| **NAS (Backup)** | \`$STORAGE_NAS_PATH\` | Network storage for backup/DR |

## PostgreSQL Storage

| Component | Path | Tablespace |
|-----------|------|------------|
| **Hot Data** | \`$POSTGRES_SSD_PATH\` | pg_default |
| **Cold Data** | \`$POSTGRES_HDD_PATH\` | pg_default |

## Application Storage

| Component | Path | Purpose |
|-----------|------|---------|
| **Uploads** | \`$APP_UPLOADS_PATH\` | User uploaded files |
| **Logs** | \`$APP_LOGS_PATH\` | Application logs |
| **Backups** | \`$BACKUP_LOCAL_PATH\` | Local backup storage |

## Backup Configuration

- **Local Backups**: \`$BACKUP_LOCAL_PATH\`
- **NAS Backups**: \`$BACKUP_NAS_PATH\`
- **NAS Enabled**: $BACKUP_TO_NAS

## Next Steps

1. Verify all paths are mounted correctly
2. Run deployment: \`./deploy-onprem.sh deploy\`
3. Monitor storage usage: \`df -h\`

EOF

    log_success "Configuration summary saved to STORAGE_CONFIG_SUMMARY.md"
}

# Main execution
main() {
    log_info "Starting storage path validation..."

    load_environment
    validate_storage_paths

    if validate_all_paths; then
        create_storage_directories
        test_storage_performance
        generate_config_summary
        log_success "Storage validation completed successfully!"
    else
        log_error "Storage validation failed. Please fix the issues above."
        exit 1
    fi
}

# Execute main function
main "$@"
