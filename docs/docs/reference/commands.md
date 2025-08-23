# Command Reference

## Overview

This reference guide provides quick access to commonly used commands for managing the PRS on-premises deployment.

## Docker Commands

### Management

```bash
# Start all services
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml up -d

# Stop all services
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml down

# Restart all services
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart

# Restart specific service
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart backend

# View service status
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml ps

# View service logs
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml logs -f backend

# Scale service (if supported)
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml up -d --scale backend=2
```

### Operations

```bash
# Execute command in container
docker exec -it prs-onprem-backend bash
docker exec -it prs-onprem-postgres-timescale psql -U prs_admin -d prs_production

# Copy files to/from container
docker cp file.txt prs-onprem-backend:/tmp/
docker cp prs-onprem-backend:/tmp/file.txt ./

# View container resource usage
docker stats
docker stats prs-onprem-backend

# Inspect container configuration
docker inspect prs-onprem-backend

# View container logs
docker logs prs-onprem-backend --tail 100 -f
```

### Management

```bash
# Build images
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml build

# Pull latest images
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml pull

# List images
docker images

# Remove unused images
docker image prune -f

# Remove specific image
docker rmi prs-backend:latest
```

### and Network Management

```bash
# List volumes
docker volume ls

# Inspect volume
docker volume inspect prs_onprem_database_data

# List networks
docker network ls

# Inspect network
docker network inspect prs_onprem_network

# Clean up unused resources
docker system prune -f
```

## Database Commands

### Administration

```bash
# Connect to database
docker exec -it prs-onprem-postgres-timescale psql -U prs_admin -d prs_production

# Check database status
docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin

# Create database backup
docker exec prs-onprem-postgres-timescale pg_dump -U prs_admin -d prs_production > backup.sql

# Restore database backup
docker exec -i prs-onprem-postgres-timescale psql -U prs_admin -d prs_production < backup.sql

# View database size
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "SELECT pg_size_pretty(pg_database_size('prs_production'));"

# View active connections
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';"
```

### Commands

```sql
-- View hypertables
SELECT * FROM timescaledb_information.hypertables;

-- View chunks
SELECT * FROM timescaledb_information.chunks WHERE hypertable_name = 'notifications';

-- View compression stats
SELECT * FROM timescaledb_information.compressed_hypertable_stats;

-- View data movement policies
SELECT * FROM timescaledb_information.data_node_move_policies;

-- View background jobs
SELECT * FROM timescaledb_information.jobs;

-- Check chunk distribution
SELECT 
    hypertable_name,
    tablespace_name,
    COUNT(*) as chunk_count,
    pg_size_pretty(SUM(chunk_size)) as total_size
FROM timescaledb_information.chunks
GROUP BY hypertable_name, tablespace_name;

-- Manual compression
SELECT compress_chunk('_timescaledb_internal._hyper_1_1_chunk');

-- Manual data movement
SELECT move_chunk('_timescaledb_internal._hyper_1_1_chunk', 'hdd_cold');
```

### Maintenance

```sql
-- Update statistics
ANALYZE notifications;
ANALYZE audit_logs;

-- Vacuum tables
VACUUM ANALYZE notifications;

-- Check table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Check slow queries
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
ORDER BY total_time DESC 
LIMIT 10;

-- Kill long-running queries
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE state = 'active' 
AND query_start < NOW() - INTERVAL '1 hour';
```

## Redis Commands

### Administration

```bash
# Connect to Redis
docker exec -it prs-onprem-redis redis-cli -a $REDIS_PASSWORD

# Check Redis status
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD ping

# Get Redis info
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD info

# Monitor Redis commands
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD monitor

# Check memory usage
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD info memory

# Save Redis snapshot
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD bgsave
```

### Operations

```bash
# View all keys
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD keys "*"

# Get key value
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD get "key_name"

# Delete key
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD del "key_name"

# Check key TTL
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD ttl "key_name"

# Flush all data (DANGEROUS)
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD flushall

# Get database size
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD dbsize
```

## Monitoring Commands

### Monitoring

```bash
# Check system resources
htop
top
free -h
df -h

# Monitor disk I/O
iostat -x 1
iotop

# Monitor network
iftop
nethogs
ss -tuln

# Check system logs
journalctl -f
tail -f /var/log/syslog

# Monitor Docker resources
docker stats
docker system df
```

### Monitoring

```bash
# Check application logs
docker logs prs-onprem-backend --tail 100 -f
docker logs prs-onprem-frontend --tail 100 -f
docker logs prs-onprem-nginx --tail 100 -f

# Test API endpoints
curl -s https://your-domain.com/api/health | jq '.'
curl -I https://your-domain.com/

# Check response times
time curl -s https://your-domain.com/api/health

# Monitor application metrics
curl -s http://localhost:9090/metrics
```

### Testing

