# Troubleshooting

## Overview

This guide provides comprehensive troubleshooting procedures for common issues in the PRS on-premises deployment.

## Service Issues

### Services Won't Start

#### Symptoms
- Docker containers fail to start
- Services show "Exited" status
- Application not accessible

#### Diagnosis

```bash
# Check service status
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml ps

# Check specific service logs
docker logs prs-onprem-backend
docker logs prs-onprem-postgres-timescale
docker logs prs-onprem-nginx

# Check Docker daemon status
sudo systemctl status docker

# Check available resources
free -h
df -h
```

#### Solutions

**Resource Issues:**
```bash
# Check disk space
df -h
# If disk full, clean up:
docker system prune -f
sudo find /tmp -type f -mtime +7 -delete

# Check memory
free -h
# If memory low, restart services one by one:
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart backend
```

**Permission Issues:**
```bash
# Fix storage permissions
sudo chown -R 999:999 /mnt/hdd/postgresql-hot /mnt/hdd/postgresql-cold
sudo chown -R 999:999 /mnt/hdd/redis-data
sudo chown -R 472:472 /mnt/hdd/grafana-data

# Fix file permissions
sudo chmod 644 02-docker-configuration/.env
sudo chmod 600 02-docker-configuration/ssl/private.key
```

**Configuration Issues:**
```bash
# Validate environment file
grep -E "(DOMAIN|POSTGRES_PASSWORD|JWT_SECRET)" 02-docker-configuration/.env

# Check Docker Compose syntax
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml config

# Restart with fresh configuration
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml down
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml up -d
```

### Database Connection Issues

#### Symptoms
- Backend can't connect to database
- "Connection refused" errors
- Timeout errors

#### Diagnosis

```bash
# Check PostgreSQL status
docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin

# Check database logs
docker logs prs-onprem-postgres-timescale --tail 50

# Test connection from backend
docker exec prs-onprem-backend npm run db:test

# Check connection count
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT count(*) as connections, state 
FROM pg_stat_activity 
GROUP BY state;
"
```

#### Solutions

**Database Not Ready:**
```bash
# Wait for database to be ready
while ! docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin; do
    echo "Waiting for PostgreSQL..."
    sleep 5
done

# Restart database if needed
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart postgres
```

**Connection Pool Exhausted:**
```bash
# Kill idle connections
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE state = 'idle' 
AND query_start < NOW() - INTERVAL '1 hour';
"

# Restart backend to reset connection pool
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart backend
```

**Network Issues:**
```bash
# Check container network
docker network inspect prs_onprem_network

# Test container connectivity
docker exec prs-onprem-backend ping prs-onprem-postgres-timescale

# Restart networking
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml down
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml up -d
```

### SSL Certificate Issues

#### Symptoms
- HTTPS not working
- Certificate warnings in browser
- SSL handshake failures

#### Diagnosis

```bash
# Check certificate files
ls -la 02-docker-configuration/ssl/

# Check certificate validity
openssl x509 -in 02-docker-configuration/ssl/certificate.crt -text -noout

# Check certificate expiration
openssl x509 -in 02-docker-configuration/ssl/certificate.crt -noout -dates

# Test SSL connection
openssl s_client -connect your-domain.com:443 -servername your-domain.com
```

#### Solutions

**Missing Certificates:**
```bash
# Generate new certificates
./scripts/ssl-automation-citylandcondo.sh

# Or copy existing certificates
sudo cp /path/to/certificate.crt 02-docker-configuration/ssl/
sudo cp /path/to/private.key 02-docker-configuration/ssl/
sudo cp /path/to/ca-bundle.crt 02-docker-configuration/ssl/
```

**Expired Certificates:**
```bash
# Renew Let's Encrypt certificates
sudo certbot renew --force-renewal

# Copy renewed certificates
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem 02-docker-configuration/ssl/certificate.crt
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem 02-docker-configuration/ssl/private.key

# Restart nginx
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart nginx
```

**Permission Issues:**
```bash
# Fix certificate permissions
sudo chmod 644 02-docker-configuration/ssl/certificate.crt
sudo chmod 600 02-docker-configuration/ssl/private.key
sudo chmod 644 02-docker-configuration/ssl/ca-bundle.crt

# Restart nginx
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart nginx
```

## Performance Issues

### Slow Response Times

#### Symptoms
- Pages load slowly (>2 seconds)
- API responses take too long
- Users report performance issues

#### Diagnosis

