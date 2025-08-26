#!/bin/bash
# /opt/prs-deployment/scripts/check-prerequisites.sh
# Verify prerequisites before running PRS deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}              PRS Deployment Prerequisites Check              ${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}PASS: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARN: $1${NC}"
}

print_error() {
    echo -e "${RED}FAIL: $1${NC}"
}

print_info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

# Track overall status
OVERALL_STATUS=0

check_os() {
    echo -e "${BLUE}Operating System Check:${NC}"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "   OS: $PRETTY_NAME"

        if [[ "$ID" == "ubuntu" ]]; then
            if [[ "$VERSION_ID" == "24.04" ]]; then
                print_success "Ubuntu 24.04 LTS (optimal)"
            elif [[ "$VERSION_ID" == "22.04" ]]; then
                print_warning "Ubuntu 22.04 LTS (supported with warnings)"
            else
                print_warning "Ubuntu $VERSION_ID (may have compatibility issues)"
            fi
        else
            print_warning "Non-Ubuntu OS detected (deploy script optimized for Ubuntu)"
        fi
    else
        print_error "Cannot determine OS version"
        OVERALL_STATUS=1
    fi
    echo ""
}

check_memory() {
    echo -e "${BLUE}Memory Check:${NC}"

    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    echo "   Total RAM: ${TOTAL_RAM}GB"

    if [ "$TOTAL_RAM" -lt 15 ]; then
        print_error "Insufficient RAM: ${TOTAL_RAM}GB (16GB required by deploy script)"
        OVERALL_STATUS=1
    elif [ "$TOTAL_RAM" -lt 31 ]; then
        print_warning "RAM: ${TOTAL_RAM}GB (32GB recommended for optimal performance)"
    else
        print_success "RAM: ${TOTAL_RAM}GB (excellent)"
    fi
    echo ""
}

check_storage() {
    echo -e "${BLUE}Storage Mount Points Check:${NC}"

    # Load environment variables to get configurable paths
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    if [ -f "$PROJECT_DIR/02-docker-configuration/.env" ]; then
        set -a
        source "$PROJECT_DIR/02-docker-configuration/.env" 2>/dev/null || true
        set +a
    fi

    # Use configurable storage paths
    local HDD_PATH="${STORAGE_HDD_PATH:-/mnt/hdd}"
    local NAS_PATH="${STORAGE_NAS_PATH:-/mnt/nas}"

    # Check HDD storage (CRITICAL - deploy script checks this)
    if [ -d "$HDD_PATH" ]; then
        print_success "HDD storage exists: $HDD_PATH"
        if mountpoint -q "$HDD_PATH" 2>/dev/null; then
            local hdd_space=$(df -h "$HDD_PATH" | awk 'NR==2{print $4}')
            echo "   Available space: $hdd_space"
        else
            print_warning "HDD path exists but not mounted: $HDD_PATH"
        fi
    else
        print_error "HDD storage missing - DEPLOY SCRIPT WILL FAIL: $HDD_PATH"
        echo "   Create with: sudo mkdir -p $HDD_PATH"
        OVERALL_STATUS=1
    fi

    # Check NAS storage (optional)
    if [ "${BACKUP_TO_NAS:-false}" = "true" ]; then
        if [ -d "$NAS_PATH" ]; then
            print_success "NAS storage exists: $NAS_PATH"
        else
            print_warning "NAS storage missing: $NAS_PATH (will be created during deployment)"
        fi
    fi

    echo ""
}

check_user() {
    echo -e "${BLUE}User Account Check:${NC}"

    # Check if running as root (deploy script checks this)
    if [ "$EUID" -eq 0 ]; then
        print_error "Running as root - DEPLOY SCRIPT WILL FAIL"
        echo "   Deploy script checks: if [[ \$EUID -eq 0 ]]; then exit 1"
        echo "   Switch to non-root user before deployment"
        OVERALL_STATUS=1
    else
        print_success "Running as non-root user: $USER"

        # Check sudo access
        if sudo -n true 2>/dev/null; then
            print_success "User has sudo access"
        else
            print_warning "Cannot verify sudo access (may require password)"
        fi
    fi
    echo ""
}

check_network() {
    echo -e "${BLUE}Network Configuration Check:${NC}"

    # Get IP addresses
    local ips=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d'/' -f1)

    if [ -n "$ips" ]; then
        print_success "Network interfaces configured:"
        for ip in $ips; do
            echo "   IP: $ip"
        done

        # Check if any IP is in the office network range (192.168.0.0/20)
        if echo "$ips" | grep -E "^192\.168\.(0|1|2|3|4|5|6|7|8|9|10|11|12|13|14|15)\." >/dev/null; then
            print_success "Office network IP detected (192.168.0.0/20 range)"
        elif echo "$ips" | grep -E "^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\." >/dev/null; then
            print_warning "Private network IP detected (not in office 192.168.0.0/20 range)"
        fi
    else
        print_error "No network interfaces configured"
        OVERALL_STATUS=1
    fi

    # Test internet connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_success "Internet connectivity available"
    else
        print_warning "No internet connectivity (may affect package installation)"
    fi
    echo ""
}

