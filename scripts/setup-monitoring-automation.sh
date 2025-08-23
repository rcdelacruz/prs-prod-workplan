#!/bin/bash
# /opt/prs-deployment/scripts/setup-monitoring-automation.sh
# Set up automated monitoring schedule after deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

main() {
    echo -e "${BLUE}📊 Setting up automated monitoring schedule...${NC}"
    echo ""
    
    # Set up monitoring cron jobs
    print_info "Setting up monitoring schedule..."
    
    # Remove any existing PRS monitoring jobs
    (crontab -l 2>/dev/null | grep -v "PRS Monitoring\|prs-monitoring\|prs-health" || true) | crontab -
    
    # Add new monitoring schedule
    (crontab -l 2>/dev/null; cat <<EOF
# PRS Monitoring Schedule
*/5 * * * * $SCRIPT_DIR/system-performance-monitor.sh >> /var/log/prs-monitoring.log 2>&1
*/10 * * * * $SCRIPT_DIR/application-health-monitor.sh >> /var/log/prs-monitoring.log 2>&1
*/15 * * * * $SCRIPT_DIR/database-performance-monitor.sh >> /var/log/prs-monitoring.log 2>&1
0 8 * * * $SCRIPT_DIR/generate-monitoring-report.sh >> /var/log/prs-monitoring.log 2>&1
0 * * * * $SCRIPT_DIR/system-health-check.sh >> /var/log/prs-health.log 2>&1
EOF
    ) | crontab -
    
    # Create log files
    sudo touch /var/log/prs-monitoring.log /var/log/prs-health.log
    sudo chown $USER:$USER /var/log/prs-monitoring.log /var/log/prs-health.log
    
    # Set up security monitoring
    print_info "Setting up security monitoring..."
    
    # Install fail2ban if not present
    if ! command -v fail2ban-server &> /dev/null; then
        print_info "Installing fail2ban for SSH protection..."
        sudo apt update
        sudo apt install -y fail2ban
        
        # Configure fail2ban for office network
        sudo tee /etc/fail2ban/jail.local > /dev/null <<EOF
[DEFAULT]
bantime = 1800
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 1800
EOF
        
        sudo systemctl enable fail2ban
        sudo systemctl start fail2ban
        print_success "fail2ban configured"
    fi
    
    # Set up automatic security updates
    if ! dpkg -l | grep -q unattended-upgrades; then
        print_info "Setting up automatic security updates..."
        sudo apt install -y unattended-upgrades
        echo 'Unattended-Upgrade::Automatic-Reboot "false";' | sudo tee -a /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null
        print_success "Automatic security updates configured"
    fi
    
    print_success "Monitoring automation configured!"
    echo ""
    echo -e "${BLUE}📋 Monitoring Schedule:${NC}"
    echo "  • System performance: Every 5 minutes"
    echo "  • Application health: Every 10 minutes"
    echo "  • Database performance: Every 15 minutes"
    echo "  • Daily monitoring report: 8:00 AM"
    echo "  • System health check: Every hour"
    echo ""
    echo -e "${BLUE}🔒 Security Features:${NC}"
    echo "  • fail2ban SSH protection"
    echo "  • Automatic security updates"
    echo ""
    echo -e "${BLUE}📝 Log files:${NC}"
    echo "  • /var/log/prs-monitoring.log"
    echo "  • /var/log/prs-health.log"
    echo ""
    echo -e "${YELLOW}💡 Check system health manually: ./system-health-check.sh${NC}"
}

main "$@"
