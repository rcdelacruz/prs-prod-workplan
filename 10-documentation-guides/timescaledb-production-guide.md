# 📊 TimescaleDB Production Guide for On-Premises Deployment

## 🎯 Overview

This guide provides comprehensive instructions for managing TimescaleDB in the PRS on-premises production environment, adapted from the EC2 setup to leverage dual storage architecture and 16GB RAM optimization.

## 🏗️ TimescaleDB Architecture

### Deployment Configuration
- **PostgreSQL Version**: 15 with TimescaleDB extension
- **Memory Allocation**: 6GB (37.5% of total 16GB RAM)
- **Storage Strategy**: Dual SSD/HDD with intelligent tiering
- **Hypertables**: 38 production hypertables (as implemented in migration)
- **Expected Load**: 100 concurrent users, 50,000+ rows/sec ingestion
- **Migration File**: `20250628120000-timescaledb-setup.js` with comprehensive coverage

### Storage Tiering Strategy
```
SSD Tablespace (ssd_hot):
├── Recent data (0-30 days)
├── Active chunks
├── Frequently accessed data
└── Real-time query workloads

HDD Tablespace (hdd_cold):
├── Historical data (30+ days)
├── Compressed chunks
├── Analytical workloads
└── Long-term retention data
```

## 🔧 Configuration Management

### PostgreSQL Configuration (16GB RAM Optimized)
```sql
-- Memory Settings
shared_buffers = 2GB                    -- 33% of allocated RAM
effective_cache_size = 4GB              -- 67% of allocated RAM
work_mem = 32MB                         -- For complex queries
maintenance_work_mem = 512MB            -- For maintenance operations

-- TimescaleDB Settings
timescaledb.max_background_workers = 16
max_worker_processes = 32
max_parallel_workers = 16
max_parallel_workers_per_gather = 4

-- Connection Settings
max_connections = 150                   -- 5x increase from EC2

-- Storage Settings
random_page_cost = 1.1                 -- SSD optimization
effective_io_concurrency = 200         -- SSD concurrent I/O
checkpoint_completion_target = 0.9     -- Smooth checkpoints
wal_buffers = 32MB                     -- WAL buffer size
```

### TimescaleDB Extension Configuration
```sql
-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Configure telemetry (disabled for on-premises)
ALTER SYSTEM SET timescaledb.telemetry = 'off';

-- Reload configuration
SELECT pg_reload_conf();
```

## 📊 Hypertable Management

### Creating Hypertables
```sql
-- Create hypertable with optimal chunk interval
SELECT create_hypertable(
    'user_activities',
    'timestamp',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE
);

-- Set tablespace for new chunks (SSD for hot data)
SELECT set_chunk_time_interval('user_activities', INTERVAL '1 day', 'ssd_hot');

-- Configure compression
ALTER TABLE user_activities SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'user_id',
    timescaledb.compress_orderby = 'timestamp DESC'
);
```

### Chunk Management
```sql
-- View chunk information
SELECT
    hypertable_name,
    chunk_name,
    chunk_schema,
    range_start,
    range_end,
    pg_size_pretty(chunk_size) as size,
    compression_status,
    tablespace_name
FROM timescaledb_information.chunks
ORDER BY range_start DESC;

-- Manual chunk compression
SELECT compress_chunk('_timescaledb_internal._hyper_1_1_chunk');

-- Move chunk to different tablespace
SELECT move_chunk(
    chunk => '_timescaledb_internal._hyper_1_1_chunk',
    destination_tablespace => 'hdd_cold'
);
```

## 🗜️ Compression Management

### Compression Policies
```sql
-- Add compression policy (compress data older than 7 days)
SELECT add_compression_policy('user_activities', INTERVAL '7 days');

-- Add compression policy for system metrics (compress after 3 days)
SELECT add_compression_policy('system_metrics', INTERVAL '3 days');

-- View compression policies
SELECT * FROM timescaledb_information.compression_settings;

-- Remove compression policy
SELECT remove_compression_policy('user_activities');
```

### Manual Compression Operations
```sql
-- Compress specific chunks
SELECT compress_chunk(chunk_name)
FROM timescaledb_information.chunks
WHERE hypertable_name = 'user_activities'
AND range_start < NOW() - INTERVAL '7 days'
AND NOT is_compressed;

-- Decompress chunk (if needed for updates)
SELECT decompress_chunk('_timescaledb_internal._hyper_1_1_chunk');

-- Check compression ratio
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

## 🔄 Data Lifecycle Management

### Automated Data Movement Policies
```sql
-- Create tablespaces for tiered storage
CREATE TABLESPACE ssd_hot LOCATION '/mnt/ssd/postgresql-hot';
CREATE TABLESPACE hdd_cold LOCATION '/mnt/hdd/postgresql-cold';

-- Add data movement policy (move chunks older than 30 days to HDD)
SELECT add_move_chunk_policy(
    'user_activities',
    INTERVAL '30 days',
    'hdd_cold'
);

-- Add data movement for system metrics (move after 14 days)
SELECT add_move_chunk_policy(
    'system_metrics',
    INTERVAL '14 days',
    'hdd_cold'
);

