#!/bin/bash

# 🔄 Upgrade Existing PRS System to Custom Domain SSL
# Safely upgrades from self-signed certificates to Let's Encrypt

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SSL_DIR="$PROJECT_DIR/02-docker-configuration/ssl"
BACKUP_DIR="$PROJECT_DIR/02-docker-configuration/ssl.backup"
DOCKER_COMPOSE_FILE="$PROJECT_DIR/02-docker-configuration/docker-compose.onprem.yml"

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
    echo "🔄 PRS SSL Upgrade: Self-Signed → Let's Encrypt"
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

# Function to analyze current setup
analyze_current_setup() {
    print_step "1" "Analyzing Current SSL Setup"
    
    if [ -f "$SSL_DIR/server.crt" ]; then
        echo "Current certificate details:"
        echo "----------------------------"
        
        # Get certificate subject
        local subject=$(openssl x509 -subject -noout -in "$SSL_DIR/server.crt" | sed 's/subject=//')
        echo "Subject: $subject"
        
        # Get certificate issuer
        local issuer=$(openssl x509 -issuer -noout -in "$SSL_DIR/server.crt" | sed 's/issuer=//')
        echo "Issuer: $issuer"
        
        # Get expiry date
        local expiry=$(openssl x509 -enddate -noout -in "$SSL_DIR/server.crt" | cut -d= -f2)
        echo "Expires: $expiry"
        
        # Check if self-signed
        if echo "$issuer" | grep -q "prs.client-domain.com"; then
            print_info "Current certificate is self-signed (as expected)"
        else
            print_warning "Current certificate may not be self-signed"
        fi
        
        print_success "Current SSL setup analyzed"
    else
        print_error "No SSL certificate found"
        return 1
    fi
}