```bash
# Test response times
time curl -s https://your-domain.com/api/health
ab -n 100 -c 10 https://your-domain.com/

# Check system resources
htop
iostat -x 1
iotop

# Check container resources
docker stats

# Check database performance
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
ORDER BY total_time DESC 
LIMIT 10;
"
```

#### Solutions

**High CPU Usage:**
```bash
# Identify CPU-intensive processes
top -o %CPU

# Check container CPU usage
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Restart high-CPU containers
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart backend
```

**Memory Issues:**
```bash
# Check memory usage
free -h
docker stats --format "table {{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Clear system cache
sudo sync && sudo sysctl vm.drop_caches=3

# Restart memory-intensive services
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart backend frontend
```

**Database Performance:**
```sql
-- Check slow queries
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
ORDER BY total_time DESC 
LIMIT 10;

-- Update statistics
ANALYZE notifications;
ANALYZE audit_logs;
ANALYZE requisitions;

-- Check for table bloat
SELECT 
    schemaname,
    tablename,
    n_dead_tup,
    n_live_tup
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;

-- Vacuum if needed
VACUUM ANALYZE notifications;
```

### Storage Issues

#### Symptoms
- "No space left on device" errors
- Slow file operations
- Database write failures

#### Diagnosis

```bash
# Check storage usage
df -h /mnt/hdd /mnt/hdd

# Check inode usage
df -i /mnt/hdd /mnt/hdd

# Check large files
find /mnt/hdd -type f -size +100M -exec ls -lh {} \;
find /mnt/hdd -type f -size +1G -exec ls -lh {} \;

# Check RAID status
cat /proc/mdstat
```

#### Solutions

**SSD Full (>90%):**
```bash
# Emergency cleanup
find /mnt/hdd/logs -name "*.log" -mtime +1 -exec gzip {} \;
docker system prune -f

# Move old data to HDD
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT move_chunk(chunk_name, 'pg_default')
FROM timescaledb_information.chunks 
WHERE range_start < NOW() - INTERVAL '14 days'
AND tablespace_name = 'pg_default'
LIMIT 10;
"

# Compress old chunks
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT compress_chunk(chunk_name) 
FROM timescaledb_information.chunks 
WHERE range_start < NOW() - INTERVAL '3 days'
AND NOT is_compressed
AND tablespace_name = 'pg_default';
"
```

**HDD Full (>85%):**
```bash
# Clean old backups
find /mnt/hdd/postgres-backups -name "*.sql" -mtime +30 -delete
find /mnt/hdd/app-logs-archive -name "*.log.gz" -mtime +365 -delete

# Compress uncompressed files
find /mnt/hdd -name "*.log" -mtime +7 -exec gzip {} \;
```

**RAID Issues:**
```bash
# Check RAID status
cat /proc/mdstat
sudo mdadm --detail /dev/md0
sudo mdadm --detail /dev/md1

# If RAID degraded, check disk health
sudo smartctl -a /dev/sda
sudo smartctl -a /dev/sdb

# Replace failed disk (if needed)
sudo mdadm --manage /dev/md1 --add /dev/sdf
```

## Network Issues

### Connectivity Problems

#### Symptoms
- Can't access application from network
- Intermittent connection failures
- DNS resolution issues

#### Diagnosis

```bash
# Check network interfaces
ip addr show
ip route show

# Test connectivity
ping 8.8.8.8
ping your-domain.com
nslookup your-domain.com

# Check firewall
sudo ufw status verbose
sudo iptables -L

# Check port bindings
sudo netstat -tulpn | grep LISTEN
```

#### Solutions

**Firewall Issues:**
```bash
# Check and fix firewall rules
sudo ufw status verbose

# Allow required ports
sudo ufw allow from 192.168.0.0/20 to any port 80
sudo ufw allow from 192.168.0.0/20 to any port 443

# Restart firewall
sudo ufw disable && sudo ufw enable
```

**DNS Issues:**
```bash
# Check DNS configuration
cat /etc/resolv.conf

# Test DNS resolution
nslookup your-domain.com
dig your-domain.com

# Update DNS if needed
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
```

**Network Configuration:**
```bash
# Check network configuration
cat /etc/netplan/01-network-config.yaml

# Apply network configuration
sudo netplan apply

# Restart networking
sudo systemctl restart systemd-networkd
```

## Application-Specific Issues

### Frontend Issues

#### Symptoms
- Blank page or loading errors
- JavaScript errors in console
- API connection failures

#### Diagnosis

```bash
# Check frontend logs
docker logs prs-onprem-frontend

# Check nginx logs
docker logs prs-onprem-nginx

# Test frontend container
docker exec prs-onprem-frontend curl http://localhost:3000

# Check browser console for errors
```

