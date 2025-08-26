# Daily Operations

## Overview

This guide covers the daily operational tasks required to maintain the PRS on-premises deployment in optimal condition.

## Daily Operations Schedule

### Routine (8:00 AM)

#### Health Check

```bash
# Run automated health check
cd /opt/prs-deployment/scripts
./system-health-check.sh

# Check service status
docker-compose -f ../02-docker-configuration/docker-compose.onprem.yml ps

# Verify all services are healthy
docker-compose -f ../02-docker-configuration/docker-compose.onprem.yml ps --filter "health=healthy"
```

#### Monitoring

```bash
# Check storage usage
df -h /mnt/hdd /mnt/hdd

# Check RAID status
cat /proc/mdstat

# Monitor storage alerts
grep -i "storage\|disk\|raid" /var/log/syslog | tail -20
```

#### Health Check

```sql
-- Connect to database
docker exec -it prs-onprem-postgres-timescale psql -U prs_admin -d prs_production

-- Check database status
SELECT version();
SELECT * FROM timescaledb_information.license;

-- Check active connections
SELECT count(*) as active_connections FROM pg_stat_activity WHERE state = 'active';

-- Check database size
SELECT pg_size_pretty(pg_database_size('prs_production')) as database_size;

-- Check recent activity
SELECT COUNT(*) as recent_records FROM notifications WHERE created_at >= NOW() - INTERVAL '24 hours';

-- Check TimescaleDB compression status
SELECT * FROM timescaledb_status ORDER BY total_size_mb DESC LIMIT 10;

-- Check chunk compression effectiveness
SELECT
    hypertable_name,
    total_chunks,
    compressed_chunks,
    ROUND((compressed_chunks::numeric / total_chunks * 100), 1) as compression_percentage
FROM timescaledb_status
WHERE total_chunks > 0
ORDER BY compression_percentage ASC;
```

### Check (12:00 PM)

#### Monitoring

```bash
# Check system resources
htop

# Monitor container resources
docker stats --no-stream

# Check network usage
iftop -t -s 10

# Review application logs
docker logs prs-onprem-backend --tail 50 | grep -E "(ERROR|WARN)"
```

#### Health

```bash
# Test API endpoints
curl -s https://your-domain.com/api/health | jq '.'

# Check response times
time curl -s https://your-domain.com/api/health

# Test database connectivity
docker exec prs-onprem-backend npm run db:test

# Check Redis connectivity
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD ping
```

### Review (6:00 PM)

#### Analysis

```bash
# Review system logs
sudo journalctl --since "today" --priority=err

# Check Docker logs
docker-compose -f ../02-docker-configuration/docker-compose.onprem.yml logs --since="24h" | grep -E "(ERROR|FATAL|CRITICAL)"

# Review nginx access logs
docker logs prs-onprem-nginx --tail 100 | grep -v "200\|304"

# Check database logs
docker logs prs-onprem-postgres-timescale --tail 50 | grep -E "(ERROR|FATAL|WARNING)"
```

#### Verification

```bash
# Check backup status
ls -la /mnt/hdd/postgres-backups/ | head -10

# Verify latest backup
LATEST_BACKUP=$(ls -t /mnt/hdd/postgres-backups/*.sql | head -1)
echo "Latest backup: $LATEST_BACKUP"
ls -lh "$LATEST_BACKUP"

# Check backup logs
tail -20 /var/log/prs-backup.log
```

## Key Metrics to Monitor

### Metrics

| Metric | Target | Warning | Critical | Action |
|--------|--------|---------|----------|---------|
| **CPU Usage** | <60% | >70% | >85% | Investigate high CPU processes |
| **Memory Usage** | <75% | >80% | >90% | Check for memory leaks |
| **HDD Usage** | <80% | >85% | >90% | Archive old data |
| **HDD Usage** | <70% | >80% | >90% | Expand storage |
| **Network Usage** | <50% | >70% | >90% | Check network traffic |

### Metrics

| Metric | Target | Warning | Critical | Action |
|--------|--------|---------|----------|---------|
| **Response Time** | <200ms | >500ms | >1000ms | Performance tuning |
| **Error Rate** | <0.1% | >1% | >5% | Investigate errors |
| **Active Users** | Variable | >80 concurrent | >100 concurrent | Monitor capacity |
| **Database Connections** | <100 | >120 | >140 | Check connection pooling |

### Metrics

```sql
-- Check slow queries
SELECT query, calls, total_time, mean_time, rows
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;

-- Check table sizes
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;

-- Check TimescaleDB chunk status
SELECT
    hypertable_name,
    COUNT(*) as total_chunks,
    COUNT(*) FILTER (WHERE is_compressed) as compressed_chunks,
    COUNT(*) FILTER (WHERE tablespace_name = 'pg_default') as ssd_chunks,
    COUNT(*) FILTER (WHERE tablespace_name = 'pg_default') as hdd_chunks
FROM timescaledb_information.chunks
GROUP BY hypertable_name;
```

## Daily Maintenance Tasks

### Tasks (via cron)

```bash
# View current cron jobs
crontab -l

# Expected daily tasks:
# 0 2 * * * /opt/prs-deployment/scripts/backup-maintenance.sh
# 0 3 * * * /opt/prs-deployment/scripts/log-rotation.sh
# 0 4 * * * /opt/prs-deployment/scripts/cleanup-temp-files.sh
# 0 5 * * * /opt/prs-deployment/scripts/update-statistics.sh
```

### Tasks

#### Rotation

