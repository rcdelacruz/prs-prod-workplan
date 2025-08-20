#!/bin/bash

# PRS On-Premises Environment Setup Script
# Quick setup of environment file with generated secrets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_EXAMPLE="$PROJECT_DIR/02-docker-configuration/.env.onprem.example"
ENV_FILE="$PROJECT_DIR/02-docker-configuration/.env"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if environment example exists
if [ ! -f "$ENV_EXAMPLE" ]; then
    echo "Error: Environment example file not found: $ENV_EXAMPLE"
    exit 1
fi

# Copy example to .env
log_info "Creating environment file from example..."
cp "$ENV_EXAMPLE" "$ENV_FILE"

# Generate secure secrets
log_info "Generating secure secrets..."

POSTGRES_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32)
OTP_KEY=$(openssl rand -base64 16)
PASS_SECRET=$(openssl rand -base64 32)
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
ROOT_USER_PASSWORD=$(openssl rand -base64 32)

# Replace placeholders with generated secrets
log_info "Updating environment file with generated secrets..."

sed -i "s/CHANGE_THIS_SUPER_STRONG_PASSWORD_123!/$POSTGRES_PASSWORD/g" "$ENV_FILE"
sed -i "s/CHANGE_THIS_REDIS_PASSWORD_456!/$REDIS_PASSWORD/g" "$ENV_FILE"
sed -i "s/CHANGE_THIS_JWT_SECRET_VERY_LONG_AND_RANDOM_STRING_789!/$JWT_SECRET/g" "$ENV_FILE"
sed -i "s/CHANGE_THIS_ENCRYPTION_KEY_32_CHARS_LONG_ABC123!/$ENCRYPTION_KEY/g" "$ENV_FILE"
sed -i "s/CHANGE_THIS_OTP_KEY_RANDOM_STRING_DEF456!/$OTP_KEY/g" "$ENV_FILE"
sed -i "s/CHANGE_THIS_PASS_SECRET_GHI789!/$PASS_SECRET/g" "$ENV_FILE"
sed -i "s/CHANGE_THIS_GRAFANA_PASSWORD_JKL012!/$GRAFANA_ADMIN_PASSWORD/g" "$ENV_FILE"
sed -i "s/CHANGE_THIS_ROOT_PASSWORD_MNO345!/$ROOT_USER_PASSWORD/g" "$ENV_FILE"

# Update domain and server IP (you may need to customize these)
sed -i "s/prs.client-domain.com/prs.$(hostname -d 2>/dev/null || echo 'local')/g" "$ENV_FILE"
sed -i "s/admin@client-domain.com/admin@$(hostname -d 2>/dev/null || echo 'local')/g" "$ENV_FILE"

log_success "Environment file created: $ENV_FILE"

# Create credentials summary
CREDS_FILE="$PROJECT_DIR/ADMIN_CREDENTIALS.txt"
cat > "$CREDS_FILE" << EOF
=== PRS On-Premises Admin Credentials ===
Generated: $(date)

Application Access:
URL: https://192.168.16.100/
Admin Email: admin@$(hostname -d 2>/dev/null || echo 'local')
Admin Password: $ROOT_USER_PASSWORD

Grafana Monitoring:
URL: http://192.168.16.100:3001/
Username: admin
Password: $GRAFANA_ADMIN_PASSWORD

Database Access (Adminer):
URL: http://192.168.16.100:8080/
Database: prs_production
Username: prs_user
Password: $POSTGRES_PASSWORD

Container Management (Portainer):
URL: http://192.168.16.100:9000/
(Setup admin user on first access)

Prometheus Monitoring:
URL: http://192.168.16.100:9090/

IMPORTANT: Keep this file secure and share only with authorized personnel.
EOF

log_success "Admin credentials saved: $CREDS_FILE"

echo ""
log_warning "IMPORTANT: Please review and customize the following in $ENV_FILE:"
echo "  - DOMAIN (currently set to prs.$(hostname -d 2>/dev/null || echo 'local'))"
echo "  - SERVER_IP (currently set to 192.168.16.100)"
echo "  - SMTP settings for email notifications"
echo "  - Any other client-specific settings"

echo ""
log_info "Next steps:"
echo "  1. Review and customize $ENV_FILE"
echo "  2. Run: $SCRIPT_DIR/deploy-onprem.sh deploy"
echo "  3. Access application at https://192.168.16.100/"

echo ""
log_success "Environment setup complete!"
