# PRS On-Premises Deployment Script

Enhanced deployment script for PRS (Personnel Record System) on-premises infrastructure with configurable repositories and PostgreSQL database access.

## New Features

### 1. Configurable Repositories

The script now supports configurable repository URLs and branches through environment variables:

- `BACKEND_REPO_URL`: Backend repository URL (default: https://github.com/rcdelacruz/prs-backend-a.git)
- `FRONTEND_REPO_URL`: Frontend repository URL (default: https://github.com/rcdelacruz/prs-frontend-a.git)
- `BACKEND_BRANCH`: Backend branch (default: main)
- `FRONTEND_BRANCH`: Frontend branch (default: main)
- `REPO_BASE_DIR`: Repository base directory (default: /opt/prs)

### 2. PostgreSQL Database Access

New database management commands:

- `db-connect`: Connect to PostgreSQL database interactively
- `db-shell`: Open shell in database container
- `db-backup`: Create database backup with timestamp
- `db-restore <file>`: Restore database from backup file

## Usage Examples

### Basic Deployment
```bash
# Deploy with default repositories
./scripts/deploy-onprem.sh deploy
```

### Custom Repository Deployment
```bash
# Using environment variables
BACKEND_REPO_URL=https://github.com/myorg/my-backend.git \
FRONTEND_REPO_URL=https://github.com/myorg/my-frontend.git \
./scripts/deploy-onprem.sh deploy

# Using configuration file
cp scripts/repo-config.example.sh scripts/repo-config.sh
# Edit repo-config.sh with your settings
source scripts/repo-config.sh
./scripts/deploy-onprem.sh deploy
```

### Database Management
```bash
# Connect to database
./scripts/deploy-onprem.sh db-connect

# Create backup
./scripts/deploy-onprem.sh db-backup

# Restore from backup
./scripts/deploy-onprem.sh db-restore /mnt/hdd/postgres-backups/backup_20241220_143000.sql.gz

# Open database container shell
./scripts/deploy-onprem.sh db-shell
```

### Service Management
```bash
# Check status
./scripts/deploy-onprem.sh status

# Restart services
./scripts/deploy-onprem.sh restart

# Stop services
./scripts/deploy-onprem.sh stop
```

## Database Access Details

### Direct PostgreSQL Connection
When you run `db-connect`, you'll be connected to the PostgreSQL database with:
- Database: `prs_production`
- User: `prs_user`
- Host: Inside the Docker container

### Backup Location
Database backups are stored in `/mnt/hdd/postgres-backups/` with the format:
`prs_production_YYYYMMDD_HHMMSS.sql.gz`

### Restore Process
The restore process:
1. Stops application services
2. Drops and recreates the database
3. Restores from the backup file
4. Restarts application services

## Prerequisites

- Ubuntu 24.04 LTS (recommended)
- 16GB RAM minimum
- SSD mount at `/mnt/ssd`
- HDD mount at `/mnt/hdd`
- Docker and Docker Compose
- Git access to repositories

## Security Notes

- Database backups are compressed and stored on HDD storage
- SSL certificates are auto-generated for HTTPS
- Firewall is configured for internal network access only
- Database restore requires confirmation prompt

## Troubleshooting

### Repository Access Issues
- Ensure Git credentials are configured
- Check repository URLs and branch names
- Verify network connectivity to Git repositories

### Database Connection Issues
- Ensure PostgreSQL container is running: `docker ps | grep postgres`
- Check database logs: `docker logs prs-onprem-postgres-timescale`
- Verify environment file configuration

### Storage Issues
- Check SSD/HDD mount points: `df -h /mnt/ssd /mnt/hdd`
- Verify permissions: `ls -la /mnt/ssd /mnt/hdd`
- Ensure sufficient disk space for backups
