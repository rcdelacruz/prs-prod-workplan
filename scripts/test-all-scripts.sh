#!/bin/bash

# Comprehensive Script Testing Framework
# Tests all deployment and operational scripts

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_LOG="/var/log/prs-script-tests.log"
TEST_RESULTS_DIR="$PROJECT_DIR/test-results"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$TEST_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$TEST_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$TEST_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$TEST_LOG"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1" | tee -a "$TEST_LOG"
}

# Test result tracking
test_start() {
    local test_name="$1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    log_test "Starting: $test_name"
}

test_pass() {
    local test_name="$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "PASSED: $test_name"
}

test_fail() {
    local test_name="$1"
    local reason="$2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_error "FAILED: $test_name - $reason"
}

test_skip() {
    local test_name="$1"
    local reason="$2"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    log_warning "SKIPPED: $test_name - $reason"
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up test environment..."
    
    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Clear previous test log
    > "$TEST_LOG"
    
    # Create test timestamp
    echo "Test run started: $(date)" | tee -a "$TEST_LOG"
    
    log_success "Test environment ready"
}

# Test script syntax
test_script_syntax() {
    local script_path="$1"
    local script_name=$(basename "$script_path")
    
    test_start "Syntax check: $script_name"
    
    if [ ! -f "$script_path" ]; then
        test_skip "Syntax check: $script_name" "Script not found"
        return
    fi
    
    if bash -n "$script_path" 2>/dev/null; then
        test_pass "Syntax check: $script_name"
    else
        test_fail "Syntax check: $script_name" "Syntax errors found"
    fi
}

# Test script permissions
test_script_permissions() {
    local script_path="$1"
    local script_name=$(basename "$script_path")
    
    test_start "Permissions check: $script_name"
    
    if [ ! -f "$script_path" ]; then
        test_skip "Permissions check: $script_name" "Script not found"
        return
    fi
    
    if [ -x "$script_path" ]; then
        test_pass "Permissions check: $script_name"
    else
        test_fail "Permissions check: $script_name" "Script not executable"
    fi
}

# Test script help/usage
test_script_help() {
    local script_path="$1"
    local script_name=$(basename "$script_path")
    
    test_start "Help check: $script_name"
    
    if [ ! -f "$script_path" ]; then
        test_skip "Help check: $script_name" "Script not found"
        return
    fi
    
    # Try common help flags
    if "$script_path" --help >/dev/null 2>&1 || "$script_path" -h >/dev/null 2>&1 || "$script_path" help >/dev/null 2>&1; then
        test_pass "Help check: $script_name"
    else
        test_skip "Help check: $script_name" "No help option available"
    fi
}

# Test environment file loading
test_environment_loading() {
    test_start "Environment loading"
    
    if [ -f "$PROJECT_DIR/02-docker-configuration/.env" ]; then
        if source "$PROJECT_DIR/02-docker-configuration/.env" 2>/dev/null; then
            test_pass "Environment loading"
        else
            test_fail "Environment loading" "Failed to source .env file"
        fi
    else
        test_fail "Environment loading" ".env file not found"
    fi
}

# Test storage path validation
test_storage_validation() {
    test_start "Storage path validation"
    
    if [ -f "$SCRIPT_DIR/validate-storage-paths.sh" ]; then
        if "$SCRIPT_DIR/validate-storage-paths.sh" >/dev/null 2>&1; then
            test_pass "Storage path validation"
        else
            test_fail "Storage path validation" "Storage validation failed"
        fi
    else
        test_skip "Storage path validation" "Validation script not found"
    fi
}

# Test Docker availability
test_docker_availability() {
    test_start "Docker availability"
    
    if command -v docker >/dev/null 2>&1; then
        if docker ps >/dev/null 2>&1; then
            test_pass "Docker availability"
        else
            test_fail "Docker availability" "Docker daemon not running"
        fi
    else
        test_fail "Docker availability" "Docker not installed"
    fi
}

# Test backup scripts
test_backup_scripts() {
    local backup_scripts=(
        "backup-full.sh"
        "backup-application-data.sh"
        "verify-backups.sh"
        "setup-backup-automation.sh"
        "restore-database.sh"
    )
    
    for script in "${backup_scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        test_script_syntax "$script_path"
        test_script_permissions "$script_path"
    done
}

