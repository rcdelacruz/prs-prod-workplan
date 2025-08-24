#!/bin/bash

# PRS On-Premises Production Deployment Script
# Adapted from EC2 deploy-ec2.sh for on-premises infrastructure
# Optimized for 16GB RAM, 100 concurrent users, dual storage (SSD/HDD)

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
    if [ -d "/mnt/ssd" ] && [ -d "/mnt/hdd" ]; then
        echo "  ✓ Storage mounts available"
    else
        echo "  ✗ Storage mounts not available"
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
        local template_file="$PROJECT_DIR/02-docker-configuration/.env.example"
        if [ -f "$template_file" ]; then
            log_info "You can copy from template: cp $template_file $ENV_FILE"
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

    # Check storage mounts
    if [ ! -d "/mnt/ssd" ]; then
        log_error "SSD mount point /mnt/ssd not found"
        exit 1
    fi

    if [ ! -d "/mnt/hdd" ]; then
        log_error "HDD mount point /mnt/hdd not found"
        exit 1
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

    # Define directory arrays
    local ssd_dirs=(postgresql-data postgresql-hot redis-data uploads logs nginx-cache prometheus-data grafana-data portainer-data)
    local hdd_dirs=(postgresql-cold backups archives logs-archive postgres-wal-archive postgres-backups redis-backups app-logs-archive worker-logs-archive prometheus-archive)

    # Create SSD directories (idempotent)
    local ssd_created=false
    for dir in "${ssd_dirs[@]}"; do
        if [ ! -d "/mnt/ssd/$dir" ]; then
            sudo mkdir -p "/mnt/ssd/$dir"
            ssd_created=true
        fi
    done

    if [ "$ssd_created" = true ]; then
        log_info "Created missing SSD directories"
    else
        log_info "All SSD directories already exist"
    fi

    # Create HDD directories (idempotent)
    local hdd_created=false
    for dir in "${hdd_dirs[@]}"; do
        if [ ! -d "/mnt/hdd/$dir" ]; then
            sudo mkdir -p "/mnt/hdd/$dir"
            hdd_created=true
        fi
    done

    if [ "$hdd_created" = true ]; then
        log_info "Created missing HDD directories"
    else
        log_info "All HDD directories already exist"
    fi

    # Set ownership (idempotent - only change if needed)
    local ownership_changed=false
    for mount_point in /mnt/ssd /mnt/hdd; do
        if [ -d "$mount_point" ]; then
            current_owner=$(stat -c '%U:%G' "$mount_point")
            if [ "$current_owner" != "$USER:$USER" ]; then
                sudo chown -R $USER:$USER "$mount_point"
                ownership_changed=true
            fi
        fi
    done

    if [ "$ownership_changed" = true ]; then
        log_info "Updated directory ownership"
    else
        log_info "Directory ownership is already correct"
    fi

    # Set permissions (idempotent)
    chmod -R 755 /mnt/ssd /mnt/hdd 2>/dev/null || true

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
        # Check if our specific rules exist
        local required_rules=(
            "80.*192.168.0.0/20.*ALLOW IN.*HTTP"
            "443.*192.168.0.0/20.*ALLOW IN.*HTTPS"
            "8080.*192.168.0.0/20.*ALLOW IN.*Adminer"
            "3001.*192.168.0.0/20.*ALLOW IN.*Grafana"
            "9000.*192.168.0.0/20.*ALLOW IN.*Portainer"
            "9090.*192.168.0.0/20.*ALLOW IN.*Prometheus"
        )

        local ufw_status=$(sudo ufw status)
        for rule in "${required_rules[@]}"; do
            if ! echo "$ufw_status" | grep -q "$rule"; then
                needs_config=true
                log_info "Missing firewall rule, will reconfigure"
                break
            fi
        done

        if [ "$needs_config" = false ]; then
            log_info "Firewall is already properly configured"
            return 0
        fi
    fi

    # Configure firewall if needed
    if [ "$needs_config" = true ]; then
        log_info "Configuring firewall rules..."

        # Reset and set defaults
        sudo ufw --force reset
        sudo ufw default deny incoming
        sudo ufw default allow outgoing

        # Allow internal network access to services
        sudo ufw allow from 192.168.0.0/20 to any port 80 comment "HTTP"
        sudo ufw allow from 192.168.0.0/20 to any port 443 comment "HTTPS"
        sudo ufw allow from 192.168.0.0/20 to any port 8080 comment "Adminer"
        sudo ufw allow from 192.168.0.0/20 to any port 3001 comment "Grafana"
        sudo ufw allow from 192.168.0.0/20 to any port 9000 comment "Portainer"
        sudo ufw allow from 192.168.0.0/20 to any port 9090 comment "Prometheus"

        # Allow SSH from IT network only
        # sudo ufw allow from 192.168.1.0/24 to any port 22 comment "SSH IT"

        # Rate limiting for HTTP/HTTPS
        sudo ufw limit 80/tcp
        sudo ufw limit 443/tcp

        # Enable firewall
        sudo ufw --force enable

        # Enable SSH
        sudo ufw allow ssh

        log_success "Firewall configured"
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

