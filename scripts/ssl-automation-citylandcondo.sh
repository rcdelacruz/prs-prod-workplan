#!/bin/bash

# 🔐 SSL Automation Script for prs.citylandcondo.com
# Automated Let's Encrypt certificate generation and renewal
# Designed for GoDaddy hosting without API access

set -e

# Configuration
DOMAIN="prs.citylandcondo.com"
EMAIL="admin@citylandcondo.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SSL_DIR="$PROJECT_DIR/02-docker-configuration/ssl"
DOCKER_COMPOSE_FILE="$PROJECT_DIR/02-docker-configuration/docker-compose.onprem.yml"
LOG_FILE="/var/log/prs-ssl.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Print colored output
print_status() {
    echo -e "${BLUE}📡 $1${NC}"
    log "$1"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
    log "WARNING: $1"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    log "ERROR: $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    # Check if running as root or with sudo
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi

    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        print_status "Installing certbot..."
        apt update
        apt install -y certbot
        print_success "Certbot installed"
    else
        print_success "Certbot is already installed"
    fi

    # Check if Docker is running
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi

    # Create SSL directory if it doesn't exist
    mkdir -p "$SSL_DIR"

    # Create log file if it doesn't exist
    touch "$LOG_FILE"

    print_success "Prerequisites check completed"
}

# Function to prompt for port forwarding setup
setup_port_forwarding() {
    print_warning "IMPORTANT: Port forwarding setup required"
    echo ""
    echo "To generate Let's Encrypt certificates, you need to temporarily configure"
    echo "your router/firewall to forward port 80 to this server."
    echo ""
    echo "Configuration needed:"
    echo "  External Port: 80"
    echo "  Internal IP: 192.168.0.100"
    echo "  Internal Port: 80"
    echo "  Protocol: TCP"
    echo ""
    echo "Steps:"
    echo "1. Log into your router/firewall admin panel"
    echo "2. Navigate to Port Forwarding or NAT settings"
    echo "3. Add the rule above"
    echo "4. Save and apply the configuration"
    echo ""
    read -p "Press Enter when port forwarding is configured and active..."
    print_success "Port forwarding confirmed"
}

# Function to remove port forwarding
remove_port_forwarding() {
    print_warning "SECURITY: Remove port forwarding"
    echo ""
    echo "For security, please remove the port 80 forwarding rule"
    echo "from your router/firewall now that certificate generation is complete."
    echo ""
    echo "Steps:"
    echo "1. Log into your router/firewall admin panel"
    echo "2. Navigate to Port Forwarding or NAT settings"
    echo "3. Delete or disable the port 80 forwarding rule"
    echo "4. Save and apply the configuration"
    echo ""
    read -p "Press Enter when port forwarding has been removed..."
    print_success "Port forwarding removal confirmed"
}

# Function to stop nginx temporarily
stop_nginx() {
    print_status "Stopping nginx temporarily for certificate generation..."

    if docker compose -f "$DOCKER_COMPOSE_FILE" ps nginx | grep -q "Up"; then
        docker compose -f "$DOCKER_COMPOSE_FILE" stop nginx
        print_success "Nginx stopped"
        return 0
    else
        print_warning "Nginx was not running"
        return 1
    fi
}

# Function to start nginx
start_nginx() {
    print_status "Starting nginx..."
    docker compose -f "$DOCKER_COMPOSE_FILE" start nginx

    # Wait for nginx to be ready
    sleep 5

    if docker compose -f "$DOCKER_COMPOSE_FILE" ps nginx | grep -q "Up"; then
        print_success "Nginx started successfully"
    else
        print_error "Failed to start nginx"
        return 1
    fi
}

# Function to generate certificate
generate_certificate() {
    print_status "Generating Let's Encrypt certificate for $DOMAIN..."

    # Check if certificate already exists and is valid
    if [ -f "$SSL_DIR/server.crt" ]; then
        if openssl x509 -checkend 2592000 -noout -in "$SSL_DIR/server.crt" 2>/dev/null; then
            print_warning "Valid certificate already exists (expires in >30 days)"
            read -p "Do you want to renew anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_status "Skipping certificate generation"
                return 0
            fi
        fi
    fi

    # Generate certificate using standalone mode
    if certbot certonly --standalone \
        -d "$DOMAIN" \
        --email "$EMAIL" \
        --agree-tos \
        --non-interactive \
        --preferred-challenges http \
        --force-renewal; then

        print_success "Certificate generated successfully"

        # Copy certificates to SSL directory
        cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$SSL_DIR/server.crt"
        cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$SSL_DIR/server.key"

        # Set proper permissions
        chmod 644 "$SSL_DIR/server.crt"
        chmod 600 "$SSL_DIR/server.key"

        # Generate DH parameters if not exists
        if [ ! -f "$SSL_DIR/dhparam.pem" ]; then
            print_status "Generating DH parameters (this may take a few minutes)..."
            openssl dhparam -out "$SSL_DIR/dhparam.pem" 2048
            chmod 644 "$SSL_DIR/dhparam.pem"
            print_success "DH parameters generated"
        fi

        print_success "Certificates copied and configured"
        return 0
    else
        print_error "Certificate generation failed"
        return 1
    fi
}

