#!/bin/bash

# PRS On-Premises Production Deployment Script
# Adapted from EC2 deploy-ec2.sh for on-premises infrastructure
# Optimized for 16GB RAM, 100 concurrent users, dual storage (SSD/HDD)

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/02-docker-configuration/.env"
COMPOSE_FILE="$PROJECT_DIR/02-docker-configuration/docker-compose.onprem.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
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
    if ! ping -c 1 192.168.1.1 >/dev/null 2>&1; then
        log_warning "Cannot reach internal gateway 192.168.1.1"
    fi
    
    log_success "Prerequisites check passed"
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."
    
    sudo apt update
    sudo apt install -y \
        docker.io \
        docker-compose-v2 \
        curl \
        wget \
        git \
        htop \
        iotop \
        nethogs \
        tree \
        unzip \
        apache2-utils \
        certbot \
        ufw
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    # Enable and start Docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    log_success "Dependencies installed"
}

# Setup storage directories
setup_storage() {
    log_info "Setting up storage directories..."
    
    # Create SSD directories
    sudo mkdir -p /mnt/ssd/{postgresql-data,postgresql-hot,redis-data,uploads,logs,nginx-cache,prometheus-data,grafana-data,portainer-data}
    
    # Create HDD directories
    sudo mkdir -p /mnt/hdd/{postgresql-cold,backups,archives,logs-archive,postgres-wal-archive,postgres-backups,redis-backups,app-logs-archive,worker-logs-archive,prometheus-archive}
    
    # Set ownership
    sudo chown -R $USER:$USER /mnt/ssd /mnt/hdd
    
    # Set permissions
    chmod -R 755 /mnt/ssd /mnt/hdd
    
    log_success "Storage directories created"
}

# Configure firewall
configure_firewall() {
    log_info "Configuring firewall..."
    
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
    sudo ufw allow from 192.168.1.0/24 to any port 22 comment "SSH IT"
    
    # Rate limiting for HTTP/HTTPS
    sudo ufw limit 80/tcp
    sudo ufw limit 443/tcp
    
    # Enable firewall
    sudo ufw --force enable
    
    log_success "Firewall configured"
}

# Setup SSL certificates
setup_ssl() {
    log_info "Setting up SSL certificates..."
    
    # Create SSL directory
    mkdir -p "$PROJECT_DIR/02-docker-configuration/ssl"
    
    # Generate self-signed certificate for initial setup
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$PROJECT_DIR/02-docker-configuration/ssl/server.key" \
        -out "$PROJECT_DIR/02-docker-configuration/ssl/server.crt" \
        -subj "/C=PH/ST=Metro Manila/L=Manila/O=Client Organization/CN=prs.client-domain.com"
    
    # Generate DH parameters
    openssl dhparam -out "$PROJECT_DIR/02-docker-configuration/ssl/dhparam.pem" 2048
    
    # Set proper permissions
    chmod 600 "$PROJECT_DIR/02-docker-configuration/ssl/server.key"
    chmod 644 "$PROJECT_DIR/02-docker-configuration/ssl/server.crt"
    chmod 644 "$PROJECT_DIR/02-docker-configuration/ssl/dhparam.pem"
    
    log_success "SSL certificates generated"
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
}

# Clone repositories
clone_repositories() {
    log_info "Cloning application repositories..."
    
    # Create repositories directory
    sudo mkdir -p /opt/prs
    sudo chown $USER:$USER /opt/prs
    
    # Clone backend repository
    if [ ! -d "/opt/prs/prs-backend-a" ]; then
        git clone https://github.com/rcdelacruz/prs-backend-a.git /opt/prs/prs-backend-a
        log_success "Backend repository cloned"
    else
        log_info "Backend repository already exists"
        cd /opt/prs/prs-backend-a
        git pull origin main
    fi
    
    # Clone frontend repository
    if [ ! -d "/opt/prs/prs-frontend-a" ]; then
        git clone https://github.com/rcdelacruz/prs-frontend-a.git /opt/prs/prs-frontend-a
        log_success "Frontend repository cloned"
    else
        log_info "Frontend repository already exists"
        cd /opt/prs/prs-frontend-a
        git pull origin main
    fi
}

# Build Docker images
build_images() {
    log_info "Building Docker images..."
    
    # Build backend image
    log_info "Building backend image..."
    docker build -t prs-backend:latest /opt/prs/prs-backend-a
    
    # Build frontend image
    log_info "Building frontend image..."
    docker build -t prs-frontend:latest /opt/prs/prs-frontend-a
    
    log_success "Docker images built successfully"
}

