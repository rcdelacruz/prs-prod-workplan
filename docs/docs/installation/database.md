# Database Setup

## Overview

This guide covers the complete setup of TimescaleDB with HDD-only storage architecture for the PRS on-premises deployment.

## TimescaleDB Installation

### Container Configuration

The database runs in a Docker container with optimized settings for production use:

```yaml
postgres:
  image: timescale/timescaledb:latest-pg15
  container_name: prs-onprem-postgres-timescale
  restart: unless-stopped
  environment:
    - POSTGRES_DB=${POSTGRES_DB}
    - POSTGRES_USER=${POSTGRES_USER}
    - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    - TIMESCALEDB_TELEMETRY=off
  command: >
    postgres
    -c max_connections=150
    -c shared_buffers=2GB
    -c effective_cache_size=4GB
    -c work_mem=32MB
    -c maintenance_work_mem=512MB
    -c random_page_cost=1.1
    -c effective_io_concurrency=200
    -c shared_preload_libraries=timescaledb
  volumes:
    - database_data:/var/lib/postgresql/data
    - /mnt/hdd/postgresql-hot:/mnt/hdd/postgresql-hot
    - /mnt/hdd/postgresql-cold:/mnt/hdd/postgresql-cold
    - /mnt/hdd/postgres-backups:/var/lib/postgresql/backups
```

### Database Initialization

#### Connect to Database

```bash
# Wait for PostgreSQL to be ready
docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin

# Connect to database
docker exec -it prs-onprem-postgres-timescale psql -U prs_admin -d prs_production
```

#### Enable TimescaleDB Extension

```sql
-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Verify installation
SELECT * FROM timescaledb_information.license;

-- Configure telemetry (disabled for on-premises)
ALTER SYSTEM SET timescaledb.telemetry = 'off';
SELECT pg_reload_conf();
```

## Dual Storage Configuration

### Create Tablespaces

```sql
-- Create tablespaces for tiered storage
-- Tablespace creation not needed (HDD-only)
-- Tablespace creation not needed (HDD-only)

-- Set default tablespace for new chunks
ALTER DATABASE prs_production SET default_tablespace = pg_default;

-- Verify tablespaces
SELECT spcname, pg_tablespace_location(oid) FROM pg_tablespace;
```

### Configure Storage Tiers

```sql
-- Configure TimescaleDB for HDD-only storage
ALTER SYSTEM SET temp_tablespaces = 'pg_default';
ALTER SYSTEM SET default_tablespace = 'pg_default';

-- Reload configuration
SELECT pg_reload_conf();
```

## Database Schema Setup

### Run Migrations

```bash
# Access backend container
docker exec -it prs-onprem-backend bash

# Install dependencies (if needed)
npm install

# Run database migrations
npm run migrate

# Verify migration status
npm run migrate:status
```

### Setup Hypertables

```bash
# Setup TimescaleDB hypertables and compression
npm run setup:timescaledb

# Verify hypertables
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT * FROM timescaledb_information.hypertables;
"
```

## Performance Optimization

### Memory Configuration

```sql
-- Optimize memory settings for 16GB RAM system
ALTER SYSTEM SET shared_buffers = '2GB';
ALTER SYSTEM SET effective_cache_size = '4GB';
ALTER SYSTEM SET work_mem = '32MB';
ALTER SYSTEM SET maintenance_work_mem = '512MB';

-- WAL settings
ALTER SYSTEM SET wal_buffers = '32MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET max_wal_size = '2GB';
ALTER SYSTEM SET min_wal_size = '512MB';

-- Reload configuration
SELECT pg_reload_conf();
```

### Connection Settings

```sql
-- Connection and worker settings
ALTER SYSTEM SET max_connections = 150;
ALTER SYSTEM SET max_worker_processes = 32;
ALTER SYSTEM SET max_parallel_workers = 16;
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;

-- TimescaleDB specific settings
ALTER SYSTEM SET timescaledb.max_background_workers = 16;

-- Reload configuration
SELECT pg_reload_conf();
```

### Storage Optimization

```sql
-- SSD optimization
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;
ALTER SYSTEM SET seq_page_cost = 1.0;

-- Checkpoint optimization
ALTER SYSTEM SET checkpoint_timeout = '15min';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;

-- Reload configuration
SELECT pg_reload_conf();
```

## Data Lifecycle Policies

### Compression Policies

```sql
-- High-volume tables - compress after 7 days
SELECT add_compression_policy('notifications', INTERVAL '7 days');
SELECT add_compression_policy('audit_logs', INTERVAL '7 days');
SELECT add_compression_policy('histories', INTERVAL '7 days');
SELECT add_compression_policy('comments', INTERVAL '7 days');

-- History tables - compress after 14 days
SELECT add_compression_policy('requisition_canvass_histories', INTERVAL '14 days');
SELECT add_compression_policy('requisition_item_histories', INTERVAL '14 days');
SELECT add_compression_policy('requisition_order_histories', INTERVAL '14 days');

-- Business tables - compress after 30 days
SELECT add_compression_policy('requisitions', INTERVAL '30 days');
SELECT add_compression_policy('purchase_orders', INTERVAL '30 days');
SELECT add_compression_policy('delivery_receipts', INTERVAL '30 days');
```

