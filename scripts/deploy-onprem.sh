#!/bin/bash

# PRS On-Premises Production Deployment Script
# Adapted from EC2 deploy-ec2.sh for on-premises infrastructure
# Optimized for 16GB RAM, 100 concurrent users
# Container apps run on SSD (OS), data storage on HDD for cost efficiency

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Environment-specific configuration files
get_env_file() {
    local env="$1"
    case "$env" in
        "dev")
            echo "$PROJECT_DIR/02-docker-configuration/.env.dev"
            ;;
        "staging")
            echo "$PROJECT_DIR/02-docker-configuration/.env.staging"
            ;;
        "prod")
            echo "$PROJECT_DIR/02-docker-configuration/.env"
            ;;
        "test")
            echo "$PROJECT_DIR/02-docker-configuration/.env.test"
            ;;
        *)
            echo "$PROJECT_DIR/02-docker-configuration/.env"
            ;;
    esac
}

get_compose_file() {
    local env="$1"
    case "$env" in
        "dev")
            echo "$PROJECT_DIR/02-docker-configuration/docker-compose.dev.yml"
            ;;
        "staging")
            echo "$PROJECT_DIR/02-docker-configuration/docker-compose.staging.yml"
            ;;
        "prod")
            echo "$PROJECT_DIR/02-docker-configuration/docker-compose.onprem.yml"
            ;;
        "test")
            echo "$PROJECT_DIR/02-docker-configuration/docker-compose.test.yml"
            ;;
        *)
            echo "$PROJECT_DIR/02-docker-configuration/docker-compose.onprem.yml"
            ;;
    esac
}

# Set environment-specific files
ENV_FILE=$(get_env_file "$DEPLOY_ENV")
COMPOSE_FILE=$(get_compose_file "$DEPLOY_ENV")

# Deployment environment configuration
DEPLOY_ENV="${DEPLOY_ENV:-prod}"
VALID_ENVIRONMENTS=("dev" "staging" "prod" "test")

# Repository configuration (can be overridden via environment variables)
BACKEND_REPO_URL="${BACKEND_REPO_URL:-https://github.com/stratpoint-engineering/prs-backend-a.git}"
FRONTEND_REPO_URL="${FRONTEND_REPO_URL:-https://github.com/stratpoint-engineering/prs-frontend-a.git}"
BACKEND_BRANCH="${BACKEND_BRANCH:-main}"
FRONTEND_BRANCH="${FRONTEND_BRANCH:-main}"
REPO_BASE_DIR="${REPO_BASE_DIR:-/opt/prs}"

# Detect system architecture for Docker builds
detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "linux/amd64"
            ;;
        aarch64|arm64)
            echo "linux/arm64"
            ;;
        armv7l)
            echo "linux/arm/v7"
            ;;
        *)
            log_warning "Unknown architecture: $arch, defaulting to linux/amd64"
            echo "linux/amd64"
            ;;
    esac
}

# Get Docker platform for current architecture (can be overridden via environment variable)
DOCKER_PLATFORM="${DOCKER_PLATFORM:-$(detect_architecture)}"

# Docker commands
DOCKER_CMD="docker"
COMPOSE_CMD="docker compose"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# State tracking
STATE_DIR="/var/lib/prs-deploy"
SETUP_COMPLETE_FLAG="$STATE_DIR/setup-complete"
DEPLOY_COMPLETE_FLAG="$STATE_DIR/deploy-complete"

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

# State management functions
create_state_dir() {
    if [ ! -d "$STATE_DIR" ]; then
        sudo mkdir -p "$STATE_DIR"
        sudo chown $USER:$USER "$STATE_DIR"
        log_info "Created state directory: $STATE_DIR"
    fi
}

mark_setup_complete() {
    create_state_dir
    touch "$SETUP_COMPLETE_FLAG"
    log_info "Marked setup as complete"
}

mark_deploy_complete() {
    create_state_dir
    touch "$DEPLOY_COMPLETE_FLAG"
    log_info "Marked deployment as complete"
}

is_setup_complete() {
    [ -f "$SETUP_COMPLETE_FLAG" ]
}

is_deploy_complete() {
    [ -f "$DEPLOY_COMPLETE_FLAG" ]
}

# Check overall system state
check_system_state() {
    log_info "Checking system state..."

    echo "Setup Status:"
    if is_setup_complete; then
        echo "  ✓ System setup completed"
    else
        echo "  ✗ System setup not completed"
    fi

    echo "Deployment Status:"
    if is_deploy_complete; then
        echo "  ✓ Deployment completed"
    else
        echo "  ✗ Deployment not completed"
    fi

    echo "Services Status:"
    if [ -f "$ENV_FILE" ]; then
        cd "$PROJECT_DIR/02-docker-configuration" 2>/dev/null || true
        local running_services=$(docker compose -f docker-compose.onprem.yml ps --services --filter "status=running" 2>/dev/null | wc -l)
        local total_services=$(docker compose -f docker-compose.onprem.yml config --services 2>/dev/null | wc -l)
        echo "  Running services: $running_services/$total_services"
    else
        echo "  Environment not configured"
    fi

    echo "Docker Status:"
    if docker ps >/dev/null 2>&1; then
        echo "  ✓ Docker is accessible"
    else
        echo "  ✗ Docker is not accessible"
    fi

    echo "Storage Status:"
    # Load environment for storage paths
    load_environment >/dev/null 2>&1 || true
    local HDD_MOUNT="${STORAGE_HDD_PATH:-/mnt/hdd}"
    local NAS_MOUNT="${NAS_BACKUP_PATH:-/mnt/nas}"

    local storage_ok=true
    if [ -d "$HDD_MOUNT" ]; then
        echo "  ✓ HDD mount available at $HDD_MOUNT"
    else
        echo "  ✗ HDD mount not available at $HDD_MOUNT"
        storage_ok=false
    fi

    if [ -d "$NAS_MOUNT" ]; then
        echo "  ✓ NAS mount available at $NAS_MOUNT"
    else
        echo "  ⚠ NAS mount not available at $NAS_MOUNT (optional)"
    fi

    if [ "$storage_ok" = true ]; then
        echo "  ✓ Required storage mounts available"
    else
        echo "  ✗ Required storage mounts not available"
    fi
}

# Reset deployment state
reset_state() {
    log_info "Resetting deployment state..."

    if [ -f "$SETUP_COMPLETE_FLAG" ] || [ -f "$DEPLOY_COMPLETE_FLAG" ]; then
        read -p "This will reset the deployment state. Are you sure? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f "$SETUP_COMPLETE_FLAG" "$DEPLOY_COMPLETE_FLAG"
            log_success "Deployment state reset"
        else
            log_info "State reset cancelled"
        fi
    else
        log_info "No state to reset"
    fi
}

# Validate deployment environment
validate_environment() {
    log_info "Validating deployment environment: $DEPLOY_ENV"

    # Check if environment is valid
    local valid=false
    for env in "${VALID_ENVIRONMENTS[@]}"; do
        if [ "$env" = "$DEPLOY_ENV" ]; then
            valid=true
            break
        fi
    done

    if [ "$valid" = false ]; then
        log_error "Invalid deployment environment: $DEPLOY_ENV"
        log_info "Valid environments: ${VALID_ENVIRONMENTS[*]}"
        exit 1
    fi

    # Check if environment files exist
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file not found: $ENV_FILE"
        log_info "Please create the environment file for $DEPLOY_ENV environment"

        # Suggest creating from template
        local template_file="$PROJECT_DIR/02-docker-configuration/.env.hdd-only.example"
        if [ -f "$template_file" ]; then
            log_info "You can copy from HDD-only template: cp $template_file $ENV_FILE"
        else
            local fallback_template="$PROJECT_DIR/02-docker-configuration/.env.example"
            if [ -f "$fallback_template" ]; then
                log_info "You can copy from template: cp $fallback_template $ENV_FILE"
            fi
        fi
        exit 1
    fi

    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Docker Compose file not found: $COMPOSE_FILE"
        log_info "Please create the compose file for $DEPLOY_ENV environment"
        exit 1
    fi

    log_success "Environment validation passed for: $DEPLOY_ENV"
    log_info "Using environment file: $ENV_FILE"
    log_info "Using compose file: $COMPOSE_FILE"
}

# Get environment-specific Docker image tags
get_image_tag() {
    local service="$1"
    case "$DEPLOY_ENV" in
        "dev")
            echo "${service}:dev-latest"
            ;;
        "staging")
            echo "${service}:staging-latest"
            ;;
        "prod")
            echo "${service}:latest"
            ;;
        "test")
            echo "${service}:test-latest"
            ;;
        *)
            echo "${service}:latest"
            ;;
    esac
}

# Get environment-specific Dockerfile
get_dockerfile() {
    local service="$1"
    case "$DEPLOY_ENV" in
        "dev")
            if [ -f "$REPO_BASE_DIR/$service/Dockerfile.dev" ]; then
                echo "Dockerfile.dev"
            else
                echo "Dockerfile"
            fi
            ;;
        "staging")
            if [ -f "$REPO_BASE_DIR/$service/Dockerfile.staging" ]; then
                echo "Dockerfile.staging"
            else
                echo "Dockerfile"
            fi
            ;;
        "prod")
            if [ -f "$REPO_BASE_DIR/$service/Dockerfile.prod" ]; then
                echo "Dockerfile.prod"
            else
                echo "Dockerfile"
            fi
            ;;
        "test")
            if [ -f "$REPO_BASE_DIR/$service/Dockerfile.test" ]; then
                echo "Dockerfile.test"
            else
                echo "Dockerfile"
            fi
            ;;
        *)
            echo "Dockerfile"
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for $DEPLOY_ENV environment..."

    # Validate environment first
    validate_environment

    # Check if running as non-root
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi

    # Check Ubuntu version
    if ! grep -q "Ubuntu 24.04" /etc/os-release 2>/dev/null; then
        log_warning "This script is optimized for Ubuntu 24.04 LTS"
    fi

    # Check available RAM
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 15 ]; then
        log_error "Insufficient RAM. Required: 16GB, Available: ${TOTAL_RAM}GB"
        exit 1
    fi

    # Check storage mounts using environment variables
    load_environment
    local HDD_MOUNT="${STORAGE_HDD_PATH:-/mnt/hdd}"
    local NAS_MOUNT="${NAS_BACKUP_PATH:-/mnt/nas}"

    if [ ! -d "$HDD_MOUNT" ]; then
        log_error "HDD mount point $HDD_MOUNT not found"
        log_info "Please ensure HDD storage is mounted at $HDD_MOUNT"
        exit 1
    fi

    # NAS mount is optional for backup functionality
    if [ ! -d "$NAS_MOUNT" ]; then
        log_warning "NAS mount point $NAS_MOUNT not found (optional for backups)"
    fi

    # Check network connectivity
    # if ! ping -c 1 192.168.1.1 >/dev/null 2>&1; then
    #     log_warning "Cannot reach internal gateway 192.168.1.1"
    # fi

    log_success "Prerequisites check passed"
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."

    # Check if packages are already installed
    local packages_to_install=()
    local all_packages=(docker.io docker-compose-v2 curl wget git htop iotop nethogs tree unzip apache2-utils certbot ufw)

    for package in "${all_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            packages_to_install+=("$package")
        fi
    done

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_info "Installing missing packages: ${packages_to_install[*]}"
        sudo apt update
        sudo apt install -y "${packages_to_install[@]}"
    else
        log_info "All required packages are already installed"
    fi

    # Add user to docker group (idempotent)
    if ! groups $USER | grep -q docker; then
        log_info "Adding user $USER to docker group..."
        sudo usermod -aG docker $USER
        log_success "User added to docker group"
    else
        log_info "User $USER is already in docker group"
    fi

    # Enable and start Docker (idempotent)
    if ! systemctl is-enabled docker >/dev/null 2>&1; then
        log_info "Enabling Docker service..."
        sudo systemctl enable docker
    else
        log_info "Docker service is already enabled"
    fi

    if ! systemctl is-active docker >/dev/null 2>&1; then
        log_info "Starting Docker service..."
        sudo systemctl start docker
    else
        log_info "Docker service is already running"
    fi

    # Apply docker group membership for current session
    log_info "Checking docker group membership..."
    if ! groups | grep -q docker; then
        log_warning "Docker group membership not active in current session"
        log_info "You may need to log out and log in, or the script will handle this automatically"
    else
        log_info "Docker group membership is active in current session"
    fi

    # Install Docker buildx
    log_info "Installing Docker buildx..."
    install_buildx

    log_success "Dependencies installed"
    log_info "Note: If you see permission errors, you may need to log out and log in to apply docker group membership"
}

