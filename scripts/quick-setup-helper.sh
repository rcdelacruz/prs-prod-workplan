#!/bin/bash
# /opt/prs-deployment/scripts/quick-setup-helper.sh
# Quick setup helper for PRS deployment configuration
# This script helps configure the environment before running deploy-onprem.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

print_header() {
    echo -e "${PURPLE}================================================================${NC}"
    echo -e "${PURPLE}                PRS Quick Setup Helper                        ${NC}"
    echo -e "${PURPLE}          Prepare configuration for deploy-onprem.sh         ${NC}"
    echo -e "${PURPLE}================================================================${NC}"
    echo ""
}

print_info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

# Function to prompt for input with default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    echo -n -e "${BLUE}$prompt${NC}"
    if [ -n "$default" ]; then
        echo -n -e " ${YELLOW}(default: $default)${NC}"
    fi
    echo -n ": "

    read -r input
    if [ -z "$input" ] && [ -n "$default" ]; then
        input="$default"
    fi

    eval "$var_name='$input'"
}

# Function to configure environment
configure_environment() {
    print_info "Configuring environment variables..."

    local env_file="$PROJECT_DIR/02-docker-configuration/.env"

    # Copy template if .env doesn't exist
    if [ ! -f "$env_file" ]; then
        cp "$PROJECT_DIR/02-docker-configuration/.env.onprem.example" "$env_file"
        print_success "Created .env file from template"
    fi

    # Get current values or defaults from the actual .env structure
    local current_domain=$(grep "^DOMAIN=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "prs.citylandcondo.com")
    local current_admin_email=$(grep "^ROOT_USER_EMAIL=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "admin@citylandcondo.com")
    local current_server_ip=$(grep "^SERVER_IP=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "192.168.0.100")

    echo ""
    echo -e "${BLUE}Basic Configuration${NC}"
    echo ""

    # Domain configuration
    prompt_with_default "Enter your domain name" "$current_domain" "domain"

    # Server IP configuration
    prompt_with_default "Enter server IP address" "$current_server_ip" "server_ip"

    # Admin email
    prompt_with_default "Enter admin email" "$current_admin_email" "admin_email"

    # SSL configuration
    echo ""
    echo -e "${BLUE}SSL Configuration${NC}"
    echo "The deploy script generates self-signed certificates by default."
    echo "You can replace them later with:"
    echo "1) GoDaddy SSL (run ssl-automation-citylandcondo.sh after deployment)"
    echo "2) Let's Encrypt (manual setup after deployment)"
    echo "3) Custom certificates (place in ssl/ directory)"
    echo ""

    # Database password (idempotent - only generate if not already set)
    echo ""
    echo -e "${BLUE}Security Configuration${NC}"
    echo ""

    # Get existing passwords from .env file (if they exist)
    local existing_db_password=$(grep "^POSTGRES_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "")
    local existing_redis_password=$(grep "^REDIS_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "")
    local existing_root_password=$(grep "^ROOT_USER_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "")

    # Only generate new passwords if they don't exist or are placeholder values
    local db_password="$existing_db_password"
    if [ -z "$db_password" ] || [[ "$db_password" == *"CHANGE_THIS"* ]]; then
        db_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        print_info "Generated new database password"
    else
        print_info "Using existing database password"
    fi
    prompt_with_default "Database password" "$db_password" "postgres_password"

    local redis_password="$existing_redis_password"
    if [ -z "$redis_password" ] || [[ "$redis_password" == *"CHANGE_THIS"* ]]; then
        redis_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        print_info "Generated new Redis password"
    else
        print_info "Using existing Redis password"
    fi
    prompt_with_default "Redis password" "$redis_password" "redis_password"

    local root_password="$existing_root_password"
    if [ -z "$root_password" ] || [[ "$root_password" == *"CHANGE_THIS"* ]]; then
        root_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        print_info "Generated new root user password"
    else
        print_info "Using existing root user password"
    fi
    prompt_with_default "Root user password" "$root_password" "root_password"

    # Application secrets (idempotent - only generate if placeholder values)
    echo ""
    echo -e "${BLUE}Application Secrets Configuration${NC}"
    echo ""

    # Get existing secrets from .env file
    local existing_jwt_secret=$(grep "^JWT_SECRET=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "")
    local existing_encryption_key=$(grep "^ENCRYPTION_KEY=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "")
    local existing_otp_key=$(grep "^OTP_KEY=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "")
    local existing_pass_secret=$(grep "^PASS_SECRET=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "")

    # JWT Secret (64 characters)
    local jwt_secret="$existing_jwt_secret"
    if [ -z "$jwt_secret" ] || [[ "$jwt_secret" == *"CHANGE_THIS"* ]]; then
        jwt_secret=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-64)
        print_info "Generated new JWT secret"
    else
        print_info "Using existing JWT secret"
    fi

    # Encryption Key (exactly 32 characters for AES-256)
    local encryption_key="$existing_encryption_key"
    if [ -z "$encryption_key" ] || [[ "$encryption_key" == *"CHANGE_THIS"* ]] || [ ${#encryption_key} -ne 32 ]; then
        encryption_key=$(openssl rand -hex 16)  # 16 bytes = 32 hex chars
        print_info "Generated new encryption key (32 chars)"
    else
        print_info "Using existing encryption key"
    fi

    # OTP Key (32 characters)
    local otp_key="$existing_otp_key"
    if [ -z "$otp_key" ] || [[ "$otp_key" == *"CHANGE_THIS"* ]] || [ ${#otp_key} -ne 32 ]; then
        otp_key=$(openssl rand -hex 16)  # 16 bytes = 32 hex chars
        print_info "Generated new OTP key (32 chars)"
    else
        print_info "Using existing OTP key"
    fi

    # Pass Secret (32 characters)
    local pass_secret="$existing_pass_secret"
    if [ -z "$pass_secret" ] || [[ "$pass_secret" == *"CHANGE_THIS"* ]] || [ ${#pass_secret} -ne 32 ]; then
        pass_secret=$(openssl rand -hex 16)  # 16 bytes = 32 hex chars
        print_info "Generated new pass secret (32 chars)"
    else
        print_info "Using existing pass secret"
    fi

    # Update .env file with correct variable names
    sed -i "s|^DOMAIN=.*|DOMAIN=$domain|" "$env_file"
    sed -i "s|^SERVER_IP=.*|SERVER_IP=$server_ip|" "$env_file"
    sed -i "s|^ROOT_USER_EMAIL=.*|ROOT_USER_EMAIL=$admin_email|" "$env_file"
    sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$postgres_password|" "$env_file"
    sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$redis_password|" "$env_file"
    sed -i "s|^ROOT_USER_PASSWORD=.*|ROOT_USER_PASSWORD=$root_password|" "$env_file"

    # Update application secrets
    sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$jwt_secret|" "$env_file"
    sed -i "s|^ENCRYPTION_KEY=.*|ENCRYPTION_KEY=$encryption_key|" "$env_file"
    sed -i "s|^OTP_KEY=.*|OTP_KEY=$otp_key|" "$env_file"
    sed -i "s|^PASS_SECRET=.*|PASS_SECRET=$pass_secret|" "$env_file"

    # Configure dynamic frontend URLs (empty values enable dynamic detection)
    sed -i "s|^VITE_APP_API_URL=.*|VITE_APP_API_URL=|" "$env_file"
    sed -i "s|^VITE_APP_UPLOAD_URL=.*|VITE_APP_UPLOAD_URL=|" "$env_file"

    # Update CORS origin to support both domain and IP access
    sed -i "s|^CORS_ORIGIN=.*|CORS_ORIGIN=https://$domain,http://$domain,https://$server_ip,http://$server_ip,http://192.168.0.0/20|" "$env_file"

    print_success "Environment configuration updated"

    # Configure dynamic frontend host detection
    configure_dynamic_frontend
}

# Function to configure dynamic frontend host detection
configure_dynamic_frontend() {
    print_info "Configuring dynamic frontend host detection..."

    local frontend_config_file="$PROJECT_DIR/../prs-frontend-a/src/config/env.js"

    # Check if frontend repository exists
    if [ ! -f "$frontend_config_file" ]; then
        print_warning "Frontend configuration file not found at $frontend_config_file"
        print_info "Dynamic host detection will be configured when repositories are cloned"
        return
    fi

    # Check if dynamic configuration is already implemented
    if grep -q "getApiUrl" "$frontend_config_file"; then
        print_success "Dynamic frontend host detection already configured"
        return
    fi

    print_info "Updating frontend configuration for dynamic host detection..."

    # Create backup
    cp "$frontend_config_file" "$frontend_config_file.backup"

    # Apply dynamic configuration patch
    cat > /tmp/env_dynamic_patch.js << 'EOF'
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

    # Replace the frontend configuration
    cp /tmp/env_dynamic_patch.js "$frontend_config_file"
    rm /tmp/env_dynamic_patch.js

    print_success "Dynamic frontend host detection configured"
    print_info "Frontend will now automatically detect API URLs based on current host"
}

# Function to configure repositories
configure_repositories() {
    echo ""
    echo -e "${BLUE}Repository Configuration${NC}"
    echo ""

    local env_file="$PROJECT_DIR/02-docker-configuration/.env"

    # Get current repository URLs
    local current_backend_url=$(grep "^BACKEND_REPO_URL=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "https://github.com/your-org/prs-backend-a.git")
    local current_frontend_url=$(grep "^FRONTEND_REPO_URL=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "https://github.com/your-org/prs-frontend-a.git")
    local current_backend_branch=$(grep "^BACKEND_BRANCH=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "main")
    local current_frontend_branch=$(grep "^FRONTEND_BRANCH=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "main")

    echo "Configure the repository URLs and branches for backend and frontend applications:"
    echo ""

    # Backend repository
    prompt_with_default "Backend repository URL" "$current_backend_url" "backend_repo_url"
    prompt_with_default "Backend branch" "$current_backend_branch" "backend_branch"

    # Frontend repository
    prompt_with_default "Frontend repository URL" "$current_frontend_url" "frontend_repo_url"
    prompt_with_default "Frontend branch" "$current_frontend_branch" "frontend_branch"

    # Update repository configuration in .env file
    sed -i "s|^BACKEND_REPO_URL=.*|BACKEND_REPO_URL=$backend_repo_url|" "$env_file"
    sed -i "s|^FRONTEND_REPO_URL=.*|FRONTEND_REPO_URL=$frontend_repo_url|" "$env_file"

    # Update or add branch configuration
    if grep -q "^BACKEND_BRANCH=" "$env_file"; then
        sed -i "s|^BACKEND_BRANCH=.*|BACKEND_BRANCH=$backend_branch|" "$env_file"
    else
        # Add BACKEND_BRANCH after FRONTEND_REPO_URL
        sed -i "/^FRONTEND_REPO_URL=/a\\BACKEND_BRANCH=$backend_branch" "$env_file"
    fi

    if grep -q "^FRONTEND_BRANCH=" "$env_file"; then
        sed -i "s|^FRONTEND_BRANCH=.*|FRONTEND_BRANCH=$frontend_branch|" "$env_file"
    else
        # Add FRONTEND_BRANCH after BACKEND_BRANCH
        sed -i "/^BACKEND_BRANCH=/a\\FRONTEND_BRANCH=$frontend_branch" "$env_file"
    fi

    # Remove old GIT_BRANCH if it exists
    sed -i "/^GIT_BRANCH=/d" "$env_file"

    print_success "Repository configuration updated"

    # Store repository summary
    echo ""
    echo -e "${BLUE}Repository Summary:${NC}"
    echo "  Backend URL: $backend_repo_url (branch: $backend_branch)"
    echo "  Frontend URL: $frontend_repo_url (branch: $frontend_branch)"

    # Store configuration summary
    echo ""
    echo -e "${BLUE}Configuration Summary:${NC}"
    echo "  Domain: $domain"
    echo "  Server IP: $server_ip"
    echo "  Admin Email: $admin_email"
    echo "  Database Password: [CONFIGURED]"
    echo "  Redis Password: [CONFIGURED]"
    echo "  Root Password: [CONFIGURED]"
}

# Function to configure NAS (optional)
configure_nas() {
    echo ""
    echo -e "${BLUE}NAS Backup Configuration (Optional)${NC}"
    echo ""

    local configure_nas
    prompt_with_default "Configure NAS backup? (y/n)" "n" "configure_nas"

    if [[ "$configure_nas" =~ ^[Yy]$ ]]; then
        # Copy NAS config template
        if [ ! -f "$SCRIPT_DIR/nas-config.sh" ]; then
            cp "$SCRIPT_DIR/nas-config.example.sh" "$SCRIPT_DIR/nas-config.sh"
        fi

        local nas_host nas_share nas_username nas_password

        prompt_with_default "NAS hostname/IP" "192.168.1.100" "nas_host"
        prompt_with_default "NAS share name" "backups" "nas_share"
        prompt_with_default "NAS username (leave empty for NFS)" "" "nas_username"

        if [ -n "$nas_username" ]; then
            prompt_with_default "NAS password" "" "nas_password"
        fi

        # Update NAS config
        sed -i "s/export NAS_HOST=.*/export NAS_HOST=\"$nas_host\"/" "$SCRIPT_DIR/nas-config.sh"
        sed -i "s/export NAS_SHARE=.*/export NAS_SHARE=\"$nas_share\"/" "$SCRIPT_DIR/nas-config.sh"
        sed -i "s/export BACKUP_TO_NAS=.*/export BACKUP_TO_NAS=\"true\"/" "$SCRIPT_DIR/nas-config.sh"

        if [ -n "$nas_username" ]; then
            sed -i "s/export NAS_USERNAME=.*/export NAS_USERNAME=\"$nas_username\"/" "$SCRIPT_DIR/nas-config.sh"
            sed -i "s/export NAS_PASSWORD=.*/export NAS_PASSWORD=\"$nas_password\"/" "$SCRIPT_DIR/nas-config.sh"
        fi

        chmod 600 "$SCRIPT_DIR/nas-config.sh"

        # Add to .env file
        echo "BACKUP_TO_NAS=true" >> "$PROJECT_DIR/02-docker-configuration/.env"
        echo "NAS_HOST=$nas_host" >> "$PROJECT_DIR/02-docker-configuration/.env"
        echo "NAS_SHARE=$nas_share" >> "$PROJECT_DIR/02-docker-configuration/.env"

        print_success "NAS configuration saved"
    else
        print_info "Skipping NAS configuration - local backups only"
    fi
}

# Function to show next steps
show_next_steps() {
    echo ""
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}                    Configuration Complete!                   ${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo ""
    echo -e "${YELLOW}1. Run the deployment (this will take 1-2 hours):${NC}"
    echo "   cd $SCRIPT_DIR"
    echo "   sudo ./deploy-onprem.sh deploy"
    echo ""
    echo -e "${BLUE}   The deploy command will:${NC}"
    echo "   - Install all dependencies (Docker, packages, etc.)"
    echo "   - Configure storage (SSD/HDD setup)"
    echo "   - Set up SSL certificates (self-signed initially)"
    echo "   - Configure firewall for office network (192.168.0.0/20)"
    echo "   - Build and deploy all services"
    echo "   - Initialize database and application"
    echo ""
    echo -e "${YELLOW}2. Optional: Set up GoDaddy SSL (for *.citylandcondo.com):${NC}"
    echo "   ./ssl-automation-citylandcondo.sh"
    echo ""
    echo -e "${YELLOW}3. Set up automation (after deployment):${NC}"
    echo "   ./setup-backup-automation.sh"
    echo "   ./setup-monitoring-automation.sh"
    echo ""
    echo -e "${YELLOW}4. Access your system (office network 192.168.0.0/20 only):${NC}"
    echo "   Main App: https://$domain OR https://$server_ip (office network only)"
    echo "   Grafana:  http://$server_ip:3000 (office network only)"
    echo "   Adminer:  http://$server_ip:8080 (office network only)"
    echo "   Portainer: http://$server_ip:9000 (office network only)"
    echo ""
    echo -e "${BLUE}Dynamic Host Detection:${NC}"
    echo "   The frontend automatically detects whether you're accessing via IP or domain."
    echo "   Both https://$domain and https://$server_ip will work seamlessly."
    echo ""
    echo -e "${BLUE}Useful commands after deployment:${NC}"
    echo "   ./deploy-onprem.sh status     # Check system status"
    echo "   ./deploy-onprem.sh check-state # Check deployment state"
    echo "   ./deploy-onprem.sh help       # See all available commands"
    echo ""
}

# Main function
main() {
    print_header

    print_info "This helper will configure your environment for PRS deployment."
    print_info "After configuration, you'll run deploy-onprem.sh to deploy the system."
    echo ""

    configure_environment
    configure_repositories
    configure_nas
    show_next_steps
}

# Run main function
main "$@"
