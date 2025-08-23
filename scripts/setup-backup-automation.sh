#!/bin/bash
# /opt/prs-deployment/scripts/setup-backup-automation.sh
# Set up automated backup schedule after deployment

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
    echo -e "${BLUE}🔄 Setting up automated backup schedule...${NC}"
    echo ""
    
    # Test NAS connectivity if configured
    if [ -f "$SCRIPT_DIR/nas-config.sh" ]; then
        print_info "Testing NAS connectivity..."
        if [ -f "$SCRIPT_DIR/test-nas-connection.sh" ]; then
            if "$SCRIPT_DIR/test-nas-connection.sh"; then
                print_success "NAS connectivity verified"
            else
                print_warning "NAS connectivity failed - backups will be local only"
            fi
        fi
    fi
    
    # Set up cron jobs
    print_info "Setting up backup schedule..."
    
    # Remove any existing PRS backup jobs
    (crontab -l 2>/dev/null | grep -v "PRS Backup\|prs-backup\|prs-maintenance" || true) | crontab -
    
    # Add new backup schedule
    (crontab -l 2>/dev/null; cat <<EOF
# PRS Backup Schedule
0 2 * * * $SCRIPT_DIR/backup-full.sh >> /var/log/prs-backup.log 2>&1
0 3 * * * $SCRIPT_DIR/backup-application-data.sh >> /var/log/prs-backup.log 2>&1
0 4 * * * $SCRIPT_DIR/verify-backups.sh >> /var/log/prs-backup.log 2>&1
0 1 * * 0 $SCRIPT_DIR/backup-maintenance.sh >> /var/log/prs-maintenance.log 2>&1
EOF
    ) | crontab -
    
    # Add NAS monitoring if configured
    if [ -f "$SCRIPT_DIR/nas-config.sh" ]; then
        (crontab -l 2>/dev/null; echo "0 */6 * * * $SCRIPT_DIR/test-nas-connection.sh >> /var/log/prs-nas-test.log 2>&1") | crontab -
        print_success "Added NAS connectivity monitoring"
    fi
    
    # Create log files
    sudo touch /var/log/prs-backup.log /var/log/prs-maintenance.log /var/log/prs-nas-test.log
    sudo chown $USER:$USER /var/log/prs-*.log
    
    print_success "Backup automation configured!"
    echo ""
    echo -e "${BLUE}📋 Backup Schedule:${NC}"
    echo "  • Daily database backup: 2:00 AM"
    echo "  • Daily application backup: 3:00 AM"
    echo "  • Daily backup verification: 4:00 AM"
    echo "  • Weekly maintenance: Sunday 1:00 AM"
    if [ -f "$SCRIPT_DIR/nas-config.sh" ]; then
        echo "  • NAS connectivity check: Every 6 hours"
    fi
    echo ""
    echo -e "${BLUE}📝 Log files:${NC}"
    echo "  • /var/log/prs-backup.log"
    echo "  • /var/log/prs-maintenance.log"
    if [ -f "$SCRIPT_DIR/nas-config.sh" ]; then
        echo "  • /var/log/prs-nas-test.log"
    fi
    echo ""
    echo -e "${YELLOW}💡 Test backup manually: ./backup-full.sh${NC}"
}

main "$@"
