# Testing & Validation

## Overview

This guide provides comprehensive testing procedures to validate your PRS on-premises deployment before production use.

## Pre-Production Testing

### System Validation Tests

#### Infrastructure Testing

```bash
# System resource validation
./scripts/system-health-check.sh --comprehensive

# Storage performance testing
sudo fio --name=ssd-test --filename=/mnt/hdd/test --size=1G --rw=randwrite --bs=4k --numjobs=4 --time_based --runtime=60
sudo fio --name=hdd-test --filename=/mnt/hdd/test --size=1G --rw=randwrite --bs=64k --numjobs=2 --time_based --runtime=60

# Network performance testing
iperf3 -c target-server -t 60 -P 4

# Memory stress testing
stress-ng --vm 4 --vm-bytes 75% --timeout 300s --metrics-brief
```

#### Service Health Testing

```bash
# Verify all services are running
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml ps

# Check service health endpoints
curl -f https://your-domain.com/api/health
curl -f https://your-domain.com/health

# Database connectivity test
docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin

# Redis connectivity test
docker exec prs-onprem-redis redis-cli -a $REDIS_PASSWORD ping
```

### Application Testing

#### API Endpoint Testing

```bash
# Health check endpoint
curl -s https://your-domain.com/api/health | jq '.'
# Expected: {"status": "ok", "timestamp": "..."}

# Authentication endpoint
curl -X POST https://your-domain.com/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "test", "password": "test"}'

# Protected endpoint (requires authentication)
curl -H "Authorization: Bearer $TOKEN" https://your-domain.com/api/user/profile

# File upload endpoint
curl -X POST https://your-domain.com/api/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@test-file.pdf"
```

#### Database Testing

```sql
-- Connect to database
docker exec -it prs-onprem-postgres-timescale psql -U prs_admin -d prs_production

-- Test basic operations
INSERT INTO notifications (user_id, message, created_at) 
VALUES (1, 'Test notification', NOW());

SELECT COUNT(*) FROM notifications;

-- Test TimescaleDB functionality
SELECT * FROM timescaledb_information.hypertables;

-- Test compression
SELECT * FROM timescaledb_information.compressed_hypertable_stats;

-- Test data movement
SELECT 
    hypertable_name,
    tablespace_name,
    COUNT(*) as chunk_count
FROM timescaledb_information.chunks
GROUP BY hypertable_name, tablespace_name;
```

## Performance Testing

### Load Testing

#### Application Load Testing

```bash
# Install Apache Bench
sudo apt install apache2-utils

# Basic load test (100 requests, 10 concurrent)
ab -n 100 -c 10 https://your-domain.com/

# API load test
ab -n 500 -c 20 -H "Authorization: Bearer $TOKEN" https://your-domain.com/api/health

# Sustained load test (5 minutes)
ab -t 300 -c 50 https://your-domain.com/
```

#### Database Load Testing

```bash
# Install pgbench
sudo apt install postgresql-client

# Initialize pgbench
docker exec prs-onprem-postgres-timescale pgbench -i -s 10 prs_production

# Run benchmark (10 clients, 1000 transactions each)
docker exec prs-onprem-postgres-timescale pgbench -c 10 -j 2 -t 1000 prs_production

# Custom benchmark with application-like queries
docker exec prs-onprem-postgres-timescale pgbench -c 20 -j 4 -T 300 -f custom-queries.sql prs_production
```

#### Concurrent User Testing

```bash
# Create concurrent user simulation script
cat > concurrent-user-test.sh << 'EOF'
#!/bin/bash
USERS=${1:-50}
DURATION=${2:-300}

echo "Testing $USERS concurrent users for $DURATION seconds"

for i in $(seq 1 $USERS); do
    (
        while [ $SECONDS -lt $DURATION ]; do
            curl -s https://your-domain.com/api/health > /dev/null
            sleep $(( RANDOM % 5 + 1 ))
        done
    ) &
done

wait
echo "Concurrent user test completed"
EOF

chmod +x concurrent-user-test.sh

# Test 100 concurrent users for 5 minutes
./concurrent-user-test.sh 100 300
```

### Performance Benchmarks

#### Response Time Testing

```bash
# Create response time test script
cat > response-time-test.sh << 'EOF'
#!/bin/bash

echo "Testing response times..."

# Test various endpoints
endpoints=(
    "/"
    "/api/health"
    "/api/auth/status"
    "/api/dashboard"
)

for endpoint in "${endpoints[@]}"; do
    echo "Testing $endpoint:"
    curl -w "Time: %{time_total}s, Size: %{size_download} bytes\n" \
         -o /dev/null -s https://your-domain.com$endpoint
done
EOF

chmod +x response-time-test.sh
./response-time-test.sh
```