### Data Movement Policies

```sql
-- Move chunks older than 30 days to HDD storage
SELECT add_move_chunk_policy('notifications', INTERVAL '30 days', 'pg_default');
SELECT add_move_chunk_policy('audit_logs', INTERVAL '30 days', 'pg_default');
SELECT add_move_chunk_policy('requisitions', INTERVAL '30 days', 'pg_default');
SELECT add_move_chunk_policy('purchase_orders', INTERVAL '30 days', 'pg_default');

-- Move history tables after 14 days (faster archival)
SELECT add_move_chunk_policy('requisition_canvass_histories', INTERVAL '14 days', 'pg_default');
SELECT add_move_chunk_policy('requisition_item_histories', INTERVAL '14 days', 'pg_default');
```

## Database Validation

### Verify Installation

```sql
-- Check TimescaleDB version
SELECT * FROM timescaledb_information.license;

-- Check hypertables
SELECT hypertable_name, num_chunks FROM timescaledb_information.hypertables;

-- Check compression policies
SELECT * FROM timescaledb_information.compression_settings;

-- Check data movement policies
SELECT * FROM timescaledb_information.data_node_move_policies;
```

### Performance Testing

```sql
-- Test query performance
EXPLAIN ANALYZE SELECT COUNT(*) FROM notifications 
WHERE created_at >= NOW() - INTERVAL '30 days';

-- Check chunk distribution
SELECT 
    hypertable_name,
    tablespace_name,
    COUNT(*) as chunk_count,
    pg_size_pretty(SUM(chunk_size)) as total_size
FROM timescaledb_information.chunks
GROUP BY hypertable_name, tablespace_name;
```

### Connection Testing

```bash
# Test database connectivity from backend
docker exec prs-onprem-backend npm run db:test

# Test connection pool
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT count(*) as connections, state 
FROM pg_stat_activity 
GROUP BY state;
"
```

## Backup Configuration

### WAL Archiving Setup

```sql
-- Enable WAL archiving for point-in-time recovery
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET archive_mode = 'on';
ALTER SYSTEM SET archive_command = 'cp %p /var/lib/postgresql/wal-archive/%f';
ALTER SYSTEM SET max_wal_senders = 3;
ALTER SYSTEM SET wal_keep_segments = 64;

-- Reload configuration
SELECT pg_reload_conf();
```

### Backup User Setup

```sql
-- Create backup user with minimal privileges
CREATE ROLE backup_user WITH LOGIN PASSWORD 'secure_backup_password';
GRANT CONNECT ON DATABASE prs_production TO backup_user;
GRANT USAGE ON SCHEMA public TO backup_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO backup_user;
```

## Security Configuration

### User Management

```sql
-- Create application-specific roles
CREATE ROLE prs_app_read;
CREATE ROLE prs_app_write;
CREATE ROLE prs_app_admin;

-- Grant appropriate permissions
GRANT SELECT ON ALL TABLES IN SCHEMA public TO prs_app_read;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO prs_app_write;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO prs_app_admin;

-- Create application user
CREATE USER prs_application WITH PASSWORD 'secure_app_password';
GRANT prs_app_write TO prs_application;
```

### Connection Security

```sql
-- Configure connection limits
ALTER ROLE prs_admin CONNECTION LIMIT 10;
ALTER ROLE prs_application CONNECTION LIMIT 50;
ALTER ROLE backup_user CONNECTION LIMIT 2;

-- Set password policies
ALTER ROLE prs_admin VALID UNTIL 'infinity';
ALTER ROLE prs_application VALID UNTIL 'infinity';
```

## Troubleshooting

### Common Issues

#### Database Won't Start

```bash
# Check container logs
docker logs prs-onprem-postgres-timescale

# Check storage permissions
ls -la /mnt/hdd/postgresql-hot
ls -la /mnt/hdd/postgresql-cold

# Fix permissions if needed
sudo chown -R 999:999 /mnt/hdd/postgresql-hot /mnt/hdd/postgresql-cold
```

#### Connection Issues

```bash
# Test connectivity
docker exec prs-onprem-postgres-timescale pg_isready -U prs_admin

# Check connection count
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT count(*) FROM pg_stat_activity;
"

# Kill idle connections if needed
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE state = 'idle' 
AND query_start < NOW() - INTERVAL '1 hour';
"
```

#### Performance Issues

```sql
-- Check slow queries
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
ORDER BY total_time DESC 
LIMIT 10;

-- Check table bloat
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
```

---

!!! success "Database Ready"
    Once all setup steps are completed, your TimescaleDB database is ready for production use with HDD-only storage architecture and zero-deletion compliance.

!!! tip "Next Steps"
    Proceed to [SSL Configuration](ssl.md) to secure your deployment with HTTPS.