# Test TimescaleDB scripts
test_timescaledb_scripts() {
    local timescaledb_scripts=(
        "setup-timescaledb-data-movement.sh"
        "timescaledb-auto-optimizer.sh"
        "timescaledb-post-setup-optimization.sh"
    )
    
    for script in "${timescaledb_scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        test_script_syntax "$script_path"
        test_script_permissions "$script_path"
    done
}

# Test deployment scripts
test_deployment_scripts() {
    local deployment_scripts=(
        "deploy-onprem.sh"
        "validate-storage-paths.sh"
    )
    
    for script in "${deployment_scripts[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        test_script_syntax "$script_path"
        test_script_permissions "$script_path"
        test_script_help "$script_path"
    done
}

# Test configuration files
test_configuration_files() {
    local config_files=(
        "02-docker-configuration/.env"
        "02-docker-configuration/docker-compose.onprem.yml"
        "02-docker-configuration/nginx/nginx.conf"
    )
    
    for config in "${config_files[@]}"; do
        local config_path="$PROJECT_DIR/$config"
        local config_name=$(basename "$config")
        
        test_start "Config check: $config_name"
        
        if [ -f "$config_path" ]; then
            test_pass "Config check: $config_name"
        else
            test_fail "Config check: $config_name" "Configuration file not found"
        fi
    done
}

# Test dry-run capabilities
test_dry_run_capabilities() {
    test_start "Dry-run capabilities"
    
    # Test deploy script dry-run
    if [ -f "$SCRIPT_DIR/deploy-onprem.sh" ]; then
        if "$SCRIPT_DIR/deploy-onprem.sh" check-state >/dev/null 2>&1; then
            test_pass "Dry-run capabilities"
        else
            test_skip "Dry-run capabilities" "Check-state not available"
        fi
    else
        test_skip "Dry-run capabilities" "Deploy script not found"
    fi
}

# Generate test report
generate_test_report() {
    log_info "Generating test report..."
    
    local report_file="$TEST_RESULTS_DIR/test-report-$(date +%Y%m%d-%H%M%S).md"
    
    cat > "$report_file" << EOF
# PRS Script Testing Report

**Generated**: $(date)
**Test Environment**: $(hostname)
**User**: $(whoami)

## Test Summary

| Metric | Count |
|--------|-------|
| **Total Tests** | $TESTS_TOTAL |
| **Passed** | $TESTS_PASSED |
| **Failed** | $TESTS_FAILED |
| **Skipped** | $TESTS_SKIPPED |

## Test Results

### Success Rate
- **Pass Rate**: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%
- **Failure Rate**: $(( TESTS_FAILED * 100 / TESTS_TOTAL ))%

### Detailed Results
See full test log: \`$TEST_LOG\`

## Recommendations

EOF

    if [ $TESTS_FAILED -eq 0 ]; then
        echo "✅ **All tests passed!** Your scripts are ready for deployment." >> "$report_file"
    else
        echo "⚠️ **$TESTS_FAILED tests failed.** Please review and fix issues before deployment." >> "$report_file"
    fi
    
    if [ $TESTS_SKIPPED -gt 0 ]; then
        echo "ℹ️ **$TESTS_SKIPPED tests were skipped.** Some features may not be available." >> "$report_file"
    fi
    
    log_success "Test report saved: $report_file"
}

# Main test execution
main() {
    log_info "Starting comprehensive script testing..."
    
    setup_test_environment
    
    # Core system tests
    test_environment_loading
    test_docker_availability
    test_storage_validation
    
    # Script tests
    test_deployment_scripts
    test_backup_scripts
    test_timescaledb_scripts
    
    # Configuration tests
    test_configuration_files
    
    # Capability tests
    test_dry_run_capabilities
    
    # Generate report
    generate_test_report
    
    # Final summary
    log_info "Test Summary: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All tests passed! Scripts are ready for deployment."
        exit 0
    else
        log_error "$TESTS_FAILED tests failed. Please review issues."
        exit 1
    fi
}

# Execute main function
main "$@"