# Start services
start_services() {
    log_info "Starting services..."
    
    cd "$PROJECT_DIR/02-docker-configuration"
    
    # Start infrastructure services first
    log_info "Starting database and cache services..."
    docker compose -f docker-compose.onprem.yml up -d postgres redis
    
    # Wait for database to be ready
    log_info "Waiting for database to be ready..."
    sleep 30
    
    # Start application services
    log_info "Starting application services..."
    docker compose -f docker-compose.onprem.yml up -d backend redis-worker
    
    # Wait for backend to be ready
    sleep 30
    
    # Start web services
    log_info "Starting web services..."
    docker compose -f docker-compose.onprem.yml up -d frontend nginx
    
    # Start monitoring services
    log_info "Starting monitoring services..."
    docker compose -f docker-compose.onprem.yml --profile monitoring up -d
    
    # Start management tools
    log_info "Starting management tools..."
    docker compose -f docker-compose.onprem.yml up -d adminer portainer
    
    log_success "All services started"
}

# Stop services
stop_services() {
    log_info "Stopping services..."
    
    cd "$PROJECT_DIR/02-docker-configuration"
    docker compose -f docker-compose.onprem.yml down
    
    log_success "All services stopped"
}

# Initialize database
init_database() {
    log_info "Initializing database..."
    
    cd "$PROJECT_DIR/02-docker-configuration"
    
    # Wait for database to be ready
    log_info "Waiting for database connection..."
    timeout 60 bash -c 'until docker exec prs-onprem-postgres-timescale pg_isready -U prs_user; do sleep 2; done'
    
    # Create TimescaleDB extension
    docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
    
    # Run migrations
    log_info "Running database migrations..."
    docker exec prs-onprem-backend npm run migrate
    
    # Create admin user
    log_info "Creating admin user..."
    docker exec prs-onprem-backend npm run seed:admin
    
    log_success "Database initialized"
}

# Show service status
show_status() {
    log_info "Service Status:"
    cd "$PROJECT_DIR/02-docker-configuration"
    docker compose -f docker-compose.onprem.yml ps
    
    echo ""
    log_info "System Resources:"
    echo "Memory: $(free -h | grep Mem | awk '{print $3"/"$2}')"
    echo "SSD Usage: $(df -h /mnt/ssd | awk 'NR==2 {print $5}')"
    echo "HDD Usage: $(df -h /mnt/hdd | awk 'NR==2 {print $5}')"
    
    echo ""
    log_info "Service URLs:"
    echo "Application: https://192.168.16.100/"
    echo "Grafana: http://192.168.16.100:3001/"
    echo "Prometheus: http://192.168.16.100:9090/"
    echo "Adminer: http://192.168.16.100:8080/"
    echo "Portainer: http://192.168.16.100:9000/"
}

# Show usage information
show_usage() {
    echo "PRS On-Premises Production Deployment Script"
    echo "Adapted from EC2 setup for on-premises infrastructure"
    echo "Optimized for 16GB RAM, 100 concurrent users, dual storage"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  deploy              Full deployment (install, build, start, init)"
    echo "  start               Start services"
    echo "  stop                Stop services"
    echo "  restart             Restart services"
    echo "  status              Show service status and resource usage"
    echo "  build               Build Docker images"
    echo "  init-db             Initialize database"
    echo "  setup               Setup system (dependencies, storage, firewall)"
    echo "  ssl-setup           Setup SSL certificates"
    echo "  health              Run health check"
    echo "  backup              Run backup"
    echo "  help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy           # Full deployment"
    echo "  $0 status           # Check status"
    echo "  $0 restart          # Restart all services"
}

# Main script logic
case "${1:-deploy}" in
    "deploy")
        check_prerequisites
        install_dependencies
        setup_storage
        configure_firewall
        setup_ssl
        load_environment
        clone_repositories
        build_images
        start_services
        sleep 20
        init_database
        show_status
        ;;
    "setup")
        check_prerequisites
        install_dependencies
        setup_storage
        configure_firewall
        setup_ssl
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
    "build")
        check_prerequisites
        load_environment
        clone_repositories
        build_images
        ;;
    "init-db")
        load_environment
        init_database
        ;;
    "ssl-setup")
        setup_ssl
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