# Function to backup current certificates
backup_current_certificates() {
    print_step "2" "Backing Up Current Certificates"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Copy all SSL files
    if cp -r "$SSL_DIR"/* "$BACKUP_DIR/" 2>/dev/null; then
        print_success "Certificates backed up to: $BACKUP_DIR"
        
        # List backup contents
        echo "Backup contents:"
        ls -la "$BACKUP_DIR/"
    else
        print_error "Failed to backup certificates"
        return 1
    fi
}

# Function to test current system
test_current_system() {
    print_step "3" "Testing Current System"
    
    # Test HTTPS access
    if curl -k -s --connect-timeout 10 "https://192.168.0.100/health" | grep -q "healthy"; then
        print_success "Current HTTPS access working"
    else
        print_error "Current HTTPS access not working"
        return 1
    fi
    
    # Check nginx status
    if docker ps | grep -q "prs-onprem-nginx"; then
        print_success "Nginx container running"
    else
        print_error "Nginx container not running"
        return 1
    fi
    
    # Test nginx configuration
    if docker exec prs-onprem-nginx nginx -t &> /dev/null; then
        print_success "Nginx configuration valid"
    else
        print_error "Nginx configuration invalid"
        return 1
    fi
}

# Function to prepare for upgrade
prepare_for_upgrade() {
    print_step "4" "Preparing for Upgrade"
    
    print_info "Before proceeding, ensure you have:"
    echo "1. ✅ DNS A record configured in GoDaddy"
    echo "2. ✅ Router/firewall admin access for port forwarding"
    echo "3. ✅ Maintenance window scheduled (10-15 minutes)"
    echo ""
    
    read -p "Have you completed the DNS configuration in GoDaddy? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Please configure DNS first:"
        echo "  Type: A"
        echo "  Name: prs"
        echo "  Value: [Your office public IP]"
        echo "  TTL: 1 Hour"
        echo ""
        echo "Then run this script again."
        exit 1
    fi
    
    print_success "Prerequisites confirmed"
}

# Function to run the upgrade
run_upgrade() {
    print_step "5" "Running SSL Upgrade"
    
    print_info "Starting custom domain setup..."
    
    # Run the custom domain setup script
    if "$SCRIPT_DIR/setup-custom-domain.sh" ssl-only; then
        print_success "SSL upgrade completed successfully"
    else
        print_error "SSL upgrade failed"
        
        print_warning "Attempting to restore backup..."
        restore_backup
        return 1
    fi
}

# Function to restore backup if needed
restore_backup() {
    print_warning "Restoring backup certificates..."
    
    if [ -d "$BACKUP_DIR" ]; then
        # Stop nginx temporarily
        docker compose -f "$DOCKER_COMPOSE_FILE" stop nginx
        
        # Restore certificates
        cp -r "$BACKUP_DIR"/* "$SSL_DIR/"
        
        # Restart nginx
        docker compose -f "$DOCKER_COMPOSE_FILE" start nginx
        
        print_success "Backup restored successfully"
        print_info "System restored to previous working state"
    else
        print_error "No backup found to restore"
    fi
}

# Function to verify upgrade
verify_upgrade() {
    print_step "6" "Verifying Upgrade"
    
    # Wait for services to stabilize
    sleep 10
    
    # Test HTTPS access via IP
    if curl -k -s --connect-timeout 10 "https://192.168.0.100/health" | grep -q "healthy"; then
        print_success "HTTPS access via IP working"
    else
        print_error "HTTPS access via IP failed"
        return 1
    fi
    
    # Test certificate details
    if [ -f "$SSL_DIR/server.crt" ]; then
        local subject=$(openssl x509 -subject -noout -in "$SSL_DIR/server.crt" | sed 's/subject=//')
        local issuer=$(openssl x509 -issuer -noout -in "$SSL_DIR/server.crt" | sed 's/issuer=//')
        
        echo "New certificate details:"
        echo "Subject: $subject"
        echo "Issuer: $issuer"
        
        # Check if Let's Encrypt certificate
        if echo "$issuer" | grep -q "Let's Encrypt"; then
            print_success "Let's Encrypt certificate installed"
        else
            print_warning "Certificate may not be from Let's Encrypt"
        fi
    fi
    
    # Test domain access (may fail if not accessible externally)
    if curl -s --connect-timeout 10 "https://prs.citylandcondo.com/health" | grep -q "healthy"; then
        print_success "Domain HTTPS access working"
    else
        print_info "Domain HTTPS access test failed (normal if not publicly accessible)"
    fi
}

# Function to show post-upgrade instructions
show_post_upgrade_instructions() {
    print_step "7" "Post-Upgrade Instructions"
    
    echo ""
    echo "🎉 SSL Upgrade Complete!"
    echo "========================"
    echo ""
    echo "Your system has been upgraded from self-signed to Let's Encrypt SSL."
    echo ""
    echo "✅ What changed:"
    echo "  - Certificate issuer: Self-signed → Let's Encrypt"
    echo "  - Domain: prs.client-domain.com → prs.citylandcondo.com"
    echo "  - Browser warnings: Removed (trusted certificate)"
    echo "  - Auto-renewal: Enabled (every 90 days)"
    echo ""
    echo "📋 Next steps:"
    echo "1. Test access from office devices: https://prs.citylandcondo.com"
    echo "2. Update bookmarks and shortcuts"
    echo "3. Verify monitoring is working:"
    echo "   sudo $SCRIPT_DIR/ssl-renewal-monitor.sh check"
    echo ""
    echo "🔄 Certificate renewal:"
    echo "  - Automatic monitoring enabled"
    echo "  - Email alerts 30 days before expiry"
    echo "  - Renewal process: ~5-10 minutes quarterly"
    echo ""
    echo "📞 Support:"
    echo "  - Backup certificates: $BACKUP_DIR"
    echo "  - Restore command: sudo $0 restore"
    echo "  - Monitoring: sudo $SCRIPT_DIR/ssl-renewal-monitor.sh"
    echo ""
}

# Function to restore from backup
restore_from_backup() {
    print_header
    print_warning "Restoring from backup..."
    
    if [ -d "$BACKUP_DIR" ]; then
        restore_backup
        
        # Test restored system
        if curl -k -s --connect-timeout 10 "https://192.168.0.100/health" | grep -q "healthy"; then
            print_success "System restored and working"
        else
            print_error "System restored but may have issues"
        fi
    else
        print_error "No backup directory found: $BACKUP_DIR"
        exit 1
    fi
}

# Main execution
main() {
    print_header
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
    
    analyze_current_setup
    backup_current_certificates
    test_current_system
    prepare_for_upgrade
    run_upgrade
    verify_upgrade
    show_post_upgrade_instructions
    
    print_success "SSL upgrade process completed successfully!"
}

# Script entry point
case "${1:-main}" in
    "main"|"")
        main
        ;;
    "restore")
        restore_from_backup
        ;;
    "backup")
        print_header
        backup_current_certificates
        ;;
    "analyze")
        print_header
        analyze_current_setup
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  main (default) - Run complete upgrade process"
        echo "  restore        - Restore from backup"
        echo "  backup         - Backup current certificates only"
        echo "  analyze        - Analyze current SSL setup"
        echo "  help           - Show this help message"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