#### Solutions

**Build Issues:**
```bash
# Rebuild frontend
cd /opt/prs/prs-frontend-a
npm run build

# Rebuild Docker image
docker build -t prs-frontend:latest -f ../prs-deployment/dockerfiles/Dockerfile.frontend .

# Restart frontend
docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml restart frontend
```

**Configuration Issues:**
```bash
# Check environment variables
docker exec prs-onprem-frontend env | grep VITE

# Update API URL if needed
# Edit .env file: VITE_APP_API_URL=https://your-domain.com/api

# Restart frontend
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart frontend
```

### Backend Issues

#### Symptoms
- API endpoints return errors
- Database connection failures
- Authentication issues

#### Diagnosis

```bash
# Check backend logs
docker logs prs-onprem-backend --tail 100

# Test API endpoints
curl -s https://your-domain.com/api/health
curl -s https://your-domain.com/api/auth/status

# Check backend container
docker exec prs-onprem-backend npm run status
```

#### Solutions

**Application Errors:**
```bash
# Restart backend
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart backend

# Check for memory leaks
docker stats prs-onprem-backend

# Update dependencies if needed
docker exec prs-onprem-backend npm update
```

**Database Migration Issues:**
```bash
# Check migration status
docker exec prs-onprem-backend npm run migrate:status

# Run pending migrations
docker exec prs-onprem-backend npm run migrate

# Reset migrations if needed (DANGEROUS)
docker exec prs-onprem-backend npm run migrate:reset
docker exec prs-onprem-backend npm run migrate
```

## Emergency Procedures

### Complete System Recovery

```bash
#!/bin/bash
# Emergency system recovery procedure

echo "Starting emergency recovery..."

# Stop all services
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml down

# Clean Docker system
docker system prune -f

# Check and fix storage permissions
sudo chown -R 999:999 /mnt/hdd/postgresql-hot /mnt/hdd/postgresql-cold
sudo chown -R 999:999 /mnt/hdd/redis-data
sudo chown -R 472:472 /mnt/hdd/grafana-data

# Restart Docker daemon
sudo systemctl restart docker

# Start services one by one
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml up -d postgres
sleep 30

docker-compose -f 02-docker-configuration/docker-compose.onprem.yml up -d redis
sleep 10

docker-compose -f 02-docker-configuration/docker-compose.onprem.yml up -d backend
sleep 20

docker-compose -f 02-docker-configuration/docker-compose.onprem.yml up -d frontend nginx

# Run health checks
./scripts/system-health-check.sh

echo "Emergency recovery completed"
```

### Data Recovery

```bash
#!/bin/bash
# Emergency data recovery from backup

BACKUP_DATE="$1"
if [ -z "$BACKUP_DATE" ]; then
    echo "Usage: $0 <YYYYMMDD>"
    exit 1
fi

echo "Starting data recovery from $BACKUP_DATE..."

# Stop application services
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml stop backend frontend worker

# Restore database
BACKUP_FILE="/mnt/hdd/postgres-backups/daily/prs_full_backup_${BACKUP_DATE}_*.sql"
if [ -f $BACKUP_FILE ]; then
    docker exec prs-onprem-postgres-timescale pg_restore -U prs_admin -d prs_production --clean --if-exists "$BACKUP_FILE"
else
    echo "Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Restore Redis data
REDIS_BACKUP="/mnt/hdd/redis-backups/redis_backup_${BACKUP_DATE}_*.rdb.gz"
if [ -f $REDIS_BACKUP ]; then
    docker-compose -f 02-docker-configuration/docker-compose.onprem.yml stop redis
    gunzip -c "$REDIS_BACKUP" > /mnt/hdd/redis-data/dump.rdb
    docker-compose -f 02-docker-configuration/docker-compose.onprem.yml start redis
fi

# Restore file uploads
FILE_BACKUP="/mnt/hdd/file-backups/$BACKUP_DATE"
if [ -d "$FILE_BACKUP" ]; then
    rsync -av "$FILE_BACKUP/" /mnt/hdd/uploads/
fi

# Start services
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml start backend frontend worker

echo "Data recovery completed"
```

---

!!! success "Troubleshooting Guide"
    This comprehensive troubleshooting guide covers the most common issues and their solutions for the PRS on-premises deployment.

!!! tip "Prevention"
    Regular monitoring, maintenance, and backups are the best way to prevent issues. Follow the daily operations checklist to maintain system health.

!!! warning "Emergency Procedures"
    Emergency procedures should only be used when normal troubleshooting steps fail. Always ensure you have recent backups before performing emergency recovery.