# Install or fix Docker buildx
install_buildx() {
    log_info "Installing/fixing Docker buildx..."

    # Check if buildx is already available
    if docker buildx version >/dev/null 2>&1; then
        log_success "Docker buildx is already available"
        return 0
    fi

    # Method 1: Try to install from official Docker repository
    log_info "Adding Docker official repository..."

    # Install prerequisites (idempotent)
    local prereq_packages=(ca-certificates curl gnupg lsb-release)
    local missing_prereqs=()

    for package in "${prereq_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            missing_prereqs+=("$package")
        fi
    done

    if [ ${#missing_prereqs[@]} -gt 0 ]; then
        log_info "Installing missing prerequisites: ${missing_prereqs[*]}"
        sudo apt update
        sudo apt install -y "${missing_prereqs[@]}"
    else
        log_info "All prerequisites are already installed"
    fi

    # Add Docker's official GPG key (idempotent)
    sudo mkdir -p /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        log_info "Adding Docker GPG key..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    else
        log_info "Docker GPG key already exists"
    fi

    # Add Docker repository (idempotent)
    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
        log_info "Adding Docker repository..."
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
    else
        log_info "Docker repository already configured"
    fi

    # Try to install buildx plugin
    if ! dpkg -l | grep -q "^ii  docker-buildx-plugin "; then
        log_info "Installing docker-buildx-plugin..."
        if sudo apt install -y docker-buildx-plugin; then
            log_info "Installed docker-buildx-plugin from Docker repository"
        else
            log_warning "Failed to install from Docker repository, trying manual installation..."

            # Method 2: Manual installation
            log_info "Downloading buildx binary manually..."
            BUILDX_VERSION=$(curl -s https://api.github.com/repos/docker/buildx/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
            ARCH=$(uname -m)
            case $ARCH in
                x86_64) ARCH="amd64" ;;
                aarch64) ARCH="arm64" ;;
                armv7l) ARCH="arm-v7" ;;
            esac

            # Create buildx plugin directory
            mkdir -p ~/.docker/cli-plugins

            # Download and install buildx (only if not already present)
            if [ ! -f ~/.docker/cli-plugins/docker-buildx ]; then
                curl -L "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-${ARCH}" -o ~/.docker/cli-plugins/docker-buildx
                chmod +x ~/.docker/cli-plugins/docker-buildx
            else
                log_info "Buildx binary already exists"
            fi
        fi
    else
        log_info "docker-buildx-plugin is already installed"
    fi

    # Restart Docker service only if needed
    if ! docker buildx version >/dev/null 2>&1; then
        log_info "Restarting Docker service..."
        sudo systemctl restart docker
        # Wait a moment for Docker to restart
        sleep 5
    fi

    # Verify buildx is now available
    if docker buildx version >/dev/null 2>&1; then
        log_success "Docker buildx installed successfully"
        # Remove the disable flag if it exists
        rm -f /tmp/disable_buildkit
    else
        log_error "Failed to install Docker buildx"
        log_warning "BuildKit will be disabled for builds"
        touch /tmp/disable_buildkit
    fi
}

# Setup storage directories
setup_storage() {
    log_info "Setting up storage directories..."

    # Load environment variables for storage paths
    load_environment

    # Get storage mount paths from environment (with defaults)
    local HDD_MOUNT="${STORAGE_HDD_PATH:-/mnt/hdd}"
    local NAS_MOUNT="${NAS_BACKUP_PATH:-/mnt/nas}"

    log_info "Using simplified HDD-only storage paths:"
    log_info "  HDD Mount: $HDD_MOUNT"
    log_info "  NAS Mount: $NAS_MOUNT"

    # Define directory arrays for HDD-only configuration
    # All data stored on HDD for simplicity
    local hdd_dirs=(
        "postgresql-data"     # Main PostgreSQL data
        "postgres-wal-archive" # PostgreSQL WAL archives
        "postgres-backups"   # PostgreSQL backup files
        "redis-data"         # Redis data
        "redis-backups"      # Redis backup files
        "uploads"            # Application uploads
        "logs"               # Application logs
        "app-logs-archive"   # Application log archives
        "worker-logs-archive" # Worker log archives
        "nginx-cache"        # Nginx cache
        "prometheus-data"    # Prometheus metrics
        "prometheus-archive" # Prometheus data archives
        "grafana-data"       # Grafana dashboards
        "portainer-data"     # Portainer configuration
        "backups"           # General backups
        "archives"          # General archives
    )

    # NAS Paths (Off-site Backup) - from .env NAS_*_PATH variables
    local nas_dirs=(
        "prs-backups"        # PRS system backups (NAS_BACKUP_PATH)
        "prs-archives"       # PRS system archives (NAS_ARCHIVE_PATH)
    )

    # Create HDD directories (idempotent)
    local hdd_created=false
    for dir in "${hdd_dirs[@]}"; do
        if [ ! -d "$HDD_MOUNT/$dir" ]; then
            sudo mkdir -p "$HDD_MOUNT/$dir"
            hdd_created=true
        fi
    done

    if [ "$hdd_created" = true ]; then
        log_info "Created missing HDD directories in $HDD_MOUNT"
    else
        log_info "All HDD directories already exist in $HDD_MOUNT"
    fi

    # Create NAS directories if NAS mount exists (idempotent)
    if [ -d "$(dirname "$NAS_MOUNT")" ]; then
        local nas_created=false
        for dir in "${nas_dirs[@]}"; do
            if [ ! -d "$NAS_MOUNT/$dir" ]; then
                sudo mkdir -p "$NAS_MOUNT/$dir"
                nas_created=true
            fi
        done

        if [ "$nas_created" = true ]; then
            log_info "Created missing NAS directories in $NAS_MOUNT"
        else
            log_info "All NAS directories already exist in $NAS_MOUNT"
        fi
    else
        log_warning "NAS mount point $NAS_MOUNT not available, skipping NAS directory creation"
    fi

    # Set ownership (idempotent - only change if needed)
    local ownership_changed=false
    if [ -d "$HDD_MOUNT" ]; then
        current_owner=$(stat -c '%U:%G' "$HDD_MOUNT")
        if [ "$current_owner" != "$USER:$USER" ]; then
            sudo chown -R $USER:$USER "$HDD_MOUNT"
            ownership_changed=true
        fi
    fi

    # Set ownership for NAS if it exists
    if [ -d "$NAS_MOUNT" ]; then
        current_owner=$(stat -c '%U:%G' "$NAS_MOUNT")
        if [ "$current_owner" != "$USER:$USER" ]; then
            sudo chown -R $USER:$USER "$NAS_MOUNT"
            ownership_changed=true
        fi
    fi

    if [ "$ownership_changed" = true ]; then
        log_info "Updated directory ownership"
    else
        log_info "Directory ownership is already correct"
    fi

    # Set permissions (idempotent)
    chmod -R 755 "$HDD_MOUNT" 2>/dev/null || true
    if [ -d "$NAS_MOUNT" ]; then
        chmod -R 755 "$NAS_MOUNT" 2>/dev/null || true
    fi

    log_success "Storage directories setup completed"
}