#### Throughput Testing

```bash
# Database throughput test
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT 
    schemaname,
    tablename,
    n_tup_ins + n_tup_upd + n_tup_del as total_operations,
    (n_tup_ins + n_tup_upd + n_tup_del) / EXTRACT(EPOCH FROM (now() - stats_reset)) as ops_per_second
FROM pg_stat_user_tables 
WHERE n_tup_ins + n_tup_upd + n_tup_del > 0
ORDER BY ops_per_second DESC;
"

# Application throughput monitoring
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
```

## Security Testing

### SSL/TLS Testing

```bash
# Test SSL configuration
openssl s_client -connect your-domain.com:443 -servername your-domain.com

# Check SSL certificate
curl -vI https://your-domain.com/

# Test SSL Labs rating (external)
# Visit: https://www.ssllabs.com/ssltest/analyze.html?d=your-domain.com

# Test security headers
curl -I https://your-domain.com/ | grep -E "(Strict-Transport-Security|X-Frame-Options|X-Content-Type-Options)"
```

### Authentication Testing

```bash
# Test authentication endpoints
# Valid login
curl -X POST https://your-domain.com/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "correct_password"}'

# Invalid login
curl -X POST https://your-domain.com/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "wrong_password"}'

# Test rate limiting
for i in {1..10}; do
    curl -X POST https://your-domain.com/api/auth/login \
      -H "Content-Type: application/json" \
      -d '{"username": "admin", "password": "wrong_password"}'
done
```

### Access Control Testing

```bash
# Test unauthorized access
curl -I https://your-domain.com/api/admin/users
# Should return 401 Unauthorized

# Test with valid token
curl -H "Authorization: Bearer $VALID_TOKEN" https://your-domain.com/api/user/profile
# Should return 200 OK

# Test with invalid token
curl -H "Authorization: Bearer invalid_token" https://your-domain.com/api/user/profile
# Should return 401 Unauthorized
```

## Data Integrity Testing

### Backup and Recovery Testing

#### Database Backup Testing

```bash
# Create test data
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
INSERT INTO notifications (user_id, message, created_at) 
SELECT 
    (random() * 100)::int + 1,
    'Test message ' || generate_series,
    NOW() - (random() * interval '30 days')
FROM generate_series(1, 1000);
"

# Create backup
./scripts/backup-maintenance.sh

# Verify backup exists
ls -la /mnt/hdd/postgres-backups/daily/

# Test backup integrity
LATEST_BACKUP=$(ls -t /mnt/hdd/postgres-backups/daily/*.sql | head -1)
sha256sum -c "${LATEST_BACKUP}.sha256"
```

#### Recovery Testing

```bash
# Create test database for recovery testing
docker exec prs-onprem-postgres-timescale psql -U prs_admin -c "CREATE DATABASE prs_test;"

# Restore backup to test database
docker exec prs-onprem-postgres-timescale pg_restore -U prs_admin -d prs_test --clean --if-exists "$LATEST_BACKUP"

# Verify data integrity
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_test -c "SELECT COUNT(*) FROM notifications;"

# Cleanup test database
docker exec prs-onprem-postgres-timescale psql -U prs_admin -c "DROP DATABASE prs_test;"
```

### Data Consistency Testing

```sql
-- Test referential integrity
SELECT 
    conname,
    conrelid::regclass AS table_name,
    confrelid::regclass AS referenced_table
FROM pg_constraint 
WHERE contype = 'f';

-- Test data consistency across tables
SELECT 
    'users' as table_name,
    COUNT(*) as record_count
FROM users
UNION ALL
SELECT 
    'notifications',
    COUNT(*)
FROM notifications;

-- Test TimescaleDB chunk consistency
SELECT 
    hypertable_name,
    COUNT(*) as total_chunks,
    COUNT(*) FILTER (WHERE is_compressed) as compressed_chunks,
    COUNT(*) FILTER (WHERE tablespace_name = 'pg_default') as ssd_chunks,
    COUNT(*) FILTER (WHERE tablespace_name = 'pg_default') as hdd_chunks
FROM timescaledb_information.chunks
GROUP BY hypertable_name;
```

## Monitoring Testing

### Metrics Collection Testing

```bash
# Test Prometheus metrics collection
curl -s http://localhost:9090/metrics | head -20

# Test application metrics
curl -s https://your-domain.com/metrics | grep -E "(http_requests|database_connections)"

# Test custom metrics
curl -s http://localhost:9100/metrics | grep -E "(node_cpu|node_memory|node_disk)"
```

### Alert Testing

```bash
# Test alert rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.type=="alerting")'

# Trigger test alert (high CPU)
stress-ng --cpu $(nproc) --timeout 300s &

# Check alert status
curl -s http://localhost:9090/api/v1/alerts | jq '.data[] | select(.state=="firing")'
```

