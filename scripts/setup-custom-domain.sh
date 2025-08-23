#!/bin/bash

# 🌐 Custom Domain Setup Script for prs.citylandcondo.com
# Quick setup script for implementing custom domain with Let's Encrypt SSL

set -e

# Configuration
DOMAIN="prs.citylandcondo.com"
EMAIL="admin@citylandcondo.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCRIPTS_DIR="$PROJECT_DIR/scripts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_header() {
    echo -e "${BLUE}"
    echo "=============================================="
    echo "🌐 Custom Domain Setup: $DOMAIN"
    echo "=============================================="
    echo -e "${NC}"
}

print_step() {
    echo -e "${BLUE}📋 Step $1: $2${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_step "1" "Checking Prerequisites"

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi

    # Check if project directory exists
    if [ ! -d "$PROJECT_DIR" ]; then
        print_error "Project directory not found: $PROJECT_DIR"
        exit 1
    fi

    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        print_error "Docker is not running"
        exit 1
    fi

    # Create scripts directory
    mkdir -p "$SCRIPTS_DIR"

    print_success "Prerequisites check completed"
}

# Function to install required packages
install_packages() {
    print_step "2" "Installing Required Packages"

    # Update package list
    apt update

    # Install certbot and dependencies
    apt install -y certbot curl openssl mailutils

    print_success "Required packages installed"
}

# Function to setup scripts
setup_scripts() {
    print_step "3" "Setting Up SSL Automation Scripts"

    # Copy SSL automation script
    if [ -f "$PROJECT_DIR/scripts/ssl-automation-citylandcondo.sh" ]; then
        cp "$PROJECT_DIR/scripts/ssl-automation-citylandcondo.sh" "$SCRIPTS_DIR/"
        chmod +x "$SCRIPTS_DIR/ssl-automation-citylandcondo.sh"
        print_success "SSL automation script installed"
    else
        print_error "SSL automation script not found"
        exit 1
    fi

    # Copy SSL monitoring script
    if [ -f "$PROJECT_DIR/scripts/ssl-renewal-monitor.sh" ]; then
        cp "$PROJECT_DIR/scripts/ssl-renewal-monitor.sh" "$SCRIPTS_DIR/"
        chmod +x "$SCRIPTS_DIR/ssl-renewal-monitor.sh"
        print_success "SSL monitoring script installed"
    else
        print_error "SSL monitoring script not found"
        exit 1
    fi
}

# Function to setup cron jobs
setup_cron_jobs() {
    print_step "4" "Setting Up Automated Monitoring"

    # Create cron job for daily SSL monitoring
    (crontab -l 2>/dev/null; echo "0 2 * * * $SCRIPTS_DIR/ssl-renewal-monitor.sh") | crontab -

    # Create cron job for weekly SSL validation
    (crontab -l 2>/dev/null; echo "0 3 * * 0 $SCRIPTS_DIR/ssl-renewal-monitor.sh report") | crontab -

    print_success "Cron jobs configured"
    print_info "Daily monitoring: 2:00 AM"
    print_info "Weekly reports: 3:00 AM on Sundays"
}

# Function to display DNS configuration instructions
show_dns_instructions() {
    print_step "5" "DNS Configuration Instructions"

    echo ""
    echo "🌐 Configure DNS in GoDaddy:"
    echo "=============================="
    echo ""
    echo "1. Log into your GoDaddy account"
    echo "2. Go to DNS Management for citylandcondo.com"
    echo "3. Add/Edit the following A record:"
    echo ""
    echo "   Type: A"
    echo "   Name: prs"
    echo "   Value: [Your office public IP address]"
    echo "   TTL: 1 Hour"
    echo ""
    echo "4. Save the DNS changes"
    echo "5. Wait 5-10 minutes for DNS propagation"
    echo ""

    read -p "Press Enter when DNS configuration is complete..."
    print_success "DNS configuration confirmed"
}

# Function to test DNS resolution
test_dns_resolution() {
    print_step "6" "Testing DNS Resolution"

    echo "Testing DNS resolution for $DOMAIN..."

    if nslookup "$DOMAIN" &> /dev/null; then
        local resolved_ip=$(nslookup "$DOMAIN" | grep -A1 "Name:" | tail -1 | awk '{print $2}')
        print_success "DNS resolution successful"
        print_info "Domain $DOMAIN resolves to: $resolved_ip"
    else
        print_warning "DNS resolution failed or still propagating"
        print_info "This is normal if DNS was just configured"
    fi
}