# Function to validate certificate
validate_certificate() {
    print_status "Validating certificate..."

    if [ ! -f "$SSL_DIR/server.crt" ]; then
        print_error "Certificate file not found"
        return 1
    fi

    # Check certificate validity
    if openssl x509 -noout -in "$SSL_DIR/server.crt" 2>/dev/null; then
        EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$SSL_DIR/server.crt" | cut -d= -f2)
        SUBJECT=$(openssl x509 -subject -noout -in "$SSL_DIR/server.crt" | sed 's/subject=//')

        print_success "Certificate is valid"
        echo "  Subject: $SUBJECT"
        echo "  Expires: $EXPIRY_DATE"

        # Check if certificate matches domain
        if openssl x509 -noout -in "$SSL_DIR/server.crt" -text | grep -q "$DOMAIN"; then
            print_success "Certificate matches domain $DOMAIN"
        else
            print_warning "Certificate may not match domain $DOMAIN"
        fi

        return 0
    else
        print_error "Certificate is invalid or corrupted"
        return 1
    fi
}

# Function to test HTTPS connectivity
test_https() {
    print_status "Testing HTTPS connectivity..."

    # Wait for nginx to be fully ready
    sleep 10

    # Test internal connectivity
    if curl -k -s "https://192.168.0.100/health" | grep -q "healthy"; then
        print_success "Internal HTTPS connectivity working"
    else
        print_warning "Internal HTTPS connectivity test failed"
    fi

    # Test domain connectivity (if accessible)
    if curl -s --connect-timeout 10 "https://$DOMAIN/health" | grep -q "healthy"; then
        print_success "Domain HTTPS connectivity working"
    else
        print_warning "Domain HTTPS connectivity test failed (may be normal if not publicly accessible)"
    fi
}

# Main execution function
main() {
    echo ""
    echo "🔐 SSL Automation for prs.citylandcondo.com"
    echo "=============================================="
    echo ""

    # Check prerequisites
    check_prerequisites

    # Setup port forwarding
    setup_port_forwarding

    # Stop nginx
    NGINX_WAS_RUNNING=false
    if stop_nginx; then
        NGINX_WAS_RUNNING=true
    fi

    # Generate certificate
    if generate_certificate; then
        # Start nginx
        if [ "$NGINX_WAS_RUNNING" = true ]; then
            start_nginx
        fi

        # Remove port forwarding
        remove_port_forwarding

        # Validate certificate
        validate_certificate

        # Test HTTPS
        test_https

        print_success "SSL automation completed successfully!"
        echo ""
        echo "🎉 Your domain $DOMAIN is now secured with Let's Encrypt SSL!"
        echo ""
        echo "Next steps:"
        echo "1. Update your nginx configuration to use the domain name"
        echo "2. Set up automated renewal monitoring"
        echo "3. Test access from client machines"

    else
        print_error "SSL automation failed"

        # Start nginx even if certificate generation failed
        if [ "$NGINX_WAS_RUNNING" = true ]; then
            start_nginx
        fi

        remove_port_forwarding
        exit 1
    fi
}

# Script entry point
case "${1:-main}" in
    "main"|"")
        main
        ;;
    "check")
        check_prerequisites
        validate_certificate
        ;;
    "renew")
        check_prerequisites
        setup_port_forwarding
        NGINX_WAS_RUNNING=false
        if stop_nginx; then
            NGINX_WAS_RUNNING=true
        fi
        generate_certificate
        if [ "$NGINX_WAS_RUNNING" = true ]; then
            start_nginx
        fi
        remove_port_forwarding
        validate_certificate
        ;;
    "validate")
        validate_certificate
        ;;
    "test")
        test_https
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  main (default) - Full SSL setup process"
        echo "  check          - Check prerequisites and validate existing certificate"
        echo "  renew          - Renew existing certificate"
        echo "  validate       - Validate certificate only"
        echo "  test           - Test HTTPS connectivity"
        echo "  help           - Show this help message"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
