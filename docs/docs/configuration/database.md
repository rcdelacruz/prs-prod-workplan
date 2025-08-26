# Database Configuration

## Overview

This guide covers advanced database configuration for optimal performance, security, and reliability in the PRS on-premises deployment.

## PostgreSQL Configuration

### Memory Configuration

```sql
-- Memory settings optimized for 16GB RAM system
-- Allocating 6GB total to PostgreSQL

-- Shared memory (33% of allocated RAM)
ALTER SYSTEM SET shared_buffers = '2GB';

-- Cache size hint (67% of allocated RAM)
ALTER SYSTEM SET effective_cache_size = '4GB';

-- Working memory per operation
ALTER SYSTEM SET work_mem = '32MB';

-- Maintenance operations memory
ALTER SYSTEM SET maintenance_work_mem = '512MB';

-- WAL buffer size
ALTER SYSTEM SET wal_buffers = '32MB';

-- Reload configuration
SELECT pg_reload_conf();
```

### Connection Management

```sql
-- Connection settings for high concurrency
ALTER SYSTEM SET max_connections = 150;

-- Connection pooling optimization
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements,timescaledb';

-- Background worker processes
ALTER SYSTEM SET max_worker_processes = 32;
ALTER SYSTEM SET max_parallel_workers = 16;
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;

-- TimescaleDB background workers
ALTER SYSTEM SET timescaledb.max_background_workers = 16;

-- Reload configuration
SELECT pg_reload_conf();
```

### Storage Optimization

```sql
-- SSD optimization settings
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;
ALTER SYSTEM SET seq_page_cost = 1.0;

-- Checkpoint configuration
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET checkpoint_timeout = '15min';
ALTER SYSTEM SET max_wal_size = '2GB';
ALTER SYSTEM SET min_wal_size = '512MB';

-- Vacuum and autovacuum settings
ALTER SYSTEM SET autovacuum_max_workers = 6;
ALTER SYSTEM SET autovacuum_naptime = '30s';
ALTER SYSTEM SET autovacuum_vacuum_threshold = 50;
ALTER SYSTEM SET autovacuum_analyze_threshold = 50;

-- Reload configuration
SELECT pg_reload_conf();
```

## TimescaleDB Configuration

### Hypertable Setup

```sql
-- Create hypertables for time-series data
SELECT create_hypertable('notifications', 'created_at', chunk_time_interval => INTERVAL '1 day');
SELECT create_hypertable('audit_logs', 'created_at', chunk_time_interval => INTERVAL '1 day');
SELECT create_hypertable('histories', 'created_at', chunk_time_interval => INTERVAL '1 day');

-- Create hypertables for business data with longer intervals
SELECT create_hypertable('requisitions', 'created_at', chunk_time_interval => INTERVAL '7 days');
SELECT create_hypertable('purchase_orders', 'created_at', chunk_time_interval => INTERVAL '7 days');
SELECT create_hypertable('delivery_receipts', 'created_at', chunk_time_interval => INTERVAL '7 days');

-- Verify hypertables
SELECT * FROM timescaledb_information.hypertables;
```

### Compression Configuration

```sql
-- Configure compression for optimal storage
ALTER TABLE notifications SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'user_id',
    timescaledb.compress_orderby = 'created_at DESC'
);

ALTER TABLE audit_logs SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'user_id, action',
    timescaledb.compress_orderby = 'created_at DESC'
);

ALTER TABLE requisitions SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'department_id, status',
    timescaledb.compress_orderby = 'created_at DESC'
);

-- Add compression policies
SELECT add_compression_policy('notifications', INTERVAL '7 days');
SELECT add_compression_policy('audit_logs', INTERVAL '7 days');
SELECT add_compression_policy('requisitions', INTERVAL '30 days');
```

### Data Movement Policies

```sql
-- Configure automatic data movement to HDD storage
SELECT add_move_chunk_policy('notifications', INTERVAL '30 days', 'pg_default');
SELECT add_move_chunk_policy('audit_logs', INTERVAL '30 days', 'pg_default');
SELECT add_move_chunk_policy('requisitions', INTERVAL '30 days', 'pg_default');
SELECT add_move_chunk_policy('purchase_orders', INTERVAL '30 days', 'pg_default');

-- Configure faster movement for history tables
SELECT add_move_chunk_policy('requisition_canvass_histories', INTERVAL '14 days', 'pg_default');
SELECT add_move_chunk_policy('requisition_item_histories', INTERVAL '14 days', 'pg_default');
```

## Index Optimization

### Primary Indexes