# Configure firewall
configure_firewall() {
    log_info "Configuring firewall..."

    # Check if UFW is already configured with our rules
    local needs_config=false

    # Check if UFW is enabled
    if ! sudo ufw status | grep -q "Status: active"; then
        needs_config=true
        log_info "UFW is not active, will configure"
    else
        # Check if our specific rules exist with correct UFW output format
        local required_rules=(
            "80.*ALLOW.*192.168.0.0/20.*HTTP"
            "443.*ALLOW.*192.168.0.0/20.*HTTPS"
            "8080.*ALLOW.*192.168.0.0/20.*Adminer"
            "3001.*ALLOW.*192.168.0.0/20.*Grafana"
            "9000.*ALLOW.*192.168.0.0/20.*Portainer"
            "9090.*ALLOW.*192.168.0.0/20.*Prometheus"
        )

        local ufw_status=$(sudo ufw status)
        local missing_rules=()

        for rule in "${required_rules[@]}"; do
            if ! echo "$ufw_status" | grep -q "$rule"; then
                missing_rules+=("$rule")
            fi
        done

        if [ ${#missing_rules[@]} -gt 0 ]; then
            needs_config=true
            log_info "Missing firewall rules detected: ${#missing_rules[@]} out of ${#required_rules[@]}"
            log_info "Will reconfigure firewall to ensure all rules are present"
        else
            log_info "All required firewall rules are present"
            return 0
        fi
    fi

    # Configure firewall if needed
    if [ "$needs_config" = true ]; then
        # Check if this is a fresh UFW installation or if we need to do a full reset
        local ufw_status=$(sudo ufw status)
        local is_fresh_install=false

        if ! echo "$ufw_status" | grep -q "Status: active"; then
            is_fresh_install=true
            log_info "UFW is not active, performing initial configuration..."
        else
            log_info "UFW is active, adding missing rules without reset..."
        fi

        # Only do full reset for fresh installations
        if [ "$is_fresh_install" = true ]; then
            log_info "Performing initial firewall setup..."
            sudo ufw --force reset
            sudo ufw default deny incoming
            sudo ufw default allow outgoing

            # Enable firewall first
            sudo ufw --force enable
        fi

        # Add rules individually (idempotent - UFW won't duplicate existing rules)
        log_info "Ensuring required firewall rules are present..."

        # Check and add each rule individually
        if ! echo "$ufw_status" | grep -q "80.*ALLOW.*192.168.0.0/20.*HTTP"; then
            log_info "Adding HTTP rule..."
            sudo ufw allow from 192.168.0.0/20 to any port 80 comment "HTTP"
        fi

        if ! echo "$ufw_status" | grep -q "443.*ALLOW.*192.168.0.0/20.*HTTPS"; then
            log_info "Adding HTTPS rule..."
            sudo ufw allow from 192.168.0.0/20 to any port 443 comment "HTTPS"
        fi

        if ! echo "$ufw_status" | grep -q "8080.*ALLOW.*192.168.0.0/20.*Adminer"; then
            log_info "Adding Adminer rule..."
            sudo ufw allow from 192.168.0.0/20 to any port 8080 comment "Adminer"
        fi

        if ! echo "$ufw_status" | grep -q "3001.*ALLOW.*192.168.0.0/20.*Grafana"; then
            log_info "Adding Grafana rule..."
            sudo ufw allow from 192.168.0.0/20 to any port 3001 comment "Grafana"
        fi

        if ! echo "$ufw_status" | grep -q "9000.*ALLOW.*192.168.0.0/20.*Portainer"; then
            log_info "Adding Portainer rule..."
            sudo ufw allow from 192.168.0.0/20 to any port 9000 comment "Portainer"
        fi

        if ! echo "$ufw_status" | grep -q "9090.*ALLOW.*192.168.0.0/20.*Prometheus"; then
            log_info "Adding Prometheus rule..."
            sudo ufw allow from 192.168.0.0/20 to any port 9090 comment "Prometheus"
        fi

        # Add rate limiting rules if not present (only for fresh installs or if missing)
        if [ "$is_fresh_install" = true ] || ! echo "$ufw_status" | grep -q "80/tcp.*LIMIT"; then
            log_info "Adding HTTP rate limiting..."
            sudo ufw limit 80/tcp
        fi

        if [ "$is_fresh_install" = true ] || ! echo "$ufw_status" | grep -q "443/tcp.*LIMIT"; then
            log_info "Adding HTTPS rate limiting..."
            sudo ufw limit 443/tcp
        fi

        # Ensure SSH is allowed (idempotent)
        if [ "$is_fresh_install" = true ] || ! echo "$ufw_status" | grep -q "22/tcp.*ALLOW"; then
            log_info "Ensuring SSH access..."
            sudo ufw allow ssh
        fi

        # Ensure UFW is enabled
        if ! sudo ufw status | grep -q "Status: active"; then
            sudo ufw --force enable
        fi

        log_success "Firewall configuration completed"
    fi
}

# Setup SSL certificates
setup_ssl() {
    log_info "Setting up SSL certificates..."

    # Create SSL directory
    mkdir -p "$PROJECT_DIR/02-docker-configuration/ssl"

    SSL_DIR="$PROJECT_DIR/02-docker-configuration/ssl"

    # Check if certificates already exist and are valid
    local need_generation=true
    if [ -f "$SSL_DIR/server.crt" ] && [ -f "$SSL_DIR/server.key" ]; then
        # Check if certificate is still valid (not expired)
        if openssl x509 -checkend 86400 -noout -in "$SSL_DIR/server.crt" >/dev/null 2>&1; then
            log_info "SSL certificates already exist and are valid, skipping generation"
            need_generation=false
        else
            log_warning "SSL certificate has expired, regenerating..."
        fi
    fi

    # Generate self-signed certificate for initial setup (only if needed)
    if [ "$need_generation" = true ]; then
        log_info "Generating new SSL certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$SSL_DIR/server.key" \
            -out "$SSL_DIR/server.crt" \
            -subj "/C=PH/ST=Metro Manila/L=Manila/O=Client Organization/CN=prs.client-domain.com"
    fi

    # Generate DH parameters if they don't exist
    if [ ! -f "$SSL_DIR/dhparam.pem" ]; then
        log_info "Generating DH parameters..."
        openssl dhparam -out "$SSL_DIR/dhparam.pem" 2048
    else
        log_info "DH parameters already exist, skipping generation"
    fi

    # Set proper permissions and ownership for PostgreSQL container
    log_info "Setting SSL file permissions and ownership for PostgreSQL container..."

    # TimescaleDB container runs postgres user as UID 70, not 999
    # We need to set ownership to UID 70 so the container can read the SSL key

    # Set ownership to postgres user (UID 70) for TimescaleDB container compatibility
    if sudo chown 70:70 "$SSL_DIR/server.key" "$SSL_DIR/server.crt" "$SSL_DIR/dhparam.pem" 2>/dev/null; then
        log_info "Set SSL files ownership to postgres user (UID 70)"
    else
        log_warning "Failed to set ownership to UID 70, trying alternative approach"
        # Fallback: make files world-readable for container access
        sudo chmod 644 "$SSL_DIR/server.key"
        sudo chmod 644 "$SSL_DIR/server.crt"
        sudo chmod 644 "$SSL_DIR/dhparam.pem"
    fi

    # Set proper permissions for PostgreSQL container
    sudo chmod 600 "$SSL_DIR/server.key" 2>/dev/null || sudo chmod 644 "$SSL_DIR/server.key"
    sudo chmod 644 "$SSL_DIR/server.crt"
    sudo chmod 644 "$SSL_DIR/dhparam.pem"

    # Ensure SSL directory has proper permissions
    sudo chmod 755 "$SSL_DIR"

    log_info "SSL file ownership and permissions set for PostgreSQL container"

    # Create Grafana configuration file if it doesn't exist
    GRAFANA_CONFIG="$PROJECT_DIR/02-docker-configuration/config/grafana/grafana.ini"
    if [ ! -f "$GRAFANA_CONFIG" ]; then
        log_info "Creating Grafana configuration file..."
        mkdir -p "$(dirname "$GRAFANA_CONFIG")"
        tee "$GRAFANA_CONFIG" > /dev/null << 'EOF'
[server]
http_port = 3000
domain = localhost
root_url = %(protocol)s://%(domain)s:%(http_port)s/

[database]
type = postgres
host = postgres:5432
name = prs_production
user = prs_user
password = ${GF_DATABASE_PASSWORD}
ssl_mode = disable

[security]
admin_user = admin
admin_password = ${GF_SECURITY_ADMIN_PASSWORD}
secret_key = ${GF_SECURITY_SECRET_KEY}

[users]
allow_sign_up = false
allow_org_create = false
auto_assign_org = true
auto_assign_org_role = Viewer

[auth.anonymous]
enabled = false

[log]
mode = console
level = info

[paths]
data = /var/lib/grafana
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins
provisioning = /etc/grafana/provisioning
EOF
        log_info "Grafana configuration file created"
    fi

    log_success "SSL certificates setup completed"
}

# Setup monitoring prerequisites
setup_monitoring_prerequisites() {
    log_info "Setting up monitoring prerequisites..."

    # Check if database container is running
    if ! docker ps | grep -q "prs-onprem-postgres-timescale"; then
        log_warning "PostgreSQL container is not running. Monitoring setup may fail."
        return 0
    fi

    # Wait for database to be ready
    timeout 30 bash -c 'until docker exec prs-onprem-postgres-timescale pg_isready -U prs_user >/dev/null 2>&1; do sleep 2; done' || {
        log_warning "Database not ready, skipping Grafana database setup"
        return 0
    }

    # Create Grafana database if it doesn't exist (required for Grafana to start)
    log_info "Ensuring Grafana database exists..."
    local grafana_db_exists=$(docker exec prs-onprem-postgres-timescale bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -t -c \"SELECT 1 FROM pg_database WHERE datname='grafana';\"" 2>/dev/null | tr -d ' ' || echo "")

    if [ -z "$grafana_db_exists" ]; then
        log_info "Creating Grafana database..."
        if docker exec prs-onprem-postgres-timescale bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U \$POSTGRES_USER -d \$POSTGRES_DB -c 'CREATE DATABASE grafana;'" >/dev/null 2>&1; then
            log_success "Grafana database created successfully"
        else
            log_warning "Failed to create Grafana database - Grafana may not start properly"
        fi
    else
        log_info "Grafana database already exists"
    fi

    log_success "Monitoring prerequisites setup completed"
}

# Function to reset database if password mismatch
reset_database() {
    log_info "Resetting database due to password mismatch..."

    # Stop database container
    cd "$PROJECT_DIR/02-docker-configuration"
    docker compose -f docker-compose.onprem.yml down postgres

    # Remove database volume
    docker volume rm 02-docker-configuration_database_data 2>/dev/null || true

    # Clean any potential data directories using environment paths
    local HDD_MOUNT="${STORAGE_HDD_PATH:-/mnt/hdd}"

    sudo rm -rf "$HDD_MOUNT/postgresql-data"/* 2>/dev/null || true

    # Start database container fresh
    docker compose -f docker-compose.onprem.yml up -d postgres

    log_success "Database reset completed"
}

# Function to ensure database is properly initialized
ensure_database_initialized() {
    log_info "Ensuring database is properly initialized..."

    # Stop database container if running
    cd "$PROJECT_DIR/02-docker-configuration"
    docker compose -f docker-compose.onprem.yml down postgres 2>/dev/null || true

    # Clear any existing PostgreSQL data to force fresh initialization
    local HDD_MOUNT="${STORAGE_HDD_PATH:-/mnt/hdd}"
    sudo rm -rf "$HDD_MOUNT/postgresql-data"/* 2>/dev/null || true

    # Remove Docker volume
    docker volume rm 02-docker-configuration_database_data 2>/dev/null || true

    log_success "Database initialization ensured"
}

# Fix Docker permission issues
fix_docker_permissions() {
    log_info "Fixing Docker permission issues..."

    # Check if user is already in docker group
    if groups | grep -q docker; then
        log_info "User is already in docker group"

        # Check if docker works
        if docker ps >/dev/null 2>&1; then
            log_success "Docker permissions are working correctly"
            return 0
        else
            log_warning "User is in docker group but permissions not active in current session"
            log_info "Please run one of the following:"
            echo "  1. Log out and log in again"
            echo "  2. Run: newgrp docker"
            echo "  3. Run: exec su -l \$USER"
            return 1
        fi
    else
        log_info "Adding user to docker group..."
        sudo usermod -aG docker $USER

        log_success "User added to docker group"
        log_warning "You need to log out and log in for changes to take effect"
        log_info "Or run: newgrp docker"
        return 1
    fi
}

# Load environment variables
load_environment() {
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file not found: $ENV_FILE"
        log_info "Please copy .env.hdd-only.example to .env and configure it"
        exit 1
    fi

    # Source environment file
    set -a
    source "$ENV_FILE"
    set +a

    log_info "Environment loaded from $ENV_FILE"

    # Verify repository configuration
    if [ -n "${BACKEND_REPO_URL:-}" ] && [ -n "${FRONTEND_REPO_URL:-}" ]; then
        log_info "Repository configuration:"
        log_info "  Backend: $BACKEND_REPO_URL (branch: ${BACKEND_BRANCH:-main})"
        log_info "  Frontend: $FRONTEND_REPO_URL (branch: ${FRONTEND_BRANCH:-main})"
        log_info "  Base directory: ${REPO_BASE_DIR:-/opt/prs}"
    else
        log_warning "Repository URLs not configured in environment file"
        log_info "Using default repository URLs"
    fi
}

# Clone repositories
clone_repositories() {
    log_info "Cloning application repositories..."
    log_info "Backend repo: $BACKEND_REPO_URL (branch: $BACKEND_BRANCH)"
    log_info "Frontend repo: $FRONTEND_REPO_URL (branch: $FRONTEND_BRANCH)"

    # Validate repository URLs
    if [[ "$BACKEND_REPO_URL" == *"your-org"* ]] || [[ "$FRONTEND_REPO_URL" == *"your-org"* ]]; then
        log_error "Repository URLs contain placeholder values (your-org)"
        log_error "Please update BACKEND_REPO_URL and FRONTEND_REPO_URL in $ENV_FILE"
        log_info "Example: BACKEND_REPO_URL=https://github.com/yourusername/prs-backend-a.git"
        exit 1
    fi

    # Create repositories directory
    sudo mkdir -p "$REPO_BASE_DIR"
    sudo chown $USER:$USER "$REPO_BASE_DIR"

    # Extract repository names from URLs
    BACKEND_DIR_NAME=$(basename "$BACKEND_REPO_URL" .git)
    FRONTEND_DIR_NAME=$(basename "$FRONTEND_REPO_URL" .git)

    # Clone backend repository
    if [ ! -d "$REPO_BASE_DIR/$BACKEND_DIR_NAME" ]; then
        log_info "Cloning backend repository..."
        if git clone -b "$BACKEND_BRANCH" "$BACKEND_REPO_URL" "$REPO_BASE_DIR/$BACKEND_DIR_NAME"; then
            log_success "Backend repository cloned"
        else
            log_error "Failed to clone backend repository"
            exit 1
        fi
    else
        log_info "Backend repository already exists, updating..."
        cd "$REPO_BASE_DIR/$BACKEND_DIR_NAME"

        # Check if we're on the right branch and remote
        current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        if [ "$current_branch" != "$BACKEND_BRANCH" ]; then
            log_info "Switching to branch $BACKEND_BRANCH"
            git fetch origin
            git checkout "$BACKEND_BRANCH" || git checkout -b "$BACKEND_BRANCH" "origin/$BACKEND_BRANCH"
        fi

        # Update the repository
        if git pull origin "$BACKEND_BRANCH"; then
            log_success "Backend repository updated"
        else
            log_warning "Failed to update backend repository, continuing with existing version"
        fi
    fi

    # Clone frontend repository
    if [ ! -d "$REPO_BASE_DIR/$FRONTEND_DIR_NAME" ]; then
        log_info "Cloning frontend repository..."
        if git clone -b "$FRONTEND_BRANCH" "$FRONTEND_REPO_URL" "$REPO_BASE_DIR/$FRONTEND_DIR_NAME"; then
            log_success "Frontend repository cloned"
        else
            log_error "Failed to clone frontend repository"
            exit 1
        fi
    else
        log_info "Frontend repository already exists, updating..."
        cd "$REPO_BASE_DIR/$FRONTEND_DIR_NAME"

        # Check if we're on the right branch and remote
        current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        if [ "$current_branch" != "$FRONTEND_BRANCH" ]; then
            log_info "Switching to branch $FRONTEND_BRANCH"
            git fetch origin
            git checkout "$FRONTEND_BRANCH" || git checkout -b "$FRONTEND_BRANCH" "origin/$FRONTEND_BRANCH"
        fi

        # Update the repository
        if git pull origin "$FRONTEND_BRANCH"; then
            log_success "Frontend repository updated"
        else
            log_warning "Failed to update frontend repository, continuing with existing version"
        fi
    fi

    # Configure dynamic frontend host detection after cloning
    configure_dynamic_frontend_deployment
}

# Configure dynamic frontend host detection for deployment
configure_dynamic_frontend_deployment() {
    log_info "Configuring dynamic frontend host detection..."

    local frontend_config_file="$REPO_BASE_DIR/$FRONTEND_DIR_NAME/src/config/env.js"

    # Check if frontend repository exists
    if [ ! -f "$frontend_config_file" ]; then
        log_warning "Frontend configuration file not found at $frontend_config_file"
        log_info "Skipping dynamic host detection configuration"
        return
    fi

    # Check if dynamic configuration is already implemented
    if grep -q "getApiUrl" "$frontend_config_file"; then
        log_info "Dynamic frontend host detection already configured"
        return
    fi

    log_info "Updating frontend configuration for dynamic host detection..."

    # Create backup
    cp "$frontend_config_file" "$frontend_config_file.backup"

    # Apply dynamic configuration
    cat > "$frontend_config_file" << 'EOF'
import * as z from 'zod';

const createEnv = () => {
  const EnvSchema = z.object({
    API_URL: z.string().default('http://localhost:4000'),
    UPLOAD_URL: z.string().default('http://localhost:4000/upload'),
    ENABLE_API_MOCKING: z
      .string()
      .refine(s => s === 'true' || s === 'false')
      .transform(s => s === 'true')
      .optional(),
  });

  const envVars = Object.entries(import.meta.env).reduce((acc, curr) => {
    const [key, value] = curr;
    if (key.startsWith('VITE_APP_')) {
      acc[key.replace('VITE_APP_', '')] = value;
    }
    return acc;
  }, {});

  // Dynamically determine API URL based on current host
  const getApiUrl = () => {
    // If we have a build-time API URL, use it (for development/localhost)
    if (envVars.API_URL && (envVars.API_URL.includes('localhost') || envVars.API_URL.includes('127.0.0.1'))) {
      return envVars.API_URL;
    }

    // For production, use the current host with HTTPS
    if (typeof window !== 'undefined') {
      const protocol = window.location.protocol;
      const host = window.location.host;
      return `${protocol}//${host}/api`;
    }

    // Fallback to build-time URL if window is not available (SSR)
    return envVars.API_URL || 'http://localhost:4000';
  };

  const apiUrl = getApiUrl();

  const mutatedEnvVars = {
    ...envVars,
    API_URL: apiUrl,
    UPLOAD_URL: `${apiUrl}/upload`,
  };

  const parsedEnv = EnvSchema.safeParse(mutatedEnvVars);

  if (!parsedEnv.success) {
    throw new Error(
      `Invalid env provided.
The following variables are missing or invalid:
${Object.entries(parsedEnv.error.flatten().fieldErrors)
  .map(([k, v]) => `- ${k}: ${v}`)
  .join('\n')}
`,
    );
  }

  return parsedEnv.data;
};

export const env = createEnv();
EOF

    log_success "Dynamic frontend host detection configured"
    log_info "Frontend will automatically detect API URLs based on current host (IP or domain)"
}

# Check docker permissions
check_docker_permissions() {
    if docker ps >/dev/null 2>&1; then
        return 0
    else
        log_warning "Docker permission denied. Checking if user is in docker group..."
        if groups | grep -q docker; then
            log_info "User is in docker group but session needs refresh"
            return 1
        else
            log_error "User is not in docker group. Please run 'sudo usermod -aG docker $USER' and log out/in"
            return 2
        fi
    fi
}

# Build Docker images
build_images() {
    log_info "Building Docker images..."
    log_info "Detected architecture: $(uname -m) -> Docker platform: $DOCKER_PLATFORM"

    # Check docker permissions first
    if ! check_docker_permissions; then
        log_error "Docker permission issues detected"
        log_info "Trying to use newgrp to apply docker group membership..."

        # Try to use newgrp to apply docker group membership
        if groups | grep -q docker; then
            log_info "User is in docker group, but session needs refresh"
            log_info "Please run: newgrp docker"
            log_info "Or log out and log in to apply group membership"
            log_info "Alternatively, the script will try to continue with sudo for docker commands"

            # Set a flag to use sudo for docker commands
            export USE_SUDO_DOCKER=1
        else
            log_error "User not in docker group. Please run the setup command first."
            exit 1
        fi
    fi

    # Check if buildx is available or if we have a flag to disable BuildKit
    if [ -f /tmp/disable_buildkit ] || ! docker buildx version >/dev/null 2>&1; then
        log_warning "Docker buildx not available, disabling BuildKit for this session"
        export DOCKER_BUILDKIT=0
        export COMPOSE_DOCKER_CLI_BUILD=0
    else
        log_info "Using Docker BuildKit for optimized builds"
        export DOCKER_BUILDKIT=1
        export COMPOSE_DOCKER_CLI_BUILD=1
    fi

    # Extract repository names from URLs
    BACKEND_DIR_NAME=$(basename "$BACKEND_REPO_URL" .git)
    FRONTEND_DIR_NAME=$(basename "$FRONTEND_REPO_URL" .git)

    # Verify repositories exist
    if [ ! -d "$REPO_BASE_DIR/$BACKEND_DIR_NAME" ]; then
        log_error "Backend repository not found at $REPO_BASE_DIR/$BACKEND_DIR_NAME"
        log_info "Please run 'clone_repositories' first or use the 'deploy' command"
        exit 1
    fi

    if [ ! -d "$REPO_BASE_DIR/$FRONTEND_DIR_NAME" ]; then
        log_error "Frontend repository not found at $REPO_BASE_DIR/$FRONTEND_DIR_NAME"
        log_info "Please run 'clone_repositories' first or use the 'deploy' command"
        exit 1
    fi

    # Determine docker command prefix
    DOCKER_CMD="docker"
    if [ "$USE_SUDO_DOCKER" = "1" ]; then
        DOCKER_CMD="sudo docker"
        log_info "Using sudo for docker commands due to permission issues"
    fi

    # Check if images already exist
    local backend_exists=$($DOCKER_CMD images -q prs-backend:latest 2>/dev/null)
    local frontend_exists=$($DOCKER_CMD images -q prs-frontend:latest 2>/dev/null)

    # Build backend image (only if it doesn't exist or force rebuild)
    if [ -z "$backend_exists" ] || [ "${FORCE_REBUILD:-false}" = "true" ]; then
        log_info "Building backend image from $REPO_BASE_DIR/$BACKEND_DIR_NAME..."

        # Determine which Dockerfile to use
        local dockerfile_path
        if [ "${USE_FALLBACK_DOCKERFILE:-false}" = "true" ]; then
            dockerfile_path="Dockerfile.fallback"
            log_info "Using fallback Dockerfile (Debian-based) due to Alpine repository issues"
        else
            # Get environment-specific Dockerfile
            dockerfile_path=$(get_dockerfile "$BACKEND_DIR_NAME")
            log_info "Using environment-specific Dockerfile: $dockerfile_path for $DEPLOY_ENV"
        fi

        # Try building with retry logic for network issues
        local build_attempts=0
        local max_attempts=3
        while [ $build_attempts -lt $max_attempts ]; do
            build_attempts=$((build_attempts + 1))
            log_info "Backend build attempt $build_attempts/$max_attempts using $dockerfile_path..."

            # Get environment-specific image tag
            local backend_tag=$(get_image_tag "prs-backend")

            # echo $DOCKER_CMD build --no-cache --platform $DOCKER_PLATFORM -f "$REPO_BASE_DIR/$BACKEND_DIR_NAME/$dockerfile_path" -t "$backend_tag" "$REPO_BASE_DIR/$BACKEND_DIR_NAME"

            if $DOCKER_CMD build --no-cache --platform $DOCKER_PLATFORM -f "$REPO_BASE_DIR/$BACKEND_DIR_NAME/$dockerfile_path" -t "$backend_tag" "$REPO_BASE_DIR/$BACKEND_DIR_NAME"; then
                log_success "Backend image built successfully"
                break
            else
                if [ $build_attempts -lt $max_attempts ]; then
                    log_warning "Backend build failed, retrying in 30 seconds..."
                    sleep 30
                elif [ "$dockerfile_path" = "Dockerfile" ] && [ -f "$REPO_BASE_DIR/$BACKEND_DIR_NAME/Dockerfile.fallback" ]; then
                    log_warning "Alpine-based build failed. Trying fallback Debian-based Dockerfile..."
                    dockerfile_path="Dockerfile.fallback"
                    build_attempts=0  # Reset attempts for fallback
                    max_attempts=2    # Fewer attempts for fallback
                else
                    log_error "Backend build failed after $max_attempts attempts"
                    log_info "This might be due to temporary network issues with package repositories"
                    log_info "You can try again later, or set USE_FALLBACK_DOCKERFILE=true to use Debian-based image"
                    log_info "Example: USE_FALLBACK_DOCKERFILE=true ./deploy-onprem.sh build"
                    exit 1
                fi
            fi
        done
    else
        log_info "Backend image already exists, skipping build (use FORCE_REBUILD=true to rebuild)"
    fi

    # Build frontend image (only if it doesn't exist or force rebuild)
    if [ -z "$frontend_exists" ] || [ "${FORCE_REBUILD:-false}" = "true" ]; then
        log_info "Building frontend image from $REPO_BASE_DIR/$FRONTEND_DIR_NAME..."

        # Get environment-specific Dockerfile
        local frontend_dockerfile=$(get_dockerfile "$FRONTEND_DIR_NAME")
        log_info "Using environment-specific Dockerfile: $frontend_dockerfile for $DEPLOY_ENV"

        # Get environment-specific image tag
        local frontend_tag=$(get_image_tag "prs-frontend")

        # Try building with retry logic for network issues
        local build_attempts=0
        local max_attempts=3
        while [ $build_attempts -lt $max_attempts ]; do
            build_attempts=$((build_attempts + 1))
            log_info "Frontend build attempt $build_attempts/$max_attempts..."

            # Prepare build arguments for frontend
            local build_args=""
            if [ -f "$ENV_FILE" ]; then
                # Source environment file to get build arguments
                source "$ENV_FILE"

                # Add build arguments (empty values enable dynamic host detection)
                build_args="$build_args --build-arg VITE_APP_API_URL=${VITE_APP_API_URL:-}"
                build_args="$build_args --build-arg VITE_APP_UPLOAD_URL=${VITE_APP_UPLOAD_URL:-}"
                if [ -n "${VITE_APP_ENVIRONMENT:-}" ]; then
                    build_args="$build_args --build-arg VITE_APP_ENVIRONMENT=$VITE_APP_ENVIRONMENT"
                else
                    build_args="$build_args --build-arg VITE_APP_ENVIRONMENT=$DEPLOY_ENV"
                fi
                if [ -n "${VITE_APP_ENABLE_DEVTOOLS:-}" ]; then
                    build_args="$build_args --build-arg VITE_APP_ENABLE_DEVTOOLS=$VITE_APP_ENABLE_DEVTOOLS"
                fi
            fi

            if $DOCKER_CMD build --no-cache --platform $DOCKER_PLATFORM -f "$REPO_BASE_DIR/$FRONTEND_DIR_NAME/$frontend_dockerfile" $build_args -t "$frontend_tag" "$REPO_BASE_DIR/$FRONTEND_DIR_NAME"; then
                log_success "Frontend image built successfully"
                break
            else
                if [ $build_attempts -lt $max_attempts ]; then
                    log_warning "Frontend build failed, retrying in 30 seconds..."
                    sleep 30
                else
                    log_error "Frontend build failed after $max_attempts attempts"
                    log_info "Common issues and solutions:"
                    log_info "1. Network issues with package repositories - try again later"
                    log_info "2. Missing build dependencies - check if all required packages are available"
                    log_info "3. Build script issues - verify package.json scripts are correct"
                    log_info "4. Environment variables - ensure all required VITE_APP_* variables are set"
                    log_info "You can check the Docker build logs above for specific error details"
                    exit 1
                fi
            fi
        done
    else
        log_info "Frontend image already exists, skipping build (use FORCE_REBUILD=true to rebuild)"
    fi

    log_success "Docker images ready"
}

# Build backend Docker image only
build_backend_image() {
    log_info "Building backend Docker image..."
    log_info "Detected architecture: $(uname -m) -> Docker platform: $DOCKER_PLATFORM"

    # Check docker permissions first
    if ! check_docker_permissions; then
        # Set docker command based on permissions
        if [ "${USE_SUDO_DOCKER:-0}" = "1" ]; then
            DOCKER_CMD="sudo docker"
            log_warning "Using sudo for docker commands due to permission issues"
        else
            log_error "Docker permission check failed"
            exit 1
        fi
    else
        DOCKER_CMD="docker"
    fi

    # Check if buildx is available or if we have a flag to disable BuildKit
    if [ -f /tmp/disable_buildkit ] || ! docker buildx version >/dev/null 2>&1; then
        log_warning "Docker buildx not available, disabling BuildKit for this session"
        export DOCKER_BUILDKIT=0
        export COMPOSE_DOCKER_CLI_BUILD=0
    else
        log_info "Using Docker BuildKit for optimized builds"
        export DOCKER_BUILDKIT=1
        export COMPOSE_DOCKER_CLI_BUILD=1
    fi

    # Extract repository names from URLs
    BACKEND_DIR_NAME=$(basename "${BACKEND_REPO_URL%.git}")

    # Check if backend image already exists
    local backend_exists=$($DOCKER_CMD images -q prs-backend:latest 2>/dev/null)

    # Build backend image (only if it doesn't exist or force rebuild)
    if [ -z "$backend_exists" ] || [ "${FORCE_REBUILD:-false}" = "true" ]; then
        log_info "Building backend image from $REPO_BASE_DIR/$BACKEND_DIR_NAME..."

        # Determine which Dockerfile to use
        local dockerfile_path
        if [ "${USE_FALLBACK_DOCKERFILE:-false}" = "true" ]; then
            dockerfile_path="Dockerfile.debian"
            log_info "Using fallback Debian-based Dockerfile"
        else
            dockerfile_path=$(get_dockerfile "$BACKEND_DIR_NAME")
        fi

        # Try building with retry logic for network issues
        local build_attempts=0
        local max_attempts=3
        while [ $build_attempts -lt $max_attempts ]; do
            build_attempts=$((build_attempts + 1))
            log_info "Backend build attempt $build_attempts/$max_attempts using $dockerfile_path..."

            # Get environment-specific image tag
            local backend_tag=$(get_image_tag "prs-backend")

            if $DOCKER_CMD build --no-cache --platform $DOCKER_PLATFORM -f "$REPO_BASE_DIR/$BACKEND_DIR_NAME/$dockerfile_path" -t "$backend_tag" "$REPO_BASE_DIR/$BACKEND_DIR_NAME"; then
                log_success "Backend image built successfully"
                break
            else
                if [ $build_attempts -lt $max_attempts ]; then
                    log_warning "Backend build failed, retrying in 30 seconds..."
                    sleep 30
                else
                    log_error "Backend build failed after $max_attempts attempts"
                    log_error "This might be due to network issues or missing dependencies"
                    log_info "Try running with USE_FALLBACK_DOCKERFILE=true if using Alpine-based build"
                    exit 1
                fi
            fi
        done
    else
        log_info "Backend image already exists, skipping build (use FORCE_REBUILD=true to rebuild)"
    fi

    log_success "Backend Docker image ready"
}

# Build frontend Docker image only
build_frontend_image() {
    log_info "Building frontend Docker image..."
    log_info "Detected architecture: $(uname -m) -> Docker platform: $DOCKER_PLATFORM"

    # Check docker permissions first
    if ! check_docker_permissions; then
        # Set docker command based on permissions
        if [ "${USE_SUDO_DOCKER:-0}" = "1" ]; then
            DOCKER_CMD="sudo docker"
            log_warning "Using sudo for docker commands due to permission issues"
        else
            log_error "Docker permission check failed"
            exit 1
        fi
    else
        DOCKER_CMD="docker"
    fi

    # Check if buildx is available or if we have a flag to disable BuildKit
    if [ -f /tmp/disable_buildkit ] || ! docker buildx version >/dev/null 2>&1; then
        log_warning "Docker buildx not available, disabling BuildKit for this session"
        export DOCKER_BUILDKIT=0
        export COMPOSE_DOCKER_CLI_BUILD=0
    else
        log_info "Using Docker BuildKit for optimized builds"
        export DOCKER_BUILDKIT=1
        export COMPOSE_DOCKER_CLI_BUILD=1
    fi

    # Extract repository names from URLs
    FRONTEND_DIR_NAME=$(basename "${FRONTEND_REPO_URL%.git}")

    # Check if frontend image already exists
    local frontend_exists=$($DOCKER_CMD images -q prs-frontend:latest 2>/dev/null)

    # Build frontend image (only if it doesn't exist or force rebuild)
    if [ -z "$frontend_exists" ] || [ "${FORCE_REBUILD:-false}" = "true" ]; then
        log_info "Building frontend image from $REPO_BASE_DIR/$FRONTEND_DIR_NAME..."

        # Get environment-specific Dockerfile
        local frontend_dockerfile=$(get_dockerfile "$FRONTEND_DIR_NAME")

        # Get environment-specific image tag
        local frontend_tag=$(get_image_tag "prs-frontend")

        # Try building with retry logic for network issues
        local build_attempts=0
        local max_attempts=3
        while [ $build_attempts -lt $max_attempts ]; do
            build_attempts=$((build_attempts + 1))
            log_info "Frontend build attempt $build_attempts/$max_attempts..."

            # Prepare build arguments for frontend
            local build_args=""
            if [ -f "$ENV_FILE" ]; then
                # Source environment file to get build arguments
                source "$ENV_FILE"

                # Add build arguments (empty values enable dynamic host detection)
                build_args="$build_args --build-arg VITE_APP_API_URL=${VITE_APP_API_URL:-}"
                build_args="$build_args --build-arg VITE_APP_UPLOAD_URL=${VITE_APP_UPLOAD_URL:-}"
                if [ -n "${VITE_APP_ENVIRONMENT:-}" ]; then
                    build_args="$build_args --build-arg VITE_APP_ENVIRONMENT=$VITE_APP_ENVIRONMENT"
                else
                    build_args="$build_args --build-arg VITE_APP_ENVIRONMENT=$DEPLOY_ENV"
                fi
                if [ -n "${VITE_APP_ENABLE_DEVTOOLS:-}" ]; then
                    build_args="$build_args --build-arg VITE_APP_ENABLE_DEVTOOLS=$VITE_APP_ENABLE_DEVTOOLS"
                fi
            fi

            if $DOCKER_CMD build --no-cache --platform $DOCKER_PLATFORM -f "$REPO_BASE_DIR/$FRONTEND_DIR_NAME/$frontend_dockerfile" $build_args -t "$frontend_tag" "$REPO_BASE_DIR/$FRONTEND_DIR_NAME"; then
                log_success "Frontend image built successfully"
                break
            else
                if [ $build_attempts -lt $max_attempts ]; then
                    log_warning "Frontend build failed, retrying in 30 seconds..."
                    sleep 30
                else
                    log_error "Frontend build failed after $max_attempts attempts"
                    log_error "This might be due to network issues or missing dependencies"
                    exit 1
                fi
            fi
        done
    else
        log_info "Frontend image already exists, skipping build (use FORCE_REBUILD=true to rebuild)"
    fi

    log_success "Frontend Docker image ready"
}

# Start services
start_services() {
    local force_restart="${1:-false}"
    log_info "Starting services for $DEPLOY_ENV environment..."

    if [ "$force_restart" = "true" ]; then
        log_info "Force restart mode enabled - will restart all services"
    fi

    cd "$PROJECT_DIR/02-docker-configuration"

    # Check which services are already running
    local compose_file_name=$(basename "$COMPOSE_FILE")
    local running_services=$(docker compose -f "$compose_file_name" ps --services --filter "status=running" 2>/dev/null || true)

    # If force restart is enabled, stop all services first
    if [ "$force_restart" = "true" ] && [ -n "$running_services" ]; then
        log_info "Stopping all services for clean restart..."
        docker compose -f "$compose_file_name" down
        sleep 5
        running_services=""  # Reset since we stopped everything
    fi

    # Start infrastructure services first
    if ! echo "$running_services" | grep -q "postgres\|redis"; then
        log_info "Starting database and cache services..."
        docker compose -f "$compose_file_name" up -d postgres redis

        # Wait for database to be ready with proper health check
        log_info "Waiting for database to be ready..."
        local db_ready=false
        local wait_time=0
        local max_wait=120

        while [ $wait_time -lt $max_wait ]; do
            if docker exec prs-onprem-postgres-timescale pg_isready -U prs_user >/dev/null 2>&1; then
                log_success "Database is ready"
                db_ready=true
                break
            fi
            sleep 5
            wait_time=$((wait_time + 5))
            if [ $((wait_time % 30)) -eq 0 ]; then
                log_info "Still waiting for database... (${wait_time}s elapsed)"
            fi
        done

        if [ "$db_ready" = false ]; then
            log_warning "Database did not become ready within ${max_wait} seconds, but continuing..."
        fi
    else
        log_info "Database and cache services are already running"
    fi

    # Start application services
    if ! echo "$running_services" | grep -q "backend\|redis-worker"; then
        log_info "Starting application services..."
        docker compose -f "$compose_file_name" up -d backend redis-worker

        # Wait for backend to be ready
        log_info "Waiting for backend service to be ready..."
        sleep 15  # Give backend time to start

        # Check if backend container is running
        local backend_wait=0
        local max_backend_wait=60
        while [ $backend_wait -lt $max_backend_wait ]; do
            if docker ps | grep -q "prs-onprem-backend"; then
                log_success "Backend service is running"
                break
            fi
            sleep 2
            backend_wait=$((backend_wait + 2))
        done

        if [ $backend_wait -ge $max_backend_wait ]; then
            log_warning "Backend service did not start within ${max_backend_wait} seconds"
        fi
    else
        log_info "Application services are already running"
    fi

    # Start web services
    if ! echo "$running_services" | grep -q "frontend\|nginx"; then
        log_info "Starting web services..."
        docker compose -f "$compose_file_name" up -d frontend nginx
    else
        log_info "Web services are already running"
    fi

    # Start monitoring services (only for prod/staging environments)
    if [ "$DEPLOY_ENV" = "prod" ] || [ "$DEPLOY_ENV" = "staging" ]; then
        if ! echo "$running_services" | grep -q "prometheus\|grafana"; then
            log_info "Setting up monitoring prerequisites..."
            setup_monitoring_prerequisites
            log_info "Starting monitoring services..."
            docker compose -f "$compose_file_name" --profile monitoring up -d
        else
            log_info "Monitoring services are already running"
        fi
    else
        log_info "Skipping monitoring services for $DEPLOY_ENV environment"
    fi

    # Start management tools (only for dev/staging/prod environments)
    if [ "$DEPLOY_ENV" != "test" ]; then
        if ! echo "$running_services" | grep -q "adminer\|portainer"; then
            log_info "Starting management tools..."
            docker compose -f "$compose_file_name" up -d adminer portainer
        else
            log_info "Management tools are already running"
        fi
    else
        log_info "Skipping management tools for $DEPLOY_ENV environment"
    fi

    log_success "All services started"
}

# Wait for services to be healthy and ready
wait_for_services_ready() {
    log_info "Verifying services are healthy and ready..."

    cd "$PROJECT_DIR/02-docker-configuration"
    local compose_file_name=$(basename "$COMPOSE_FILE")

    # Check PostgreSQL health
    log_info "Checking PostgreSQL health..."

    # First check if container is running
    if ! docker ps | grep -q "prs-onprem-postgres-timescale"; then
        log_error "PostgreSQL container is not running!"
        log_info "Checking container status:"
        docker ps -a | grep postgres || log_info "No postgres containers found"
        log_info "Recent PostgreSQL logs:"
        docker logs --tail 10 prs-onprem-postgres-timescale 2>/dev/null || log_info "Could not retrieve logs"
        return 1
    fi

    local db_attempts=0
    local max_db_attempts=30
    while [ $db_attempts -lt $max_db_attempts ]; do
        if docker exec prs-onprem-postgres-timescale pg_isready -U prs_user >/dev/null 2>&1; then
            log_success "PostgreSQL is healthy"
            break
        fi
        sleep 2
        db_attempts=$((db_attempts + 1))
        if [ $((db_attempts % 10)) -eq 0 ]; then
            log_info "Still checking PostgreSQL health... (attempt $db_attempts/$max_db_attempts)"
            # Show some debugging info every 10 attempts
            if [ $db_attempts -eq 20 ]; then
                log_info "PostgreSQL container status:"
                docker ps | grep postgres || log_info "Container not found in running processes"
                log_info "Recent PostgreSQL logs:"
                docker logs --tail 5 prs-onprem-postgres-timescale 2>/dev/null || log_info "Could not retrieve logs"
            fi
        fi
    done

    if [ $db_attempts -eq $max_db_attempts ]; then
        log_error "PostgreSQL failed health check after $max_db_attempts attempts"
        log_info "Final debugging information:"
        log_info "Container status:"
        docker ps -a | grep postgres || log_info "No postgres containers found"
        log_info "Recent PostgreSQL logs (last 20 lines):"
        docker logs --tail 20 prs-onprem-postgres-timescale 2>/dev/null || log_info "Could not retrieve logs"
        log_info "Environment variables in container:"
        docker exec prs-onprem-postgres-timescale env | grep POSTGRES 2>/dev/null || log_info "Could not retrieve environment"
        return 1
    fi

    # Check backend health (if it has a health endpoint)
    log_info "Checking backend service..."
    if docker ps | grep -q "prs-onprem-backend"; then
        log_success "Backend container is running"
    else
        log_warning "Backend container is not running"
        return 1
    fi

    # Check Redis health
    log_info "Checking Redis health..."
    if docker exec prs-onprem-redis redis-cli ping >/dev/null 2>&1; then
        log_success "Redis is healthy"
    else
        log_warning "Redis health check failed, but continuing..."
    fi

    log_success "All critical services are healthy and ready"
    return 0
}

# Stop services
stop_services() {
    log_info "Stopping services for $DEPLOY_ENV environment..."

    cd "$PROJECT_DIR/02-docker-configuration"
    local compose_file_name=$(basename "$COMPOSE_FILE")
    docker compose -f "$compose_file_name" down

    log_success "All services stopped"
}

# Initialize database
init_users_database() {
    log_info "Initializing database..."

    cd "$PROJECT_DIR/02-docker-configuration"

    # Wait for containers to be running and ready with better error handling
    log_info "Checking container status..."

    # Check if database container is running with retry logic
    local max_retries=30
    local retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        if docker ps | grep -q "prs-onprem-postgres-timescale"; then
            log_info "PostgreSQL container is running"
            break
        else
            if [ $retry_count -eq 0 ]; then
                log_info "Waiting for PostgreSQL container to start..."
            fi
            sleep 2
            retry_count=$((retry_count + 1))
        fi
    done

    if [ $retry_count -eq $max_retries ]; then
        log_error "PostgreSQL container is not running after waiting 60 seconds."
        log_info "Checking container status:"
        docker ps -a | grep postgres || log_info "No postgres containers found"
        log_info "Please check if services started correctly with: $0 status"
        exit 1
    fi

    # Check if backend container is running with retry logic
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        if docker ps | grep -q "prs-onprem-backend"; then
            log_info "Backend container is running"
            break
        else
            if [ $retry_count -eq 0 ]; then
                log_info "Waiting for backend container to start..."
            fi
            sleep 2
            retry_count=$((retry_count + 1))
        fi
    done

    if [ $retry_count -eq $max_retries ]; then
        log_error "Backend container is not running after waiting 60 seconds."
        log_info "Checking container status:"
        docker ps -a | grep backend || log_info "No backend containers found"
        log_info "Please check if services started correctly with: $0 status"
        exit 1
    fi

    # Wait for database to be ready with better error handling
    log_info "Waiting for database connection..."
    if ! timeout 120 bash -c 'until docker exec prs-onprem-postgres-timescale pg_isready -U prs_user >/dev/null 2>&1; do sleep 2; done'; then
        log_error "Database failed to become ready within 120 seconds"
        log_info "Checking database container logs:"
        docker logs --tail 20 prs-onprem-postgres-timescale || log_info "Could not retrieve container logs"
        exit 1
    fi

    log_success "Database is ready for initialization"

    # Check if users table already exists and has data
    local user_count=$(docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='users';" 2>/dev/null | tr -d ' ' || echo "0")

    if [ "$user_count" -gt 0 ]; then
        local existing_users=$(docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$existing_users" -gt 0 ]; then
            log_info "Database already has $existing_users users, skipping initialization"
            return 0
        fi
    fi



    # # Run migrations (should be idempotent)
    # log_info "Running database migrations..."
    # docker exec prs-onprem-backend npm run migrate

    # Run all database seeders (roles, permissions, users, etc.)
    log_info "Running database seeders..."
    if docker exec prs-onprem-backend npm run seed:dev; then
        log_success "Database seeders completed successfully"
    else
        log_warning "Some seeders failed or data already exists"
    fi

    log_success "Database initialized"
}


# Database access functions
db_connect() {
    log_info "Connecting to PostgreSQL database..."

    # Load environment to get database credentials
    load_environment

    # Check if database container is running
    if ! docker ps | grep -q "prs-onprem-postgres-timescale"; then
        log_error "PostgreSQL container is not running. Please start services first."
        exit 1
    fi

    # Connect to database
    docker exec -it prs-onprem-postgres-timescale psql -U prs_user -d prs_production
}

# Database shell access
db_shell() {
    log_info "Opening database shell..."

    # Load environment to get database credentials
    load_environment

    # Check if database container is running
    if ! docker ps | grep -q "prs-onprem-postgres-timescale"; then
        log_error "PostgreSQL container is not running. Please start services first."
        exit 1
    fi

    # Open shell in database container
    docker exec -it prs-onprem-postgres-timescale bash
}

# Database backup
db_backup() {
    log_info "Creating database backup..."

    # Load environment to get database credentials
    load_environment

    # Check if database container is running
    if ! docker ps | grep -q "prs-onprem-postgres-timescale"; then
        log_error "PostgreSQL container is not running. Please start services first."
        exit 1
    fi

    # Get backup path from environment
    local HDD_MOUNT="${HDD_MOUNT_PATH:-/mnt/hdd}"
    local BACKUP_DIR="${HDD_BACKUP_PATH:-$HDD_MOUNT/backups}/postgres-backups"

    # Create backup directory if it doesn't exist (idempotent)
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log_info "Created backup directory: $BACKUP_DIR"
    fi

    # Generate backup filename with timestamp
    BACKUP_FILE="$BACKUP_DIR/prs_production_$(date +%Y%m%d_%H%M%S).sql"

    # Create backup
    log_info "Creating backup: $BACKUP_FILE"
    if docker exec prs-onprem-postgres-timescale pg_dump -U prs_user -d prs_production > "$BACKUP_FILE"; then
        # Compress backup
        gzip "$BACKUP_FILE"
        log_success "Database backup created: ${BACKUP_FILE}.gz"
    else
        log_error "Failed to create database backup"
        # Clean up failed backup file
        rm -f "$BACKUP_FILE"
        exit 1
    fi
}

# Database restore
db_restore() {
    if [ -z "$1" ]; then
        # Get backup path from environment
        local HDD_MOUNT="${HDD_MOUNT_PATH:-/mnt/hdd}"
        local BACKUP_DIR="${HDD_BACKUP_PATH:-$HDD_MOUNT/backups}/postgres-backups"

        log_error "Usage: $0 db-restore <backup_file>"
        log_info "Available backups in $BACKUP_DIR:"
        if [ -d "$BACKUP_DIR" ]; then
            ls -la "$BACKUP_DIR/"
        else
            log_warning "Backup directory $BACKUP_DIR does not exist"
        fi
        exit 1
    fi

    BACKUP_FILE="$1"

    if [ ! -f "$BACKUP_FILE" ]; then
        log_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi

    log_warning "This will restore the database from backup. All current data will be lost!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Database restore cancelled"
        exit 0
    fi

    # Load environment
    load_environment

    # Check if database container is running
    if ! docker ps | grep -q "prs-onprem-postgres-timescale"; then
        log_error "PostgreSQL container is not running. Please start services first."
        exit 1
    fi

    # Stop application services to prevent connections
    log_info "Stopping application services..."
    cd "$PROJECT_DIR/02-docker-configuration"
    docker compose -f docker-compose.onprem.yml stop backend redis-worker frontend

    # Drop and recreate database
    log_info "Recreating database..."
    docker exec prs-onprem-postgres-timescale psql -U prs_user -c "DROP DATABASE IF EXISTS prs_production;"
    docker exec prs-onprem-postgres-timescale psql -U prs_user -c "CREATE DATABASE prs_production;"

    # Restore from backup
    log_info "Restoring from backup..."
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        gunzip -c "$BACKUP_FILE" | docker exec -i prs-onprem-postgres-timescale psql -U prs_user -d prs_production
    else
        docker exec -i prs-onprem-postgres-timescale psql -U prs_user -d prs_production < "$BACKUP_FILE"
    fi

    # Restart application services
    log_info "Restarting application services..."
    docker compose -f docker-compose.onprem.yml start backend redis-worker frontend

    log_success "Database restored from: $BACKUP_FILE"
}

# Setup TimescaleDB (HDD-only configuration)
setup_timescaledb() {
    log_info "Setting up TimescaleDB (HDD-only configuration)..."

    # Load environment to get database credentials
    load_environment

    # Check if database container is running
    if ! docker ps | grep -q "prs-onprem-postgres-timescale"; then
        log_error "PostgreSQL container is not running. Please start services first."
        exit 1
    fi

    # Wait for database to be ready
    log_info "Waiting for database to be ready..."
    if ! timeout 60 bash -c 'until docker exec prs-onprem-postgres-timescale pg_isready -U prs_user >/dev/null 2>&1; do sleep 2; done'; then
        log_error "Database failed to become ready within 60 seconds"
        exit 1
    fi

    # Get database credentials from environment
    local POSTGRES_USER="${POSTGRES_USER:-prs_user}"
    local POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
    local POSTGRES_DB="${POSTGRES_DB:-prs_production}"

    if [ -z "$POSTGRES_PASSWORD" ]; then
        log_error "POSTGRES_PASSWORD not found in environment"
        exit 1
    fi

    log_info "Using simplified HDD-only storage configuration"

    # Check if TimescaleDB extension is available and enable it
    log_info "Checking TimescaleDB extension..."
    local ts_available=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" prs-onprem-postgres-timescale psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT COUNT(*) FROM pg_available_extensions WHERE name='timescaledb';" 2>/dev/null | tr -d ' \n' | grep -o '[0-9]*' || echo "0")

    # Ensure we have a valid number
    if [ -z "$ts_available" ] || ! [[ "$ts_available" =~ ^[0-9]+$ ]]; then
        ts_available=0
    fi

    local timescaledb_enabled=false

    if [ "$ts_available" -eq 0 ]; then
        log_warning "TimescaleDB extension not available, continuing with regular PostgreSQL"
    else
        log_info "TimescaleDB extension is available"

        # Enable TimescaleDB extension if not already enabled
        local ts_enabled=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" prs-onprem-postgres-timescale psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT COUNT(*) FROM pg_extension WHERE extname='timescaledb';" 2>/dev/null | tr -d ' \n' | grep -o '[0-9]*' || echo "0")

        # Ensure we have a valid number
        if [ -z "$ts_enabled" ] || ! [[ "$ts_enabled" =~ ^[0-9]+$ ]]; then
            ts_enabled=0
        fi

        if [ "$ts_enabled" -eq 0 ]; then
            log_info "Enabling TimescaleDB extension..."
            if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" prs-onprem-postgres-timescale psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE EXTENSION IF NOT EXISTS timescaledb;" >/dev/null 2>&1; then
                log_success "TimescaleDB extension enabled"
                timescaledb_enabled=true
            else
                log_warning "Failed to enable TimescaleDB extension, continuing with regular PostgreSQL"
            fi
        else
            log_info "TimescaleDB extension is already enabled"
            timescaledb_enabled=true
        fi
    fi

    # HDD-only configuration - no complex setup needed
    log_info "Using default PostgreSQL storage on HDD"

    # TimescaleDB setup completed - HDD-only configuration
    if [ "$timescaledb_enabled" = true ]; then
        log_success "TimescaleDB setup completed (HDD-only configuration)"
    else
        log_success "PostgreSQL setup completed (HDD-only configuration)"
    fi
}





# Run TimescaleDB optimization (HDD-only configuration)
optimize_timescaledb() {
    log_info "Running TimescaleDB optimization (HDD-only configuration)..."

    # Load environment to get database credentials
    load_environment

    # Check if database container is running
    if ! docker ps | grep -q "prs-onprem-postgres-timescale"; then
        log_error "PostgreSQL container is not running. Please start services first."
        exit 1
    fi

    # Check if optimization scripts exist
    local post_setup_script="/opt/prs/prs-deployment/scripts/timescaledb-post-setup-optimization.sh"
    local auto_optimizer_script="/opt/prs/prs-deployment/scripts/timescaledb-auto-optimizer.sh"

    if [ ! -f "$post_setup_script" ]; then
        log_error "Post-setup optimization script not found: $post_setup_script"
        exit 1
    fi

    if [ ! -f "$auto_optimizer_script" ]; then
        log_error "Auto-optimizer script not found: $auto_optimizer_script"
        exit 1
    fi

    # Step 1: Ensure TimescaleDB is set up (HDD-only configuration)
    log_info "Step 1: Ensuring TimescaleDB setup is complete..."
    setup_timescaledb

    # Step 2: Run post-setup optimization (compression policies, retention policies, etc.)
    log_info "Step 2: Running post-setup optimization..."
    if bash "$post_setup_script"; then
        log_success "Post-setup optimization completed"
    else
        log_warning "Post-setup optimization had some issues, continuing..."
    fi

    # Step 3: Run auto-optimizer (compress chunks, optimize policies)
    log_info "Step 3: Running auto-optimizer..."
    if bash "$auto_optimizer_script"; then
        log_success "Auto-optimization completed"
    else
        log_warning "Auto-optimization had some issues, continuing..."
    fi

    # Step 6: Show final optimization summary
    log_info "Step 6: Generating optimization summary..."

    log_info "Final TimescaleDB optimization summary:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" prs-onprem-postgres-timescale psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT
            'Hypertables' as metric,
            COUNT(*)::text as value
        FROM timescaledb_information.hypertables
        UNION ALL
        SELECT
            'Total Chunks' as metric,
            COUNT(*)::text as value
        FROM timescaledb_information.chunks
        UNION ALL
        SELECT
            'Compressed Chunks' as metric,
            COUNT(*)::text as value
        FROM timescaledb_information.chunks WHERE is_compressed
        UNION ALL
        SELECT
            'HDD Chunks' as metric,
            COUNT(*)::text as value
        FROM timescaledb_information.chunks
        UNION ALL
        SELECT
            'Active Compression Policies' as metric,
            COUNT(*)::text as value
        FROM timescaledb_information.jobs
        WHERE application_name LIKE '%Compression%'
        UNION ALL
        SELECT
            'Active Retention Policies' as metric,
            COUNT(*)::text as value
        FROM timescaledb_information.jobs
        WHERE application_name LIKE '%Retention%';
    " 2>/dev/null || log_warning "Could not generate summary"

    log_success "TimescaleDB optimization completed (HDD-only configuration)!"

    log_info "Production automation recommendations:"
    echo "  1. One-time setup: ./deploy-onprem.sh optimize-timescaledb (DONE)"
    echo "  2. Weekly maintenance: ./deploy-onprem.sh weekly-maintenance"
    echo "  3. Monitor with: ./deploy-onprem.sh timescaledb-status"
    echo "  4. Consider database restart for all PostgreSQL settings to take effect"
}

# Weekly maintenance for production (cron-friendly)
weekly_maintenance() {
    log_info "Running weekly TimescaleDB maintenance..."

    # Load environment
    load_environment

    # Check if database container is running
    if ! docker ps | grep -q "prs-onprem-postgres-timescale"; then
        log_error "PostgreSQL container is not running. Skipping maintenance."
        exit 1
    fi

    local POSTGRES_USER="${POSTGRES_USER:-prs_user}"
    local POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
    local POSTGRES_DB="${POSTGRES_DB:-prs_production}"

    if [ -z "$POSTGRES_PASSWORD" ]; then
        log_error "POSTGRES_PASSWORD not found in environment"
        exit 1
    fi

    # HDD-only configuration - all data already optimally placed
    log_info "HDD-only configuration - all data optimally placed on HDD"

    # Run the auto-optimizer if it exists
    local auto_optimizer_script="/opt/prs/prs-deployment/scripts/timescaledb-auto-optimizer.sh"
    if [ -f "$auto_optimizer_script" ]; then
        log_info "Running TimescaleDB auto-optimizer..."
        if bash "$auto_optimizer_script" >/dev/null 2>&1; then
            log_success "Auto-optimizer completed successfully"
        else
            log_warning "Auto-optimizer had some issues"
        fi
    else
        log_warning "Auto-optimizer script not found, skipping"
    fi

    # Generate maintenance summary
    log_info "Weekly maintenance summary:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" prs-onprem-postgres-timescale psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT
            'Total Chunks' as metric,
            COUNT(*)::text as value
        FROM timescaledb_information.chunks
        UNION ALL
        SELECT
            'Compressed Chunks' as metric,
            COUNT(*)::text as value
        FROM timescaledb_information.chunks WHERE is_compressed
        UNION ALL
        SELECT
            'HDD Chunks' as metric,
            COUNT(*)::text as value
        FROM timescaledb_information.chunks;
    " 2>/dev/null || log_warning "Could not generate summary"

    log_success "Weekly maintenance completed!"
}

# Show TimescaleDB status (monitoring-friendly)
timescaledb_status() {
    log_info "TimescaleDB Status Report"

    # Load environment
    load_environment

    local POSTGRES_USER="${POSTGRES_USER:-prs_user}"
    local POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
    local POSTGRES_DB="${POSTGRES_DB:-prs_production}"

    if ! docker ps | grep -q "prs-onprem-postgres-timescale"; then
        log_error "PostgreSQL container is not running"
        exit 1
    fi

    echo ""
    log_info "=== CHUNK DISTRIBUTION ==="
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" prs-onprem-postgres-timescale psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT
            'HDD (default)' as storage,
            CASE WHEN c.is_compressed THEN 'Compressed' ELSE 'Uncompressed' END as compression_status,
            COUNT(*) as chunk_count,
            ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - c.range_end))/86400), 1) as avg_age_days
        FROM timescaledb_information.chunks c
        GROUP BY c.is_compressed
        ORDER BY compression_status;
    " 2>/dev/null || log_warning "Could not retrieve chunk distribution"

    echo ""
    log_info "=== ACTIVE POLICIES ==="
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" prs-onprem-postgres-timescale psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT
            job_id,
            application_name,
            schedule_interval,
            CASE WHEN scheduled THEN 'Active' ELSE 'Inactive' END as status
        FROM timescaledb_information.jobs
        WHERE application_name LIKE '%Compression%' OR application_name LIKE '%Retention%'
        ORDER BY application_name;
    " 2>/dev/null || log_warning "Could not retrieve policies"

    echo ""
    log_info "=== CHUNK STATUS ==="
    log_success "All chunks use HDD storage (simplified configuration)"

    echo ""
}

# Troubleshoot deployment issues
troubleshoot_deployment() {
    log_info "Running deployment troubleshooting..."

    cd "$PROJECT_DIR/02-docker-configuration"
    local compose_file_name=$(basename "$COMPOSE_FILE")

    echo ""
    log_info "=== Container Status ==="
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    echo ""
    log_info "=== Docker Compose Services ==="
    docker compose -f "$compose_file_name" ps

    echo ""
    log_info "=== Critical Container Health Checks ==="

    # Check PostgreSQL
    if docker ps | grep -q "prs-onprem-postgres-timescale"; then
        echo "✓ PostgreSQL container is running"
        if docker exec prs-onprem-postgres-timescale pg_isready -U prs_user >/dev/null 2>&1; then
            echo "✓ PostgreSQL is accepting connections"
        else
            echo "✗ PostgreSQL is not accepting connections"
            echo "PostgreSQL logs (last 10 lines):"
            docker logs --tail 10 prs-onprem-postgres-timescale
        fi
    else
        echo "✗ PostgreSQL container is not running"
        echo "Checking for any postgres containers:"
        docker ps -a | grep postgres || echo "No postgres containers found"
    fi

    # Check Backend
    if docker ps | grep -q "prs-onprem-backend"; then
        echo "✓ Backend container is running"
    else
        echo "✗ Backend container is not running"
        echo "Checking for any backend containers:"
        docker ps -a | grep backend || echo "No backend containers found"
        echo "Backend logs (last 10 lines):"
        docker logs --tail 10 prs-onprem-backend 2>/dev/null || echo "Could not retrieve backend logs"
    fi

    # Check Redis
    if docker ps | grep -q "prs-onprem-redis"; then
        echo "✓ Redis container is running"
        if docker exec prs-onprem-redis redis-cli ping >/dev/null 2>&1; then
            echo "✓ Redis is responding to ping"
        else
            echo "✗ Redis is not responding to ping"
        fi
    else
        echo "✗ Redis container is not running"
    fi

    echo ""
    log_info "=== System Resources ==="
    echo "Memory usage:"
    free -h
    echo ""
    echo "Disk usage:"
    df -h | grep -E "(Filesystem|/mnt|/$)"

    echo ""
    log_info "=== Environment Configuration ==="
    if [ -f "$ENV_FILE" ]; then
        echo "Environment file: $ENV_FILE ✓"
        echo "Compose file: $COMPOSE_FILE ✓"
    else
        echo "Environment file: $ENV_FILE ✗"
    fi

    echo ""
    log_info "=== Recent Container Logs ==="
    echo "PostgreSQL logs (last 5 lines):"
    docker logs --tail 5 prs-onprem-postgres-timescale 2>/dev/null || echo "Could not retrieve PostgreSQL logs"
    echo ""
    echo "Backend logs (last 5 lines):"
    docker logs --tail 5 prs-onprem-backend 2>/dev/null || echo "Could not retrieve backend logs"

    echo ""
    log_info "=== Troubleshooting Complete ==="
    log_info "If issues persist, check the full logs with:"
    echo "  docker logs prs-onprem-postgres-timescale"
    echo "  docker logs prs-onprem-backend"
    echo "  docker logs prs-onprem-redis"
}

# Show service status
show_status() {
    log_info "Service Status for $DEPLOY_ENV environment:"
    cd "$PROJECT_DIR/02-docker-configuration"
    local compose_file_name=$(basename "$COMPOSE_FILE")
    docker compose -f "$compose_file_name" ps

    echo ""
    log_info "System Resources:"
    echo "Memory: $(free -h | grep Mem | awk '{print $3"/"$2}')"

    # Get storage paths from environment (HDD-only configuration)
    local HDD_MOUNT="${STORAGE_HDD_PATH:-/mnt/hdd}"
    local NAS_MOUNT="${NAS_BACKUP_PATH:-/mnt/nas}"

    if [ -d "$HDD_MOUNT" ]; then
        echo "HDD Usage ($HDD_MOUNT): $(df -h "$HDD_MOUNT" | awk 'NR==2 {print $5}')"
    else
        echo "HDD Usage: Mount not available at $HDD_MOUNT"
    fi

    if [ -d "$NAS_MOUNT" ]; then
        echo "NAS Usage ($NAS_MOUNT): $(df -h "$NAS_MOUNT" | awk 'NR==2 {print $5}')"
    fi

    echo ""
    log_info "Service URLs for $DEPLOY_ENV environment:"

    # Load environment variables to get server IP and ports
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi

    local server_ip="${SERVER_IP:-192.168.0.100}"
    local http_port="${HTTP_PORT:-80}"
    local https_port="${HTTPS_PORT:-443}"

    echo "Application: https://$server_ip:$https_port/"

    if [ "$DEPLOY_ENV" = "prod" ] || [ "$DEPLOY_ENV" = "staging" ]; then
        echo "Grafana: http://$server_ip:${GRAFANA_PORT:-3001}/"
        echo "Prometheus: http://$server_ip:${PROMETHEUS_PORT:-9090}/"
    fi

    if [ "$DEPLOY_ENV" != "test" ]; then
        echo "Adminer: http://$server_ip:${ADMINER_PORT:-8080}/"
        echo "Portainer: http://$server_ip:${PORTAINER_PORT:-9000}/"
    fi
}

# Show usage information
show_usage() {
    echo "PRS On-Premises Production Deployment Script (Idempotent)"
    echo "Adapted from EC2 setup for on-premises infrastructure"
    echo "Optimized for 16GB RAM, 100 concurrent users, HDD-only storage"
    echo ""
    echo "This script is designed to be idempotent - it can be run multiple times safely."
    echo "It will skip steps that have already been completed and only perform necessary changes."
    echo ""
    echo "Current deployment environment: $DEPLOY_ENV"
    echo "Environment file: $ENV_FILE"
    echo "Compose file: $COMPOSE_FILE"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo "       DEPLOY_ENV=<env> $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Deployment Commands:"
    echo "  deploy              Full deployment (install, build, start, init) - idempotent"
    echo "  redeploy            Force redeployment with minimal downtime (preserves data)"
    echo "  reset-deploy        Force redeployment with database reset (DESTRUCTIVE - deletes data)"
    echo "  setup               Setup system (dependencies, storage, firewall) - idempotent"
    echo "  install-buildx      Install/fix Docker buildx plugin - idempotent"
    echo "  build               Build Docker images - idempotent (use FORCE_REBUILD=true to force)"
    echo "  build-backend       Build backend Docker image only - idempotent"
    echo "  build-frontend      Build frontend Docker image only - idempotent"
    echo "  start               Start services - idempotent"
    echo "  stop                Stop services"
    echo "  restart             Restart services"
    echo "  wait-ready          Wait for services to be healthy and ready"
    echo "  status              Show service status and resource usage"
    echo "  check-state         Check overall system state"
    echo ""
    echo "Database Commands:"
    echo "  init-db             Initialize database - idempotent"
    echo "  db-connect          Connect to PostgreSQL database"
    echo "  db-shell            Open shell in database container"
    echo "  db-backup           Create database backup"
    echo "  db-restore <file>   Restore database from backup"
    echo ""
    echo "Other Commands:"
    echo "  ssl-setup           Setup SSL certificates - idempotent"
    echo "  firewall-setup      Configure firewall rules - idempotent"
    echo "  timescaledb-setup   Setup TimescaleDB (HDD-only configuration) - idempotent"
    echo "  optimize-timescaledb Complete TimescaleDB optimization (HDD-only configuration)"
    echo "  weekly-maintenance  Automated weekly TimescaleDB maintenance (cron-friendly)"
    echo "  timescaledb-status  Show TimescaleDB status and chunk distribution"
    echo "  fix-docker-perms    Fix Docker permission issues - idempotent"
    echo "  reset-state         Reset deployment state flags"
    echo "  health              Run health check"
    echo "  backup              Run backup"
    echo "  troubleshoot        Show detailed container status and logs for debugging"
    echo "  help                Show this help message"
    echo ""
    echo "Environment Configuration:"
    echo "  DEPLOY_ENV              Deployment environment: dev, staging, prod, test (default: prod)"
    echo ""
    echo "Repository Configuration (Environment Variables):"
    echo "  BACKEND_REPO_URL        Backend repository URL (default: https://github.com/stratpoint-engineering/prs-backend-a.git)"
    echo "  FRONTEND_REPO_URL       Frontend repository URL (default: https://github.com/stratpoint-engineering/prs-frontend-a.git)"
    echo "  BACKEND_BRANCH          Backend branch (default: main)"
    echo "  FRONTEND_BRANCH         Frontend branch (default: main)"
    echo "  REPO_BASE_DIR           Repository base directory (default: /opt/prs)"
    echo "  FORCE_REBUILD           Set to 'true' to force rebuild of Docker images"
    echo "  USE_FALLBACK_DOCKERFILE Set to 'true' to use Debian-based Dockerfile if Alpine repos fail"
    echo "  DOCKER_PLATFORM         Override Docker platform (auto-detected: linux/amd64, linux/arm64, linux/arm/v7)"
    echo ""
    echo "Frontend Configuration:"
    echo "  The frontend automatically detects the current host (IP or domain) for API calls."
    echo "  Leave VITE_APP_API_URL and VITE_APP_UPLOAD_URL empty in .env for dynamic detection."
    echo "  This allows access via both IP (192.168.0.100) and domain (prs.example.com)."
    echo ""
    echo "Examples:"
    echo "  $0 deploy                                    # Full deployment with default repos (prod environment)"
    echo "  $0 redeploy                                  # Force redeployment with minimal downtime (preserves data)"
    echo "  $0 reset-deploy                              # DESTRUCTIVE: Reset deployment with database wipe"
    echo "  DEPLOY_ENV=dev $0 deploy                     # Deploy to development environment"
    echo "  DEPLOY_ENV=staging $0 deploy                 # Deploy to staging environment"
    echo "  $0 check-state                               # Check what has been completed"
    echo "  $0 troubleshoot                              # Show detailed debugging information"
    echo "  FORCE_REBUILD=true $0 build                  # Force rebuild of images"
    echo "  $0 build-frontend                            # Build only frontend image"
    echo "  $0 build-backend                             # Build only backend image"
    echo "  USE_FALLBACK_DOCKERFILE=true $0 build        # Use Debian-based Dockerfile if Alpine fails"
    echo "  DEPLOY_ENV=dev BACKEND_REPO_URL=https://github.com/user/my-backend.git $0 deploy"
    echo "  DEPLOY_ENV=staging $0 status                 # Check staging environment status"
    echo "  DEPLOY_ENV=prod $0 restart                   # Restart production services"
    echo "  $0 db-connect                                # Connect to database"
    echo "  $0 db-backup                                 # Create database backup"
    echo "  $0 timescaledb-setup                         # Setup TimescaleDB (HDD-only)"
    echo "  $0 db-restore \${HDD_BACKUP_PATH}/postgres-backups/backup.sql.gz"
}

# Main script logic
case "${1:-deploy}" in
    "deploy")
        log_info "Starting full deployment for $DEPLOY_ENV environment..."
        log_info "Using environment file: $ENV_FILE"
        log_info "Using compose file: $COMPOSE_FILE"

        # Check if deployment was already completed
        local is_redeployment=false
        if is_deploy_complete; then
            log_info "Deployment appears to be complete. Checking service status..."
            load_environment
            show_status

            # Ask if user wants to redeploy
            read -p "Deployment seems complete. Do you want to redeploy anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Skipping deployment. Use 'restart' to restart services or specific commands for partial updates."
                exit 0
            fi
            log_info "Proceeding with redeployment..."
            is_redeployment=true
        fi

        check_prerequisites
        install_dependencies
        setup_storage
        configure_firewall
        setup_ssl

        mark_setup_complete
        load_environment

        # Handle redeployment vs fresh deployment differently
        if [ "$is_redeployment" = true ]; then
            log_info "Preparing for redeployment (preserving data)..."
            # Build new images first while services are running (minimize downtime)
            log_info "Building new images while services are running..."
            clone_repositories
            build_images

            # Only stop services after images are built
            log_info "New images ready. Stopping services for quick restart..."
            stop_services
            sleep 5
            # NOTE: We do NOT clear database data during redeployment to preserve user data

            # Quick restart with new images
            start_services true  # Force restart
        else
            # For fresh deployments, ensure database is initialized
            log_info "Preparing fresh deployment..."
            ensure_database_initialized
            clone_repositories
            build_images
            start_services false  # Normal start
        fi

        log_info "Waiting for services to stabilize before database initialization..."
        sleep 10
        wait_for_services_ready
        init_users_database
        setup_timescaledb
        mark_deploy_complete
        show_status
        ;;
    "redeploy")
        log_info "Starting forced redeployment for $DEPLOY_ENV environment..."
        log_info "Using environment file: $ENV_FILE"
        log_info "Using compose file: $COMPOSE_FILE"

        # Force redeployment without asking
        log_info "Forcing clean redeployment..."

        check_prerequisites
        install_dependencies
        setup_storage
        configure_firewall
        setup_ssl

        log_info "Preparing for clean redeployment (preserving data)..."
        load_environment

        mark_setup_complete

        # Build new images first while services are still running (minimize downtime)
        log_info "Building new images while services are running..."
        clone_repositories
        build_images

        # Only stop services after images are built
        log_info "New images ready. Stopping services for quick restart..."
        stop_services
        sleep 5

        # Quick restart with new images (minimal downtime)
        log_info "Starting services with new images..."
        start_services true  # Force restart

        log_info "Waiting for services to stabilize before database initialization..."
        sleep 10
        wait_for_services_ready
        init_users_database
        setup_timescaledb
        mark_deploy_complete
        show_status
        ;;
    "reset-deploy")
        log_warning "Starting DESTRUCTIVE redeployment for $DEPLOY_ENV environment..."
        log_warning "This will DELETE ALL DATABASE DATA and reset the system!"
        log_info "Using environment file: $ENV_FILE"
        log_info "Using compose file: $COMPOSE_FILE"

        # Confirm destructive action
        read -p "Are you sure you want to RESET ALL DATA? This cannot be undone! (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Reset deployment cancelled. Use 'redeploy' for safe redeployment."
            exit 0
        fi

        log_warning "Proceeding with destructive reset deployment..."

        check_prerequisites
        install_dependencies
        setup_storage
        configure_firewall
        setup_ssl

        log_info "Preparing for reset deployment (clearing all data)..."
        load_environment
        # Stop services first to avoid conflicts
        stop_services
        sleep 5
        # Clear database data for fresh start
        ensure_database_initialized

        mark_setup_complete
        clone_repositories
        build_images

        # Force restart for clean state
        log_info "Starting services with clean restart..."
        start_services true  # Force restart

        log_info "Waiting for services to stabilize before database initialization..."
        sleep 10
        wait_for_services_ready
        init_users_database
        setup_timescaledb
        mark_deploy_complete
        show_status
        ;;
    "setup")
        log_info "Starting system setup for $DEPLOY_ENV environment..."

        # Check if setup was already completed
        if is_setup_complete; then
            log_info "Setup appears to be complete."
            read -p "Do you want to run setup again? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Skipping setup. Use specific commands for individual setup tasks."
                exit 0
            fi
            log_info "Proceeding with setup..."
        fi

        check_prerequisites
        install_dependencies
        setup_storage
        configure_firewall
        setup_ssl
        mark_setup_complete
        ;;
    "install-buildx")
        install_buildx
        ;;
    "start")
        load_environment
        start_services
        show_status
        ;;
    "stop")
        load_environment
        stop_services
        ;;
    "restart")
        load_environment
        stop_services
        start_services
        show_status
        ;;
    "wait-ready")
        load_environment
        wait_for_services_ready
        ;;
    "status")
        load_environment
        show_status
        ;;
    "check-state")
        check_system_state
        ;;
    "build")
        check_prerequisites
        load_environment
        clone_repositories
        build_images
        ;;
    "build-backend")
        check_prerequisites
        load_environment
        clone_repositories
        build_backend_image
        ;;
    "build-frontend")
        check_prerequisites
        load_environment
        clone_repositories
        build_frontend_image
        ;;
    "init-db")
        load_environment
        init_users_database
        ;;
    "db-connect")
        db_connect
        ;;
    "db-shell")
        db_shell
        ;;
    "db-backup")
        db_backup
        ;;
    "db-restore")
        db_restore "$2"
        ;;
    "ssl-setup")
        setup_ssl
        ;;
    "firewall-setup")
        configure_firewall
        ;;
    "timescaledb-setup")
        setup_timescaledb
        ;;
    "optimize-timescaledb")
        optimize_timescaledb
        ;;
    "weekly-maintenance")
        weekly_maintenance
        ;;
    "timescaledb-status")
        timescaledb_status
        ;;
    "reset-db")
        reset_database
        ;;
    "fix-docker-perms")
        fix_docker_permissions
        ;;
    "reset-state")
        reset_state
        ;;
    "health")
        if [ -f "$PROJECT_DIR/99-templates-examples/health-check.sh" ]; then
            "$PROJECT_DIR/99-templates-examples/health-check.sh"
        else
            log_error "Health check script not found"
            exit 1
        fi
        ;;
    "backup")
        if [ -f "$PROJECT_DIR/09-scripts-adaptation/daily-backup.sh" ]; then
            "$PROJECT_DIR/09-scripts-adaptation/daily-backup.sh"
        else
            log_error "Backup script not found"
            exit 1
        fi
        ;;
    "troubleshoot")
        load_environment
        troubleshoot_deployment
        ;;
    "help"|"--help"|"-h")
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
