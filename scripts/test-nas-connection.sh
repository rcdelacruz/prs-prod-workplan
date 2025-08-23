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

# Load environment variables
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/02-docker-configuration/.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

test_nas_connectivity() {
    log_message "Testing NAS connectivity"

    if [ -z "$NAS_HOST" ]; then
        log_message "ERROR: NAS_HOST not configured"
        return 1
    fi

    # Test network connectivity
    log_message "Testing network connectivity to $NAS_HOST"
    if ping -c 3 "$NAS_HOST" >/dev/null 2>&1; then
        log_message "✅ Network connectivity to NAS successful"
    else
        log_message "❌ Network connectivity to NAS failed"
        return 1
    fi

    # Test specific ports
    if [ -n "$NAS_USERNAME" ]; then
        # Test SMB/CIFS ports
        log_message "Testing SMB/CIFS connectivity (port 445)"
        if timeout 5 bash -c "</dev/tcp/$NAS_HOST/445" 2>/dev/null; then
            log_message "✅ SMB/CIFS port 445 accessible"
        else
            log_message "❌ SMB/CIFS port 445 not accessible"
            return 1
        fi
    else
        # Test NFS port
        log_message "Testing NFS connectivity (port 2049)"
        if timeout 5 bash -c "</dev/tcp/$NAS_HOST/2049" 2>/dev/null; then
            log_message "✅ NFS port 2049 accessible"
        else
            log_message "❌ NFS port 2049 not accessible"
            return 1
        fi
    fi

    return 0
}

test_nas_mount() {
    log_message "Testing NAS mount functionality"

    # Create mount point
    mkdir -p "$NAS_MOUNT_PATH"

    # Check if already mounted
    if mountpoint -q "$NAS_MOUNT_PATH"; then
        log_message "NAS already mounted, unmounting for test"
        umount "$NAS_MOUNT_PATH" || {
            log_message "ERROR: Failed to unmount existing NAS mount"
            return 1
        }
    fi

    # Attempt mount
    if [ -n "$NAS_USERNAME" ] && [ -n "$NAS_PASSWORD" ]; then
        # CIFS/SMB mount
        log_message "Testing CIFS/SMB mount: //$NAS_HOST/$NAS_SHARE"
        if mount -t cifs "//$NAS_HOST/$NAS_SHARE" "$NAS_MOUNT_PATH" \
            -o username="$NAS_USERNAME",password="$NAS_PASSWORD",uid=0,gid=0,file_mode=0600,dir_mode=0700; then
            log_message "✅ CIFS/SMB mount successful"
        else
            log_message "❌ CIFS/SMB mount failed"
            return 1
        fi
    else
        # NFS mount
        log_message "Testing NFS mount: $NAS_HOST:/$NAS_SHARE"
        if mount -t nfs "$NAS_HOST:/$NAS_SHARE" "$NAS_MOUNT_PATH"; then
            log_message "✅ NFS mount successful"
        else
            log_message "❌ NFS mount failed"
            return 1
        fi
    fi

    return 0
}

test_nas_read_write() {
    log_message "Testing NAS read/write functionality"

    if ! mountpoint -q "$NAS_MOUNT_PATH"; then
        log_message "ERROR: NAS not mounted"
        return 1
    fi

    local test_dir="$NAS_MOUNT_PATH/prs-test-$(date +%s)"
    local test_file="$test_dir/test-file.txt"
    local test_data="PRS NAS Test - $(date)"

    # Create test directory
    if mkdir -p "$test_dir"; then
        log_message "✅ NAS directory creation successful"
    else
        log_message "❌ NAS directory creation failed"
        return 1
    fi

    # Write test file
    if echo "$test_data" > "$test_file"; then
        log_message "✅ NAS file write successful"
    else
        log_message "❌ NAS file write failed"
        return 1
    fi

    # Read test file
    if [ "$(cat "$test_file")" = "$test_data" ]; then
        log_message "✅ NAS file read successful"
    else
        log_message "❌ NAS file read failed"
        return 1
    fi

    # Test large file (simulate backup)
    log_message "Testing large file operations (simulating backup)"
    local large_file="$test_dir/large-test.dat"
    if dd if=/dev/zero of="$large_file" bs=1M count=100 2>/dev/null; then
        local file_size=$(stat -c%s "$large_file")
        log_message "✅ Large file write successful ($(numfmt --to=iec $file_size))"
    else
        log_message "❌ Large file write failed"
        return 1
    fi

    # Cleanup test files
    rm -rf "$test_dir"
    log_message "✅ Test cleanup completed"

    return 0
}

test_backup_directories() {
    log_message "Testing backup directory structure"

    if ! mountpoint -q "$NAS_MOUNT_PATH"; then
        log_message "ERROR: NAS not mounted"
        return 1
    fi

    # Create backup directory structure
    local backup_dirs=(
        "$NAS_MOUNT_PATH/postgres-backups/daily"
        "$NAS_MOUNT_PATH/app-backups"
        "$NAS_MOUNT_PATH/redis-backups"
    )

    for dir in "${backup_dirs[@]}"; do
        if mkdir -p "$dir"; then
            log_message "✅ Created backup directory: $dir"
        else
            log_message "❌ Failed to create backup directory: $dir"
            return 1
        fi
    done

    return 0
}

cleanup_and_unmount() {
    log_message "Cleaning up and unmounting NAS"

    if mountpoint -q "$NAS_MOUNT_PATH"; then
        if umount "$NAS_MOUNT_PATH"; then
            log_message "✅ NAS unmounted successfully"
        else
            log_message "❌ Failed to unmount NAS"
            return 1
        fi
    fi

    return 0
}

main() {
    log_message "Starting NAS connection test"
    log_message "NAS Host: $NAS_HOST"
    log_message "NAS Share: $NAS_SHARE"
    log_message "Mount Path: $NAS_MOUNT_PATH"

    # Run tests
    if test_nas_connectivity; then
        log_message "✅ NAS connectivity test passed"
    else
        log_message "❌ NAS connectivity test failed"
        exit 1
    fi

    if test_nas_mount; then
        log_message "✅ NAS mount test passed"
    else
        log_message "❌ NAS mount test failed"
        exit 1
    fi

    if test_nas_read_write; then
        log_message "✅ NAS read/write test passed"
    else
        log_message "❌ NAS read/write test failed"
        cleanup_and_unmount
        exit 1
    fi

    if test_backup_directories; then
        log_message "✅ Backup directory test passed"
    else
        log_message "❌ Backup directory test failed"
        cleanup_and_unmount
        exit 1
    fi

    cleanup_and_unmount

    log_message "🎉 All NAS tests passed successfully!"
    log_message "Your NAS is ready for PRS backup integration"

    echo ""
    echo "✅ NAS Connection Test Results:"
    echo "   - Network connectivity: PASSED"
    echo "   - Mount functionality: PASSED"
    echo "   - Read/Write operations: PASSED"
    echo "   - Backup directories: PASSED"
    echo ""
    echo "Your NAS is ready for production backup use!"
    echo "You can now run backup scripts with NAS integration enabled."
}

main "$@"
