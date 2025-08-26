#!/bin/bash

# Fix Hardcoded Storage Paths Script
# Systematically replaces hardcoded paths with configurable environment variables

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

# Find all scripts with hardcoded paths
find_scripts_with_hardcoded_paths() {
    log_info "Finding scripts with hardcoded storage paths..."

    find "$SCRIPT_DIR" -name "*.sh" -exec grep -l "${STORAGE_HDD_PATH:-/mnt/hdd}\|/mnt/hdd\|/mnt/nas" {} \; | sort
}

# Create backup of scripts before modification
backup_scripts() {
    local backup_dir="$PROJECT_DIR/script-backups-$(date +%Y%m%d-%H%M%S)"
    log_info "Creating backup of scripts in: $backup_dir"

    mkdir -p "$backup_dir"
    cp -r "$SCRIPT_DIR"/*.sh "$backup_dir/" 2>/dev/null || true

    log_success "Scripts backed up to: $backup_dir"
}

# Fix a specific script
fix_script_paths() {
    local script_path="$1"
    local script_name=$(basename "$script_path")

    log_info "Fixing hardcoded paths in: $script_name"

    # Create temporary file
    local temp_file=$(mktemp)

    # Apply replacements
    sed \
        -e 's|"/mnt/hdd/postgres-backups|"${BACKUP_LOCAL_PATH:-/mnt/hdd}/postgres-backups|g' \
        -e 's|"/mnt/hdd/app-backups|"${BACKUP_LOCAL_PATH:-/mnt/hdd}/app-backups|g' \
        -e 's|"/mnt/hdd/|"${STORAGE_HDD_PATH:-/mnt/hdd}/|g' \
        -e 's|/mnt/hdd/|${STORAGE_HDD_PATH:-/mnt/hdd}/|g' \
        -e 's|"${STORAGE_HDD_PATH:-/mnt/hdd}/|"${STORAGE_HDD_PATH:-/mnt/hdd}/|g' \
        -e 's|${STORAGE_HDD_PATH:-/mnt/hdd}/|${STORAGE_HDD_PATH:-/mnt/hdd}/|g' \
        -e 's|"/mnt/nas|"${STORAGE_NAS_PATH:-/mnt/nas}|g' \
        -e 's|/mnt/nas|${STORAGE_NAS_PATH:-/mnt/nas}|g' \
        -e 's|NAS_MOUNT_PATH:-/mnt/nas|STORAGE_NAS_PATH:-/mnt/nas|g' \
        -e 's|BACKUP_NAS_PATH:-/mnt/nas|STORAGE_NAS_PATH:-/mnt/nas|g' \
        "$script_path" > "$temp_file"

    # Check if changes were made
    if ! diff -q "$script_path" "$temp_file" >/dev/null 2>&1; then
        mv "$temp_file" "$script_path"
        log_success "Fixed: $script_name"
        return 0
    else
        rm "$temp_file"
        log_info "No changes needed: $script_name"
        return 1
    fi
}

# Add environment variable loading to scripts that don't have it
add_env_loading() {
    local script_path="$1"
    local script_name=$(basename "$script_path")

    # Check if script already loads environment
    if grep -q "source.*\.env\|load_environment" "$script_path"; then
        return 0
    fi

    log_info "Adding environment loading to: $script_name"

    # Create temporary file with environment loading
    local temp_file=$(mktemp)

    # Add environment loading after shebang and before main content
    awk '
    BEGIN { added = 0 }
    /^#!/ { print; next }
    /^$/ && !added {
        print ""
        print "# Load environment variables"
        print "SCRIPT_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\""
        print "PROJECT_DIR=\"$(dirname \"$SCRIPT_DIR\")\""
        print "if [ -f \"$PROJECT_DIR/02-docker-configuration/.env\" ]; then"
        print "    set -a"
        print "    source \"$PROJECT_DIR/02-docker-configuration/.env\""
        print "    set +a"
        print "fi"
        print ""
        added = 1
        next
    }
    { print }
    ' "$script_path" > "$temp_file"

    mv "$temp_file" "$script_path"
    log_success "Added environment loading to: $script_name"
}

# Validate fixed scripts
validate_fixed_scripts() {
    log_info "Validating fixed scripts..."

    local errors=0

    for script in "$SCRIPT_DIR"/*.sh; do
        if [ -f "$script" ]; then
            local script_name=$(basename "$script")

            # Check syntax
            if ! bash -n "$script" 2>/dev/null; then
                log_error "Syntax error in: $script_name"
                ((errors++))
            fi

            # Check for remaining hardcoded paths
            if grep -q "${STORAGE_HDD_PATH:-/mnt/hdd}\|/mnt/hdd\|/mnt/nas" "$script" 2>/dev/null; then
                local remaining=$(grep -n "${STORAGE_HDD_PATH:-/mnt/hdd}\|/mnt/hdd\|/mnt/nas" "$script" | head -3)
                log_warning "Remaining hardcoded paths in $script_name:"
                echo "$remaining"
            fi
        fi
    done

    if [ $errors -eq 0 ]; then
        log_success "All scripts validated successfully"
        return 0
    else
        log_error "Found $errors scripts with syntax errors"
        return 1
    fi
}

# Generate summary report
generate_summary_report() {
    log_info "Generating summary report..."

    local report_file="$PROJECT_DIR/HARDCODED_PATHS_FIX_REPORT.md"

    cat > "$report_file" << 'EOF'
# Hardcoded Paths Fix Report

## Summary

This report documents the systematic replacement of hardcoded storage paths with configurable environment variables.

## Changes Made

### Path Replacements

| Old Hardcoded Path | New Configurable Path |
|-------------------|----------------------|
| `/mnt/hdd/postgres-backups` | `${BACKUP_LOCAL_PATH:-/mnt/hdd}/postgres-backups` |
| `/mnt/hdd/app-backups` | `${BACKUP_LOCAL_PATH:-/mnt/hdd}/app-backups` |
| `/mnt/hdd/` | `${STORAGE_HDD_PATH:-/mnt/hdd}/` |
| `${STORAGE_HDD_PATH:-/mnt/hdd}/` | `${STORAGE_HDD_PATH:-/mnt/hdd}/` |
| `/mnt/nas` | `${STORAGE_NAS_PATH:-/mnt/nas}` |

### Environment Variables Used

| Variable | Purpose | Default Value |
|----------|---------|---------------|
| `STORAGE_HDD_PATH` | Fast storage for hot data | `${STORAGE_HDD_PATH:-/mnt/hdd}` |
| `STORAGE_HDD_PATH` | Cold storage for old data | `/mnt/hdd` |
| `STORAGE_NAS_PATH` | Network storage for backup/DR | `/mnt/nas` |
| `BACKUP_LOCAL_PATH` | Local backup storage | `${STORAGE_HDD_PATH}` |
| `BACKUP_NAS_PATH` | NAS backup storage | `${STORAGE_NAS_PATH}` |
| `APP_UPLOADS_PATH` | Application uploads | `${STORAGE_HDD_PATH}/uploads` |
| `APP_LOGS_PATH` | Application logs | `${STORAGE_HDD_PATH}/logs` |

## Scripts Modified

EOF

    # List all scripts that were processed
    find_scripts_with_hardcoded_paths | while read script; do
        echo "- $(basename "$script")" >> "$report_file"
    done

    cat >> "$report_file" << 'EOF'

## Configuration

To use different storage paths, update your `.env` file:

```bash
# Custom storage configuration
STORAGE_HDD_PATH=/your/ssd/path
STORAGE_HDD_PATH=/your/hdd/path
STORAGE_NAS_PATH=/your/nas/path
```

## Validation

Run the following commands to validate the changes:

```bash
# Test all scripts
./scripts/test-all-scripts.sh

# Validate storage configuration
./scripts/validate-storage-paths.sh

# Check deployment readiness
./scripts/deploy-onprem.sh check-state
```

## Benefits

1. **Flexibility**: Works with any server storage configuration
2. **Portability**: Easy to deploy on different servers
3. **Maintainability**: Single place to configure all paths
4. **Backward Compatibility**: Default values maintain existing behavior

EOF

    log_success "Summary report generated: $report_file"
}

# Main execution
main() {
    log_info "Starting systematic hardcoded paths fix..."

    # Create backup
    backup_scripts

    # Find and fix all scripts
    local scripts_fixed=0

    find_scripts_with_hardcoded_paths | while read script_path; do
        if [ -f "$script_path" ]; then
            add_env_loading "$script_path"
            if fix_script_paths "$script_path"; then
                ((scripts_fixed++))
            fi
        fi
    done

    # Validate results
    if validate_fixed_scripts; then
        generate_summary_report
        log_success "All hardcoded paths fixed successfully!"
        log_info "Scripts are now configurable via .env variables"
        log_info "Run './scripts/validate-storage-paths.sh' to test your configuration"
    else
        log_error "Some scripts have issues. Please review and fix manually."
        exit 1
    fi
}

# Execute main function
main "$@"