```bash
# Load testing with Apache Bench
ab -n 1000 -c 10 https://your-domain.com/
ab -n 500 -c 5 https://your-domain.com/api/health

# Database performance testing
docker exec prs-onprem-postgres-timescale pgbench -i -s 10 prs_production
docker exec prs-onprem-postgres-timescale pgbench -c 5 -j 2 -t 1000 prs_production

# Storage performance testing
sudo fio --name=test --filename=/mnt/ssd/test --size=1G --rw=randwrite --bs=4k --numjobs=4 --time_based --runtime=60
```

## Security Commands

### Certificate Management

```bash
# Check certificate validity
openssl x509 -in 02-docker-configuration/ssl/certificate.crt -text -noout

# Check certificate expiration
openssl x509 -in 02-docker-configuration/ssl/certificate.crt -noout -dates

# Test SSL connection
openssl s_client -connect your-domain.com:443 -servername your-domain.com

# Verify certificate chain
curl -vI https://your-domain.com/

# Renew Let's Encrypt certificate
certbot renew --dry-run
certbot renew
```

### Management

```bash
# Check firewall status
sudo ufw status verbose

# Add firewall rule
sudo ufw allow from 192.168.0.0/20 to any port 80

# Remove firewall rule
sudo ufw delete allow 80

# Reset firewall
sudo ufw --force reset

# Enable/disable firewall
sudo ufw enable
sudo ufw disable
```

### Scanning

```bash
# Check for security updates
sudo apt list --upgradable

# Scan for open ports
nmap -sS -O localhost
sudo netstat -tulpn | grep LISTEN

# Check fail2ban status
sudo fail2ban-client status
sudo fail2ban-client status sshd

# View authentication logs
sudo tail -f /var/log/auth.log
```

## Maintenance Commands

### Operations

```bash
# Run manual backup
./scripts/backup-maintenance.sh

# List backups
ls -la /mnt/hdd/postgres-backups/daily/
ls -la /mnt/hdd/redis-backups/

# Verify backup integrity
sha256sum -c /mnt/hdd/postgres-backups/daily/*.sha256

# Restore from backup
./scripts/restore-database.sh /mnt/hdd/postgres-backups/daily/backup_20240822.sql
```

### Management

```bash
# View application logs
tail -f /mnt/ssd/logs/application.log
tail -f /mnt/ssd/logs/error.log

# Rotate logs
./scripts/log-rotation.sh

# Archive old logs
find /mnt/ssd/logs -name "*.log" -mtime +7 -exec mv {} /mnt/hdd/app-logs-archive/ \;

# Compress logs
find /mnt/ssd/logs -name "*.log" -mtime +1 -exec gzip {} \;
```

### Cleanup

```bash
# Clean Docker resources
docker system prune -f
docker volume prune -f
docker image prune -f

# Clean temporary files
sudo find /tmp -type f -mtime +7 -delete
sudo find /var/tmp -type f -mtime +7 -delete

# Clean package cache
sudo apt autoremove
sudo apt autoclean

# Clean old logs
sudo journalctl --vacuum-time=30d
```

## Troubleshooting Commands

### Debugging

```bash
# Check service health
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml ps
docker inspect prs-onprem-backend | grep Health -A 10

# Debug container startup
docker logs prs-onprem-backend
docker exec prs-onprem-backend ps aux

# Check container resources
docker stats prs-onprem-backend
docker exec prs-onprem-backend free -h

# Network debugging
docker network inspect prs_onprem_network
docker exec prs-onprem-backend ping prs-onprem-postgres-timescale
```

### Debugging

```bash
# Check CPU usage
top -p $(docker inspect -f '{{.State.Pid}}' prs-onprem-backend)

# Check memory usage
cat /proc/$(docker inspect -f '{{.State.Pid}}' prs-onprem-backend)/status

# Check disk I/O
iotop -p $(docker inspect -f '{{.State.Pid}}' prs-onprem-backend)

# Check network connections
ss -tulpn | grep $(docker inspect -f '{{.State.Pid}}' prs-onprem-backend)
```

### Procedures

```bash
# Emergency stop all services
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml down

# Emergency restart
sudo systemctl restart docker
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml up -d

# Emergency database recovery
./scripts/restore-database.sh /mnt/hdd/postgres-backups/daily/latest-backup.sql

# Emergency storage cleanup
sudo find /mnt/ssd -name "*.tmp" -delete
sudo find /mnt/ssd/logs -name "*.log" -mtime +1 -exec gzip {} \;
```

---

!!! tip "Command Aliases"
    Create aliases for frequently used commands to improve efficiency:
    ```bash
    alias prs-logs='docker-compose -f 02-docker-configuration/docker-compose.onprem.yml logs -f'
    alias prs-ps='docker-compose -f 02-docker-configuration/docker-compose.onprem.yml ps'
    alias prs-restart='docker-compose -f 02-docker-configuration/docker-compose.onprem.yml restart'
    ```

!!! warning "Dangerous Commands"
    Commands marked as DANGEROUS can cause data loss. Always ensure you have recent backups before executing them.