# Function to reset database if password mismatch
reset_database() {
    log_info "Resetting database due to password mismatch..."

    # Stop database container
    cd "$PROJECT_DIR/02-docker-configuration"
    docker compose -f docker-compose.onprem.yml down postgres

    # Remove database volume
    docker volume rm 02-docker-configuration_database_data 2>/dev/null || true

    # Clean any potential data directories
    sudo rm -rf /mnt/ssd/postgresql-hot/* 2>/dev/null || true
    sudo rm -rf /mnt/hdd/postgresql-cold/* 2>/dev/null || true

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
    sudo rm -rf /mnt/ssd/postgresql-data/* 2>/dev/null || true

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
        log_info "Please copy .env.onprem.example to .env and configure it"
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

            # echo $DOCKER_CMD build --no-cache --platform linux/arm64 -f "$REPO_BASE_DIR/$BACKEND_DIR_NAME/$dockerfile_path" -t "$backend_tag" "$REPO_BASE_DIR/$BACKEND_DIR_NAME"

            if $DOCKER_CMD build --no-cache --platform linux/arm64 -f "$REPO_BASE_DIR/$BACKEND_DIR_NAME/$dockerfile_path" -t "$backend_tag" "$REPO_BASE_DIR/$BACKEND_DIR_NAME"; then
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

                # Add build arguments if they exist in environment
                if [ -n "${VITE_APP_API_URL:-}" ]; then
                    build_args="$build_args --build-arg VITE_APP_API_URL=$VITE_APP_API_URL"
                fi
                if [ -n "${VITE_APP_UPLOAD_URL:-}" ]; then
                    build_args="$build_args --build-arg VITE_APP_UPLOAD_URL=$VITE_APP_UPLOAD_URL"
                fi
                if [ -n "${VITE_APP_ENVIRONMENT:-}" ]; then
                    build_args="$build_args --build-arg VITE_APP_ENVIRONMENT=$VITE_APP_ENVIRONMENT"
                else
                    build_args="$build_args --build-arg VITE_APP_ENVIRONMENT=$DEPLOY_ENV"
                fi
                if [ -n "${VITE_APP_ENABLE_DEVTOOLS:-}" ]; then
                    build_args="$build_args --build-arg VITE_APP_ENABLE_DEVTOOLS=$VITE_APP_ENABLE_DEVTOOLS"
                fi
            fi

            if $DOCKER_CMD build  --no-cache --platform linux/arm64-f "$REPO_BASE_DIR/$BACKEND_DIR_NAME/$frontend_dockerfile" $build_args -t "$frontend_tag" "$REPO_BASE_DIR/$FRONTEND_DIR_NAME"; then
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

# Start services
start_services() {
    log_info "Starting services for $DEPLOY_ENV environment..."

    cd "$PROJECT_DIR/02-docker-configuration"

    # Check which services are already running
    local compose_file_name=$(basename "$COMPOSE_FILE")
    local running_services=$(docker compose -f "$compose_file_name" ps --services --filter "status=running" 2>/dev/null || true)

    # Start infrastructure services first
    if ! echo "$running_services" | grep -q "postgres\|redis"; then
        log_info "Starting database and cache services..."
        docker compose -f "$compose_file_name" up -d postgres redis

        # Wait for database to be ready
        log_info "Waiting for database to be ready..."
        sleep 30
    else
        log_info "Database and cache services are already running"
    fi

    # Start application services
    if ! echo "$running_services" | grep -q "backend\|redis-worker"; then
        log_info "Starting application services..."
        docker compose -f "$compose_file_name" up -d backend redis-worker

        # Wait for backend to be ready
        sleep 30
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

    # Check if database container is running
    if ! docker ps | grep -q "prs-onprem-postgres-timescale"; then
        log_error "PostgreSQL container is not running. Please start services first."
        exit 1
    fi

    # Check if backend container is running
    if ! docker ps | grep -q "prs-onprem-backend"; then
        log_error "Backend container is not running. Please start services first."
        exit 1
    fi

    # Wait for database to be ready
    log_info "Waiting for database connection..."
    timeout 60 bash -c 'until docker exec prs-onprem-postgres-timescale pg_isready -U prs_user >/dev/null 2>&1; do sleep 2; done'

    # Check if users table already exists and has data
    local user_count=$(docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='users';" 2>/dev/null | tr -d ' ' || echo "0")

    if [ "$user_count" -gt 0 ]; then
        local existing_users=$(docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$existing_users" -gt 0 ]; then
            log_info "Database already has $existing_users users, skipping initialization"
            return 0
        fi
    fi

    # # Create TimescaleDB extension (idempotent)
    # log_info "Creating TimescaleDB extension..."
    # docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "CREATE EXTENSION IF NOT EXISTS timescaledb;" >/dev/null 2>&1

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

    # Create backup directory if it doesn't exist (idempotent)
    if [ ! -d /mnt/hdd/postgres-backups ]; then
        mkdir -p /mnt/hdd/postgres-backups
        log_info "Created backup directory"
    fi

    # Generate backup filename with timestamp
    BACKUP_FILE="/mnt/hdd/postgres-backups/prs_production_$(date +%Y%m%d_%H%M%S).sql"

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
        log_error "Usage: $0 db-restore <backup_file>"
        log_info "Available backups:"
        ls -la /mnt/hdd/postgres-backups/
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

# Show service status
show_status() {
    log_info "Service Status for $DEPLOY_ENV environment:"
    cd "$PROJECT_DIR/02-docker-configuration"
    local compose_file_name=$(basename "$COMPOSE_FILE")
    docker compose -f "$compose_file_name" ps

    echo ""
    log_info "System Resources:"
    echo "Memory: $(free -h | grep Mem | awk '{print $3"/"$2}')"
    echo "SSD Usage: $(df -h /mnt/ssd | awk 'NR==2 {print $5}')"
    echo "HDD Usage: $(df -h /mnt/hdd | awk 'NR==2 {print $5}')"

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
    echo "Optimized for 16GB RAM, 100 concurrent users, dual storage"
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
    echo "  setup               Setup system (dependencies, storage, firewall) - idempotent"
    echo "  install-buildx      Install/fix Docker buildx plugin - idempotent"
    echo "  build               Build Docker images - idempotent (use FORCE_REBUILD=true to force)"
    echo "  start               Start services - idempotent"
    echo "  stop                Stop services"
    echo "  restart             Restart services"
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
    echo "  fix-docker-perms    Fix Docker permission issues - idempotent"
    echo "  reset-state         Reset deployment state flags"
    echo "  health              Run health check"
    echo "  backup              Run backup"
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
    echo ""
    echo "Examples:"
    echo "  $0 deploy                                    # Full deployment with default repos (prod environment)"
    echo "  DEPLOY_ENV=dev $0 deploy                     # Deploy to development environment"
    echo "  DEPLOY_ENV=staging $0 deploy                 # Deploy to staging environment"
    echo "  $0 check-state                               # Check what has been completed"
    echo "  FORCE_REBUILD=true $0 build                  # Force rebuild of images"
    echo "  USE_FALLBACK_DOCKERFILE=true $0 build        # Use Debian-based Dockerfile if Alpine fails"
    echo "  DEPLOY_ENV=dev BACKEND_REPO_URL=https://github.com/user/my-backend.git $0 deploy"
    echo "  DEPLOY_ENV=staging $0 status                 # Check staging environment status"
    echo "  DEPLOY_ENV=prod $0 restart                   # Restart production services"
    echo "  $0 db-connect                                # Connect to database"
    echo "  $0 db-backup                                 # Create database backup"
    echo "  $0 db-restore /mnt/hdd/postgres-backups/backup.sql.gz"
}

# Main script logic
case "${1:-deploy}" in
    "deploy")
        log_info "Starting full deployment for $DEPLOY_ENV environment..."
        log_info "Using environment file: $ENV_FILE"
        log_info "Using compose file: $COMPOSE_FILE"

        # Check if deployment was already completed
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
        fi

        check_prerequisites
        install_dependencies
        setup_storage
        configure_firewall
        setup_ssl
        ensure_database_initialized
        mark_setup_complete
        load_environment
        clone_repositories
        build_images
        start_services
        sleep 20
        init_users_database
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
    "help"|"--help"|"-h")
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