check_docker() {
    echo -e "${BLUE}Docker Check:${NC}"

    if command -v docker >/dev/null 2>&1; then
        print_info "Docker already installed (deploy script will verify/update)"
        local docker_version=$(docker --version 2>/dev/null || echo "unknown")
        echo "   Version: $docker_version"

        # Check if Docker daemon is running
        if docker ps >/dev/null 2>&1; then
            print_success "Docker daemon is running"
        else
            print_warning "Docker daemon not running (deploy script will start it)"
        fi
    else
        print_info "Docker not installed (deploy script will install it)"
    fi
    echo ""
}

check_github_cli() {
    echo -e "${BLUE}GitHub CLI Check:${NC}"

    if command -v gh >/dev/null 2>&1; then
        print_success "GitHub CLI installed"
        local gh_version=$(gh --version 2>/dev/null | head -n1 || echo "unknown")
        echo "   Version: $gh_version"

        # Check if authenticated
        if gh auth status >/dev/null 2>&1; then
            print_success "GitHub CLI authenticated"
        else
            print_error "GitHub CLI not authenticated - run 'gh auth login'"
            echo "   Deploy script needs access to private repositories"
            OVERALL_STATUS=1
        fi
    else
        print_error "GitHub CLI not installed - REQUIRED for deployment"
        echo "   Install with: curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg"
        echo "   Then: sudo apt update && sudo apt install gh"
        OVERALL_STATUS=1
    fi
    echo ""
}

check_repository_structure() {
    echo -e "${BLUE}Repository Structure Check:${NC}"

    # Check if we're in the right directory structure
    local current_dir=$(pwd)
    local expected_dir="/opt/prs/prs-deployment/scripts"

    if [ "$current_dir" = "$expected_dir" ]; then
        print_success "Running from correct directory: $current_dir"
    else
        print_warning "Not in expected directory"
        echo "   Current: $current_dir"
        echo "   Expected: $expected_dir"
    fi

    # Check if base directory exists
    if [ -d "/opt/prs" ]; then
        print_success "/opt/prs base directory exists"
    else
        print_error "/opt/prs base directory missing"
        echo "   Create with: sudo mkdir -p /opt/prs && sudo chown \$USER:\$USER /opt/prs"
        OVERALL_STATUS=1
    fi

    # Check if deployment repository exists
    if [ -d "/opt/prs/prs-deployment" ]; then
        print_success "prs-deployment repository exists"

        # Check if deploy script exists
        if [ -f "/opt/prs/prs-deployment/scripts/deploy-onprem.sh" ]; then
            print_success "deploy-onprem.sh script found"
        else
            print_error "deploy-onprem.sh script missing"
            OVERALL_STATUS=1
        fi
    else
        print_error "prs-deployment repository missing"
        echo "   Clone with: cd /opt/prs && git clone https://github.com/stratpoint-engineering/prs-deployment.git"
        OVERALL_STATUS=1
    fi
    echo ""
}

show_summary() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}                    Prerequisites Summary                     ${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""

    if [ $OVERALL_STATUS -eq 0 ]; then
        print_success "All critical prerequisites met!"
        echo ""
        echo -e "${GREEN}Ready for deployment:${NC}"
        echo "   1. cd /opt/prs/prs-deployment/scripts"
        echo "   2. ./quick-setup-helper.sh"
        echo "   3. ./deploy-onprem.sh deploy"
    else
        print_error "Critical prerequisites missing!"
        echo ""
        echo -e "${RED}Fix these issues before deployment:${NC}"
        echo "   • Ensure storage paths exist (check .env for STORAGE_HDD_PATH)"
        echo "   • Use non-root user account"
        echo "   • Verify sufficient RAM (16GB+)"
        echo "   • Install and authenticate GitHub CLI (gh auth login)"
        echo "   • Clone prs-deployment repository to /opt/prs/"
        echo ""
        echo -e "${YELLOW}See full setup guide:${NC}"
        echo "   /opt/prs-deployment/docs/docs/getting-started/prerequisites.md"
    fi
    echo ""
}

# Main execution
main() {
    print_header

    print_info "Checking prerequisites for PRS deployment..."
    print_info "This verifies requirements checked by deploy-onprem.sh script"
    echo ""

    check_os
    check_memory
    check_storage
    check_user
    check_network
    check_docker
    check_github_cli
    check_repository_structure

    show_summary

    exit $OVERALL_STATUS
}

# Run main function
main "$@"