```sql
-- Time-based indexes for efficient queries
CREATE INDEX CONCURRENTLY idx_notifications_time
ON notifications (created_at DESC);

CREATE INDEX CONCURRENTLY idx_audit_logs_time
ON audit_logs (created_at DESC);

CREATE INDEX CONCURRENTLY idx_requisitions_time
ON requisitions (created_at DESC);
```

### Composite Indexes

```sql
-- User-specific time-based queries
CREATE INDEX CONCURRENTLY idx_notifications_user_time
ON notifications (user_id, created_at DESC);

CREATE INDEX CONCURRENTLY idx_audit_logs_user_action_time
ON audit_logs (user_id, action, created_at DESC);

-- Department-specific queries
CREATE INDEX CONCURRENTLY idx_requisitions_dept_status_time
ON requisitions (department_id, status, created_at DESC);
```

### Partial Indexes

```sql
-- Indexes for hot data only (performance optimization)
CREATE INDEX CONCURRENTLY idx_notifications_recent
ON notifications (user_id, created_at DESC)
WHERE created_at >= NOW() - INTERVAL '30 days';

CREATE INDEX CONCURRENTLY idx_requisitions_active
ON requisitions (department_id, status, created_at DESC)
WHERE status IN ('pending', 'approved', 'processing');
```

## Query Optimization

### Statistics Configuration

```sql
-- Increase statistics target for better query planning
ALTER SYSTEM SET default_statistics_target = 100;

-- Enable constraint exclusion for partitioning
ALTER SYSTEM SET constraint_exclusion = 'partition';

-- Query planning settings
ALTER SYSTEM SET enable_partitionwise_join = on;
ALTER SYSTEM SET enable_partitionwise_aggregate = on;

-- Reload configuration
SELECT pg_reload_conf();
```

### Query Monitoring

```sql
-- Enable query statistics collection
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements,timescaledb';
ALTER SYSTEM SET pg_stat_statements.track = 'all';
ALTER SYSTEM SET pg_stat_statements.max = 10000;

-- Create extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- View slow queries
SELECT
    query,
    calls,
    total_time,
    mean_time,
    rows
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;
```

## Connection Pooling

### Application-Level Pooling

```javascript
// Backend connection pool configuration
const poolConfig = {
  host: process.env.POSTGRES_HOST,
  database: process.env.POSTGRES_DB,
  user: process.env.POSTGRES_USER,
  password: process.env.POSTGRES_PASSWORD,
  port: process.env.POSTGRES_PORT,

  // Pool settings optimized for on-premises
  min: 5,                    // Minimum connections
  max: 20,                   // Maximum connections (vs 3 on cloud)
  acquire: 30000,            // Connection timeout (30s)
  idle: 10000,               // Idle timeout (10s)
  evict: 20000,              // Eviction timeout (20s)

  // Retry configuration
  retry: {
    max: 3,
    timeout: 5000,
    match: [/ECONNRESET/, /ETIMEDOUT/]
  }
};
```

### PgBouncer Configuration (Optional)

```ini
# /etc/pgbouncer/pgbouncer.ini
[databases]
prs_production = host=localhost port=5432 dbname=prs_production

[pgbouncer]
listen_port = 6432
listen_addr = 127.0.0.1
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# Pool settings
pool_mode = transaction
max_client_conn = 200
default_pool_size = 25
reserve_pool_size = 5

# Timeouts
server_connect_timeout = 15
server_login_retry = 15
query_timeout = 0
query_wait_timeout = 120
client_idle_timeout = 0
server_idle_timeout = 600
```

## Backup Configuration

### Continuous Archiving

```sql
-- Configure WAL archiving
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET archive_mode = 'on';
ALTER SYSTEM SET archive_command = 'cp %p /var/lib/postgresql/wal-archive/%f';
ALTER SYSTEM SET archive_timeout = '300s';

-- Configure for streaming replication (future use)
ALTER SYSTEM SET max_wal_senders = 3;
ALTER SYSTEM SET wal_keep_segments = 64;

-- Reload configuration
SELECT pg_reload_conf();
```

### Backup Scheduling

```bash
# Full backup script configuration
cat > /opt/prs-deployment/scripts/backup-config.sh << 'EOF'
#!/bin/bash

# Backup configuration
BACKUP_DIR="/mnt/hdd/postgres-backups"
RETENTION_DAYS=30
COMPRESSION_LEVEL=9

# Database connection
PGHOST="localhost"
PGPORT="5432"
PGUSER="prs_admin"
PGDATABASE="prs_production"

# Backup types
FULL_BACKUP_SCHEDULE="0 2 * * *"      # Daily at 2 AM
INCREMENTAL_SCHEDULE="0 */6 * * *"     # Every 6 hours
WAL_ARCHIVE_SCHEDULE="*/5 * * * *"     # Every 5 minutes

export PGHOST PGPORT PGUSER PGDATABASE
EOF
```