```bash
# Rotate application logs
docker exec prs-onprem-backend logrotate /etc/logrotate.conf

# Clean old Docker logs
docker system prune -f --filter "until=24h"

# Archive old logs to HDD
find /mnt/hdd/logs -name "*.log" -mtime +7 -exec mv {} /mnt/hdd/app-logs-archive/ \;
```

#### Maintenance

```sql
-- Update table statistics
ANALYZE notifications;
ANALYZE audit_logs;
ANALYZE requisitions;

-- Check for bloated tables
SELECT
    schemaname,
    tablename,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_dead_tup
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;

-- Vacuum if needed
VACUUM ANALYZE notifications;
```

#### Maintenance

```bash
# Check Redis memory usage
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD info memory

# Clear expired keys
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD eval "return #redis.call('keys', ARGV[1])" 0 "*expired*"

# Check cache hit ratio
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD info stats | grep keyspace
```

## Alert Response Procedures

### CPU Usage

```bash
# Identify CPU-intensive processes
top -o %CPU

# Check container CPU usage
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# If backend is high CPU:
docker exec prs-onprem-backend pm2 list
docker exec prs-onprem-backend pm2 monit
```

### Memory Usage

```bash
# Check memory usage by container
docker stats --format "table {{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Check for memory leaks in backend
docker exec prs-onprem-backend node --expose-gc -e "global.gc(); console.log(process.memoryUsage());"

# Restart service if memory leak detected
docker-compose -f ../02-docker-configuration/docker-compose.onprem.yml restart backend
```

### Alerts

```bash
# If SSD usage >85%
# 1. Check for large files
find /mnt/hdd -type f -size +100M -exec ls -lh {} \;

# 2. Compress old logs
find /mnt/hdd/logs -name "*.log" -mtime +1 -exec gzip {} \;

# 3. Move old data to HDD
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT move_chunk(chunk_name, 'pg_default')
FROM timescaledb_information.chunks
WHERE range_start < NOW() - INTERVAL '14 days'
AND tablespace_name = 'pg_default'
LIMIT 10;
"
```

### Connection Issues

```bash
# Check connection count
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT count(*) as connections, state
FROM pg_stat_activity
GROUP BY state;
"

# Kill idle connections if needed
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
AND query_start < NOW() - INTERVAL '1 hour';
"

# Restart backend if connection pool issues
docker-compose -f ../02-docker-configuration/docker-compose.onprem.yml restart backend
```

## Daily Checklist

### (8:00 AM)

- [ ] Run system health check script
- [ ] Verify all Docker services are running
- [ ] Check storage usage (SSD <85%, HDD <80%)
- [ ] Verify database connectivity
- [ ] Check overnight backup completion
- [ ] Review system logs for errors
- [ ] Test application endpoints

### (12:00 PM)

- [ ] Monitor system performance metrics
- [ ] Check application response times
- [ ] Review error logs
- [ ] Verify user activity levels
- [ ] Check Redis cache performance
- [ ] Monitor network usage

### (6:00 PM)

- [ ] Review daily log summaries
- [ ] Verify backup integrity
- [ ] Check TimescaleDB compression status
- [ ] Review performance metrics
- [ ] Plan any needed maintenance
- [ ] Update operational notes

## Daily Report Template

```bash
# Generate daily report
cat > /tmp/daily-report-$(date +%Y%m%d).txt << EOF
PRS Daily Operations Report - $(date +%Y-%m-%d)
================================================

System Status:
- CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%
- Memory Usage: $(free | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')
- HDD Usage: $(df -h /mnt/hdd | awk 'NR==2{print $5}')
- HDD Usage: $(df -h /mnt/hdd | awk 'NR==2{print $5}')

Service Status:
$(docker-compose -f /opt/prs-deployment/02-docker-configuration/docker-compose.onprem.yml ps --format table)

Database Status:
- Active Connections: $(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" | xargs)
- Database Size: $(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT pg_size_pretty(pg_database_size('prs_production'));" | xargs)

TimescaleDB Status:
- Total Hypertables: $(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT count(*) FROM timescaledb_information.hypertables;" | xargs)
- Total Chunks: $(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT count(*) FROM timescaledb_information.chunks;" | xargs)
- Compressed Chunks: $(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT count(*) FROM timescaledb_information.chunks WHERE is_compressed;" | xargs)
- Compression Ratio: $(docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -t -c "SELECT ROUND((SELECT count(*)::numeric FROM timescaledb_information.chunks WHERE is_compressed) / (SELECT count(*) FROM timescaledb_information.chunks) * 100, 1) || '%';" | xargs)

Backup Status:
- Latest Backup: $(ls -t /mnt/hdd/postgres-backups/*.sql 2>/dev/null | head -1 | xargs basename)
- Backup Size: $(ls -lh /mnt/hdd/postgres-backups/*.sql 2>/dev/null | head -1 | awk '{print $5}')

Issues Found:
$(grep -i "error\|critical\|fatal" /var/log/syslog | tail -5 || echo "No critical issues found")

EOF

# Email report (if configured)
# mail -s "PRS Daily Report - $(date +%Y-%m-%d)" admin@your-domain.com < /tmp/daily-report-$(date +%Y%m%d).txt
```

---

!!! tip "Automation"
    Most daily tasks can be automated using cron jobs and monitoring scripts. Focus manual effort on reviewing metrics and investigating any anomalies.

!!! warning "Escalation"
    If any critical thresholds are exceeded or services are unresponsive, follow the escalation procedures in the troubleshooting guide.