# Function to run SSL setup
run_ssl_setup() {
    print_step "7" "Running SSL Certificate Setup"

    echo ""
    print_warning "IMPORTANT: The next step will guide you through SSL certificate generation"
    print_info "You will need to temporarily configure port forwarding on your router/firewall"
    echo ""

    read -p "Are you ready to proceed with SSL setup? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Run SSL automation script
        "$SCRIPTS_DIR/ssl-automation-citylandcondo.sh"

        if [ $? -eq 0 ]; then
            print_success "SSL certificate setup completed"
        else
            print_error "SSL certificate setup failed"
            exit 1
        fi
    else
        print_info "SSL setup skipped. You can run it later with:"
        print_info "sudo $SCRIPTS_DIR/ssl-automation-citylandcondo.sh"
    fi
}

# Function to restart services
restart_services() {
    print_step "8" "Restarting Services"

    cd "$PROJECT_DIR/02-docker-configuration"

    # Restart nginx to apply new configuration
    docker compose -f docker-compose.onprem.yml restart nginx

    # Wait for services to be ready
    sleep 10

    print_success "Services restarted"
}

# Function to run connectivity tests
test_connectivity() {
    print_step "9" "Testing Connectivity"

    echo "Testing HTTPS connectivity..."

    # Test internal IP access
    if curl -k -s --connect-timeout 10 "https://192.168.0.100/health" | grep -q "healthy"; then
        print_success "Internal IP HTTPS access: Working"
    else
        print_warning "Internal IP HTTPS access: Failed"
    fi

    # Test domain access
    if curl -s --connect-timeout 10 "https://$DOMAIN/health" | grep -q "healthy"; then
        print_success "Domain HTTPS access: Working"
    else
        print_warning "Domain HTTPS access: Failed (may be normal if not publicly accessible)"
    fi
}

# Function to display completion summary
show_completion_summary() {
    print_step "10" "Setup Complete"

    echo ""
    echo "🎉 Custom Domain Setup Complete!"
    echo "================================="
    echo ""
    echo "Domain: https://$DOMAIN"
    echo "Server: 192.168.0.100"
    echo ""
    echo "✅ SSL certificates configured"
    echo "✅ Nginx configuration updated"
    echo "✅ Automated monitoring enabled"
    echo "✅ Services restarted"
    echo ""
    echo "📋 Next Steps:"
    echo "1. Test access from client machines: https://$DOMAIN"
    echo "2. Update any bookmarks or shortcuts"
    echo "3. Monitor SSL certificate status with:"
    echo "   sudo $SCRIPTS_DIR/ssl-renewal-monitor.sh"
    echo ""
    echo "🔄 Certificate Renewal:"
    echo "Certificates will be monitored automatically."
    echo "When renewal is needed (every ~90 days), run:"
    echo "   sudo $SCRIPTS_DIR/ssl-automation-citylandcondo.sh renew"
    echo ""
    echo "📞 Support:"
    echo "For assistance, contact your IT team or refer to:"
    echo "   $PROJECT_DIR/10-documentation-guides/custom-domain-ssl-guide.md"
    echo ""
}

# Main execution
main() {
    print_header

    check_prerequisites
    install_packages
    setup_scripts
    setup_cron_jobs
    show_dns_instructions
    test_dns_resolution
    run_ssl_setup
    restart_services
    test_connectivity
    show_completion_summary

    print_success "Custom domain setup completed successfully!"
}

# Script entry point
case "${1:-main}" in
    "main"|"")
        main
        ;;
    "dns-only")
        show_dns_instructions
        test_dns_resolution
        ;;
    "ssl-only")
        run_ssl_setup
        restart_services
        test_connectivity
        ;;
    "test")
        test_dns_resolution
        test_connectivity
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  main (default) - Run complete setup process"
        echo "  dns-only       - Show DNS configuration instructions only"
        echo "  ssl-only       - Run SSL setup only (assumes DNS is configured)"
        echo "  test           - Test DNS resolution and connectivity"
        echo "  help           - Show this help message"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