## Security Configuration

### User Management

```sql
-- Create role hierarchy
CREATE ROLE prs_readonly;
CREATE ROLE prs_readwrite;
CREATE ROLE prs_admin_role;

-- Grant permissions
GRANT CONNECT ON DATABASE prs_production TO prs_readonly;
GRANT USAGE ON SCHEMA public TO prs_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO prs_readonly;

GRANT prs_readonly TO prs_readwrite;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO prs_readwrite;

GRANT prs_readwrite TO prs_admin_role;
GRANT CREATE ON SCHEMA public TO prs_admin_role;

-- Create application users
CREATE USER prs_app_user WITH PASSWORD 'secure_app_password';
GRANT prs_readwrite TO prs_app_user;

CREATE USER prs_readonly_user WITH PASSWORD 'secure_readonly_password';
GRANT prs_readonly TO prs_readonly_user;
```

### Access Control

```sql
-- Configure connection limits
ALTER ROLE prs_admin CONNECTION LIMIT 10;
ALTER ROLE prs_app_user CONNECTION LIMIT 50;
ALTER ROLE prs_readonly_user CONNECTION LIMIT 20;

-- Set session timeouts
ALTER ROLE prs_app_user SET statement_timeout = '30s';
ALTER ROLE prs_readonly_user SET statement_timeout = '60s';

-- Restrict dangerous functions
REVOKE EXECUTE ON FUNCTION pg_read_file(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pg_ls_dir(text) FROM PUBLIC;
```

## Monitoring Configuration

### Performance Monitoring

```sql
-- Create monitoring views
CREATE OR REPLACE VIEW v_database_stats AS
SELECT
    datname,
    numbackends as connections,
    xact_commit as commits,
    xact_rollback as rollbacks,
    blks_read,
    blks_hit,
    round(blks_hit::numeric / (blks_hit + blks_read) * 100, 2) as cache_hit_ratio
FROM pg_stat_database
WHERE datname = 'prs_production';

CREATE OR REPLACE VIEW v_table_stats AS
SELECT
    schemaname,
    tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;
```

### TimescaleDB Monitoring

```sql
-- Create TimescaleDB monitoring views
CREATE OR REPLACE VIEW v_chunk_stats AS
SELECT
    hypertable_name,
    chunk_name,
    'HDD (default)' as storage_location,
    is_compressed,
    pg_size_pretty(chunk_size) as size,
    range_start,
    range_end
FROM timescaledb_information.chunks
ORDER BY hypertable_name, range_start DESC;

CREATE OR REPLACE VIEW v_compression_stats AS
SELECT
    hypertable_name,
    pg_size_pretty(before_compression_total_bytes) as before_compression,
    pg_size_pretty(after_compression_total_bytes) as after_compression,
    round(
        (before_compression_total_bytes::numeric - after_compression_total_bytes::numeric)
        / before_compression_total_bytes::numeric * 100, 2
    ) as compression_ratio_percent
FROM timescaledb_information.compressed_hypertable_stats;
```

## Maintenance Procedures

### Daily Maintenance

```sql
-- Update table statistics
ANALYZE notifications;
ANALYZE audit_logs;
ANALYZE requisitions;

-- Check for bloated tables
SELECT
    schemaname,
    tablename,
    n_dead_tup,
    n_live_tup,
    round(n_dead_tup::numeric / (n_live_tup + n_dead_tup) * 100, 2) as dead_ratio
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY dead_ratio DESC;
```

### Weekly Maintenance

```sql
-- Vacuum and analyze all tables
VACUUM ANALYZE;

-- Reindex if needed (check for index bloat first)
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC;
```

### Monthly Maintenance

```sql
-- Full vacuum for heavily updated tables
VACUUM FULL notifications;
VACUUM FULL audit_logs;

-- Update statistics targets if needed
ALTER TABLE notifications ALTER COLUMN created_at SET STATISTICS 1000;
ALTER TABLE requisitions ALTER COLUMN status SET STATISTICS 1000;

-- Analyze after statistics changes
ANALYZE notifications;
ANALYZE requisitions;
```

---

!!! success "Database Optimized"
    Your PostgreSQL/TimescaleDB configuration is now optimized for high-performance on-premises deployment with automatic data lifecycle management.

!!! tip "Performance Monitoring"
    Regularly monitor the created views and adjust configuration based on actual usage patterns and performance metrics.

!!! warning "Configuration Changes"
    Always test configuration changes in a staging environment before applying to production, and monitor performance after changes.