### Dashboard Testing

```bash
# Test Grafana API
curl -s -H "Authorization: Bearer $GRAFANA_API_KEY" http://localhost:3001/api/health

# Test dashboard data
curl -s -H "Authorization: Bearer $GRAFANA_API_KEY" \
  "http://localhost:3001/api/datasources/proxy/1/api/v1/query?query=up"
```

## User Acceptance Testing

### Functional Testing Checklist

#### User Management
- [ ] User registration works
- [ ] User login/logout works
- [ ] Password reset works
- [ ] User profile updates work
- [ ] Role-based access control works

#### Core Functionality
- [ ] Create requisition works
- [ ] Approve requisition works
- [ ] Generate purchase order works
- [ ] Upload documents works
- [ ] Search functionality works
- [ ] Reporting works

#### Performance Requirements
- [ ] Page load time <2 seconds
- [ ] API response time <500ms
- [ ] File upload works for 50MB files
- [ ] System supports 100+ concurrent users
- [ ] Database queries complete <1 second

### Browser Compatibility Testing

```bash
# Test with different user agents
curl -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" https://your-domain.com/
curl -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" https://your-domain.com/
curl -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" https://your-domain.com/
```

## Automated Testing

### Test Automation Script

```bash
#!/bin/bash
# automated-test-suite.sh

DOMAIN="your-domain.com"
LOG_FILE="/tmp/prs-test-results-$(date +%Y%m%d_%H%M%S).log"

echo "Starting PRS Automated Test Suite" | tee "$LOG_FILE"
echo "=================================" | tee -a "$LOG_FILE"

# Test 1: Service Health
echo "Testing service health..." | tee -a "$LOG_FILE"
if curl -f -s https://$DOMAIN/api/health > /dev/null; then
    echo "✓ API health check passed" | tee -a "$LOG_FILE"
else
    echo "✗ API health check failed" | tee -a "$LOG_FILE"
fi

# Test 2: Database Connectivity
echo "Testing database connectivity..." | tee -a "$LOG_FILE"
if docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin > /dev/null; then
    echo "✓ Database connectivity passed" | tee -a "$LOG_FILE"
else
    echo "✗ Database connectivity failed" | tee -a "$LOG_FILE"
fi

# Test 3: Performance
echo "Testing performance..." | tee -a "$LOG_FILE"
RESPONSE_TIME=$(curl -w "%{time_total}" -o /dev/null -s https://$DOMAIN/)
if (( $(echo "$RESPONSE_TIME < 2.0" | bc -l) )); then
    echo "✓ Response time test passed ($RESPONSE_TIME seconds)" | tee -a "$LOG_FILE"
else
    echo "✗ Response time test failed ($RESPONSE_TIME seconds)" | tee -a "$LOG_FILE"
fi

# Test 4: SSL Certificate
echo "Testing SSL certificate..." | tee -a "$LOG_FILE"
if openssl s_client -connect $DOMAIN:443 -servername $DOMAIN < /dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
    echo "✓ SSL certificate test passed" | tee -a "$LOG_FILE"
else
    echo "✗ SSL certificate test failed" | tee -a "$LOG_FILE"
fi

echo "Test suite completed. Results saved to: $LOG_FILE"
```

## Test Results Documentation

### Test Report Template

```markdown
# PRS Deployment Test Report

**Date**: $(date)
**Environment**: Production
**Tester**: [Name]

## Test Summary
- Total Tests: [number]
- Passed: [number]
- Failed: [number]
- Success Rate: [percentage]

## Performance Results
- Average Response Time: [time]
- Peak Concurrent Users: [number]
- Database Query Performance: [time]
- Storage Performance: [IOPS]

## Security Results
- SSL Rating: [A+/A/B/etc]
- Authentication: [Pass/Fail]
- Authorization: [Pass/Fail]
- Security Headers: [Pass/Fail]

## Issues Found
1. [Issue description]
   - Severity: [High/Medium/Low]
   - Status: [Open/Resolved]
   - Resolution: [Description]

## Recommendations
1. [Recommendation]
2. [Recommendation]

## Sign-off
- Technical Lead: [Name] [Date]
- System Administrator: [Name] [Date]
- Business Owner: [Name] [Date]
```

---

!!! success "Testing Complete"
    Comprehensive testing ensures your PRS deployment meets performance, security, and reliability requirements before production use.

!!! tip "Continuous Testing"
    Implement automated testing as part of your deployment pipeline to catch issues early and maintain system quality.

!!! warning "Production Readiness"
    Complete all testing phases and resolve any issues before declaring the system production-ready.
