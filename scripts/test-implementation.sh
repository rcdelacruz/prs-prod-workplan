#!/bin/bash

# 🧪 Implementation Testing Script
# Automated testing for prs.citylandcondo.com SSL implementation

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$PROJECT_DIR/scripts"
SSL_DIR="$PROJECT_DIR/02-docker-configuration/ssl"
NGINX_CONFIG="$PROJECT_DIR/02-docker-configuration/nginx/sites-enabled/prs-onprem.conf"
DOCKER_COMPOSE_FILE="$PROJECT_DIR/02-docker-configuration/docker-compose.onprem.yml"

# Test domain (change this to your test domain)
TEST_DOMAIN="test.yourdomain.com"
PRODUCTION_DOMAIN="prs.citylandcondo.com"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging
LOG_FILE="/tmp/implementation-test-$(date +%Y%m%d_%H%M%S).log"

# Print functions
print_header() {
    echo -e "${BLUE}"
    echo "=============================================="
    echo "🧪 PRS Implementation Testing"
    echo "=============================================="
    echo -e "${NC}"
}

print_test() {
    echo -e "${BLUE}🧪 Test $1: $2${NC}"
    echo "Test $1: $2" >> "$LOG_FILE"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

print_pass() {
    echo -e "${GREEN}✅ PASS: $1${NC}"
    echo "PASS: $1" >> "$LOG_FILE"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
    echo -e "${RED}❌ FAIL: $1${NC}"
    echo "FAIL: $1" >> "$LOG_FILE"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_warning() {
    echo -e "${YELLOW}⚠️ WARNING: $1${NC}"
    echo "WARNING: $1" >> "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}ℹ️ $1${NC}"
    echo "INFO: $1" >> "$LOG_FILE"
}

# Test functions
test_prerequisites() {
    print_test "1" "Prerequisites Check"

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_pass "Running as root/sudo"
    else
        print_fail "Must run as root or with sudo"
        return 1
    fi

    # Check project directory
    if [ -d "$PROJECT_DIR" ]; then
        print_pass "Project directory exists"
    else
        print_fail "Project directory not found: $PROJECT_DIR"
        return 1
    fi

    # Check Docker
    if docker info &> /dev/null; then
        print_pass "Docker is running"
    else
        print_fail "Docker is not running"
        return 1
    fi

    # Check if PRS containers are running
    if docker compose -f "$DOCKER_COMPOSE_FILE" ps | grep -q "Up"; then
        print_pass "PRS containers are running"
    else
        print_warning "Some PRS containers may not be running"
    fi
}

test_script_syntax() {
    print_test "2" "Script Syntax Validation"

    local scripts=(
        "ssl-automation-citylandcondo.sh"
        "ssl-renewal-monitor.sh"
        "setup-custom-domain.sh"
    )

    for script in "${scripts[@]}"; do
        if [ -f "$SCRIPTS_DIR/$script" ]; then
            if bash -n "$SCRIPTS_DIR/$script"; then
                print_pass "Script syntax valid: $script"
            else
                print_fail "Script syntax error: $script"
            fi
        else
            print_fail "Script not found: $script"
        fi
    done

    # Check script permissions
    for script in "${scripts[@]}"; do
        if [ -x "$SCRIPTS_DIR/$script" ]; then
            print_pass "Script executable: $script"
        else
            print_fail "Script not executable: $script"
        fi
    done
}

test_nginx_configuration() {
    print_test "3" "Nginx Configuration"

    # Check nginx config file exists
    if [ -f "$NGINX_CONFIG" ]; then
        print_pass "Nginx config file exists"
    else
        print_fail "Nginx config file not found"
        return 1
    fi

    # Test nginx configuration syntax
    if docker exec prs-onprem-nginx nginx -t &> /dev/null; then
        print_pass "Nginx configuration syntax valid"
    else
        print_fail "Nginx configuration syntax error"
    fi

    # Check for required server blocks
    if grep -q "server_name prs.citylandcondo.com" "$NGINX_CONFIG"; then
        print_pass "Production domain configured in nginx"
    else
        print_fail "Production domain not found in nginx config"
    fi

    if grep -q "192.168.0.100" "$NGINX_CONFIG"; then
        print_pass "Correct IP address in nginx config"
    else
        print_fail "Incorrect IP address in nginx config"
    fi
}

test_ssl_directory() {
    print_test "4" "SSL Directory Structure"

    # Check SSL directory exists
    if [ -d "$SSL_DIR" ]; then
        print_pass "SSL directory exists"
    else
        print_fail "SSL directory not found"
        mkdir -p "$SSL_DIR"
        print_info "Created SSL directory"
    fi

    # Check for existing certificates
    if [ -f "$SSL_DIR/server.crt" ]; then
        print_info "Existing certificate found"

        # Check certificate validity
        if openssl x509 -checkend 86400 -noout -in "$SSL_DIR/server.crt" &> /dev/null; then
            print_pass "Existing certificate is valid"
        else
            print_warning "Existing certificate is expired or invalid"
        fi
    else
        print_info "No existing certificate found (normal for new setup)"
    fi

    # Check directory permissions
    if [ -w "$SSL_DIR" ]; then
        print_pass "SSL directory is writable"
    else
        print_fail "SSL directory is not writable"
    fi
}

test_current_access() {
    print_test "5" "Current System Access"

    # Test HTTP access to health endpoint
    if curl -s --connect-timeout 10 "http://192.168.0.100/health" | grep -q "healthy"; then
        print_pass "HTTP health endpoint accessible"
    else
        print_warning "HTTP health endpoint not accessible"
    fi

    # Test HTTPS access (may fail with self-signed cert)
    if curl -k -s --connect-timeout 10 "https://192.168.0.100/health" | grep -q "healthy"; then
        print_pass "HTTPS health endpoint accessible"
    else
        print_fail "HTTPS health endpoint not accessible"
    fi

    # Test nginx container
    if docker ps | grep -q "prs-onprem-nginx"; then
        print_pass "Nginx container is running"
    else
        print_fail "Nginx container is not running"
    fi
}

test_monitoring_scripts() {
    print_test "6" "Monitoring Scripts"

    # Test SSL monitoring script
    if "$SCRIPTS_DIR/ssl-renewal-monitor.sh" check &> /dev/null; then
        print_pass "SSL monitoring script executes"
    else
        print_warning "SSL monitoring script has issues (may be normal without certificates)"
    fi

    # Test connectivity check
    if "$SCRIPTS_DIR/ssl-renewal-monitor.sh" test &> /dev/null; then
        print_pass "Connectivity test script executes"
    else
        print_warning "Connectivity test has issues"
    fi

    # Check if cron would work
    if command -v crontab &> /dev/null; then
        print_pass "Crontab available for scheduling"
    else
        print_fail "Crontab not available"
    fi
}

test_dependencies() {
    print_test "7" "Required Dependencies"

    local deps=("curl" "openssl" "docker")

    for dep in "${deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            print_pass "Dependency available: $dep"
        else
            print_fail "Dependency missing: $dep"
        fi
    done

    # Check docker compose (newer version)
    if docker compose version &> /dev/null; then
        print_pass "Docker Compose available (v2)"
    elif command -v docker-compose &> /dev/null; then
        print_pass "Docker Compose available (v1)"
    else
        print_fail "Docker Compose not available"
    fi

    # Check if certbot is available (may not be installed yet)
    if command -v certbot &> /dev/null; then
        print_pass "Certbot is available"
    else
        print_info "Certbot not installed (will be installed during setup)"
    fi
}

test_network_configuration() {
    print_test "8" "Network Configuration"

    # Check if server is accessible on expected IP
    if ip addr show | grep -q "192.168.0.100"; then
        print_pass "Server has correct IP address (192.168.0.100)"
    else
        print_warning "Server IP may not be 192.168.0.100"
        print_info "Current IPs: $(ip addr show | grep 'inet ' | awk '{print $2}')"
    fi

    # Check if port 80 is available
    if ! netstat -tlnp | grep -q ":80 "; then
        print_pass "Port 80 is available"
    else
        print_warning "Port 80 is already in use"
    fi

    # Check if port 443 is in use (should be by nginx)
    if netstat -tlnp | grep -q ":443 "; then
        print_pass "Port 443 is in use (nginx)"
    else
        print_warning "Port 443 is not in use"
    fi
}

test_docker_environment() {
    print_test "9" "Docker Environment"

    # Check docker-compose file
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        print_pass "Docker compose file exists"
    else
        print_fail "Docker compose file not found"
        return 1
    fi

    # Test docker-compose syntax
    if docker compose -f "$DOCKER_COMPOSE_FILE" config &> /dev/null; then
        print_pass "Docker compose configuration valid"
    else
        print_fail "Docker compose configuration error"
    fi

    # Check for nginx service
    if docker compose -f "$DOCKER_COMPOSE_FILE" config | grep -q "nginx:"; then
        print_pass "Nginx service defined in compose"
    else
        print_fail "Nginx service not found in compose"
    fi
}

test_file_permissions() {
    print_test "10" "File Permissions"

    # Check script permissions
    local scripts=(
        "ssl-automation-citylandcondo.sh"
        "ssl-renewal-monitor.sh"
        "setup-custom-domain.sh"
    )

    for script in "${scripts[@]}"; do
        if [ -x "$SCRIPTS_DIR/$script" ]; then
            print_pass "Script executable: $script"
        else
            print_fail "Script not executable: $script"
            chmod +x "$SCRIPTS_DIR/$script" 2>/dev/null && print_info "Fixed permissions for $script"
        fi
    done

    # Check SSL directory permissions
    if [ -w "$SSL_DIR" ]; then
        print_pass "SSL directory writable"
    else
        print_fail "SSL directory not writable"
    fi
}

# Generate test report
generate_report() {
    echo ""
    echo -e "${BLUE}=============================================="
    echo "📊 Test Results Summary"
    echo "===============================================${NC}"
    echo ""
    echo "Total Tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed! Ready for implementation.${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Configure DNS in GoDaddy"
        echo "2. Run: sudo $SCRIPTS_DIR/setup-custom-domain.sh"
        echo "3. Test with client domain"
    else
        echo -e "${RED}⚠️ Some tests failed. Please review and fix issues.${NC}"
        echo ""
        echo "Check the log file for details: $LOG_FILE"
    fi

    echo ""
    echo "Detailed log: $LOG_FILE"
}

# Main execution
main() {
    print_header

    echo "Starting implementation testing..."
    echo "Log file: $LOG_FILE"
    echo ""

    # Initialize log
    echo "PRS Implementation Test - $(date)" > "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"

    # Run all tests
    test_prerequisites
    test_script_syntax
    test_nginx_configuration
    test_ssl_directory
    test_current_access
    test_monitoring_scripts
    test_dependencies
    test_network_configuration
    test_docker_environment
    test_file_permissions

    # Generate report
    generate_report
}

# Script entry point
case "${1:-main}" in
    "main"|"")
        main
        ;;
    "quick")
        print_header
        test_prerequisites
        test_script_syntax
        test_current_access
        generate_report
        ;;
    "network")
        print_header
        test_network_configuration
        test_current_access
        generate_report
        ;;
    "scripts")
        print_header
        test_script_syntax
        test_monitoring_scripts
        test_file_permissions
        generate_report
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  main (default) - Run all tests"
        echo "  quick          - Run essential tests only"
        echo "  network        - Run network-related tests only"
        echo "  scripts        - Run script-related tests only"
        echo "  help           - Show this help message"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