-- View data movement policies
SELECT * FROM timescaledb_information.move_chunk_policies;
```

### Retention Policies (Zero-Deletion Compliant)
```sql
-- Note: Zero-deletion policy means NO automatic data deletion
-- Instead, use compression and data movement for space management

-- View retention policies (should be empty for zero-deletion)
SELECT * FROM timescaledb_information.drop_chunks_policies;

-- If retention is needed (NOT recommended for zero-deletion policy):
-- SELECT add_retention_policy('table_name', INTERVAL '1 year');
```

## 📈 Performance Optimization

### Query Optimization
```sql
-- Create time-based indexes for better performance
CREATE INDEX CONCURRENTLY idx_user_activities_time_user
ON user_activities (timestamp DESC, user_id);

-- Create partial indexes for hot data
CREATE INDEX CONCURRENTLY idx_user_activities_recent
ON user_activities (user_id, timestamp DESC)
WHERE timestamp >= NOW() - INTERVAL '30 days';

-- Analyze tables for better query planning
ANALYZE user_activities;

-- Update table statistics
SELECT update_stats('user_activities');
```

### Continuous Aggregates
```sql
-- Create continuous aggregate for hourly summaries
CREATE MATERIALIZED VIEW user_activity_hourly
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', timestamp) AS hour,
    user_id,
    count(*) as activity_count,
    avg(duration) as avg_duration
FROM user_activities
GROUP BY hour, user_id;

-- Add refresh policy for continuous aggregate
SELECT add_continuous_aggregate_policy(
    'user_activity_hourly',
    start_offset => INTERVAL '1 day',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour'
);

-- Manually refresh continuous aggregate
CALL refresh_continuous_aggregate('user_activity_hourly', NULL, NULL);
```

## 🔍 Monitoring and Maintenance

### Health Check Queries
```sql
-- Check TimescaleDB version and status
SELECT * FROM timescaledb_information.license;

-- Check hypertable statistics
SELECT
    hypertable_name,
    num_chunks,
    table_size,
    index_size,
    total_size
FROM timescaledb_information.hypertables;

-- Check compression statistics
SELECT
    hypertable_name,
    compression_status,
    uncompressed_heap_size,
    uncompressed_index_size,
    compressed_heap_size,
    compressed_index_size
FROM timescaledb_information.compressed_chunk_stats;

-- Check background job status
SELECT * FROM timescaledb_information.jobs;
```

### Maintenance Operations
```sql
-- Vacuum and analyze hypertables
VACUUM ANALYZE user_activities;

-- Reindex hypertables
REINDEX TABLE user_activities;

-- Update statistics for all hypertables
SELECT update_stats(hypertable_name)
FROM timescaledb_information.hypertables;

-- Check for bloated tables
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

## 🚨 Troubleshooting

### Common Issues and Solutions

#### High Memory Usage
```sql
-- Check memory usage by queries
SELECT
    query,
    calls,
    total_time,
    mean_time,
    rows
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;

-- Check for long-running queries
SELECT
    pid,
    now() - pg_stat_activity.query_start AS duration,
    query
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';
```

#### Compression Issues
```sql
-- Check failed compression jobs
SELECT * FROM timescaledb_information.job_stats
WHERE job_type = 'compression' AND last_run_success = false;

-- Retry failed compression
SELECT run_job(job_id)
FROM timescaledb_information.jobs
WHERE job_type = 'compression';
```

#### Storage Issues
```sql
-- Check tablespace usage
SELECT
    spcname as tablespace_name,
    pg_size_pretty(pg_tablespace_size(spcname)) as size
FROM pg_tablespace;

-- Find largest chunks
SELECT
    chunk_name,
    pg_size_pretty(chunk_size) as size,
    tablespace_name
FROM timescaledb_information.chunks
ORDER BY chunk_size DESC
LIMIT 10;
```

## 📋 Daily Operations Checklist

### Daily Tasks
- [ ] Check compression job status
- [ ] Monitor chunk creation rate
- [ ] Verify data movement policies
- [ ] Check storage usage (SSD/HDD)
- [ ] Review slow query log

### Weekly Tasks
- [ ] Analyze hypertable statistics
- [ ] Review compression ratios
- [ ] Check continuous aggregate refresh
- [ ] Vacuum and analyze large tables
- [ ] Review and optimize queries

### Monthly Tasks
- [ ] Review data retention policies
- [ ] Optimize chunk intervals
- [ ] Review and update indexes
- [ ] Performance tuning analysis
- [ ] Capacity planning review

## 🔧 Emergency Procedures

### Emergency Compression (SSD Full)
```sql
-- Emergency compress all eligible chunks
SELECT compress_chunk(chunk_name)
FROM timescaledb_information.chunks
WHERE hypertable_name = 'user_activities'
AND range_start < NOW() - INTERVAL '3 days'
AND NOT is_compressed;
```

### Emergency Data Movement (SSD Critical)
```sql
-- Move older chunks to HDD immediately
SELECT move_chunk(chunk_name, 'hdd_cold')
FROM timescaledb_information.chunks
WHERE hypertable_name = 'user_activities'
AND range_start < NOW() - INTERVAL '14 days'
AND tablespace_name = 'ssd_hot';
```

---

**Document Version**: 1.0
**Created**: 2025-08-13
**Last Updated**: 2025-08-13
**Status**: Production Ready
