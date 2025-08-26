# TimescaleDB Automation & Maintenance

## Overview

This document provides comprehensive guidance for automating TimescaleDB maintenance in production environments. The PRS deployment includes intelligent automation for multi-tier storage management, compression, and data lifecycle policies.

## Automation Strategy

### What TimescaleDB Does Automatically
- **Chunk Creation** - Automatic based on time intervals
- **Compression** - Automatic (once policies are set)
- **Retention** - Automatic (once policies are set)
- **Background Jobs** - Compression, retention, statistics

### What Our Enhancement Adds
- **Multi-tier Storage** - SSD for hot data, HDD for cold data
- **Compression-aware Placement** - Optimal storage based on compression status
- **Automated Maintenance** - Weekly optimization without manual intervention

## Production Setup

### 1. One-Time Initial Setup

Run the complete optimization setup once after deployment:

```bash
# Complete initial TimescaleDB optimization
./deploy-onprem.sh optimize-timescaledb
```

This command:
- Sets up SSD and HDD tablespaces
- Configures compression policies (7-14 days)
- Sets up retention policies (2-7 years)
- Optimizes PostgreSQL settings
- Creates monitoring views
- Moves existing chunks to optimal locations

### 2. Weekly Automation (Cron Job)

Set up automated weekly maintenance:

```bash
# Edit crontab
crontab -e

# Add weekly maintenance (Sundays at 2 AM)
0 2 * * 0 /opt/prs/prs-deployment/scripts/deploy-onprem.sh weekly-maintenance >> /var/log/timescaledb-maintenance.log 2>&1

# Optional: Daily status check (8 AM)
0 8 * * * /opt/prs/prs-deployment/scripts/deploy-onprem.sh timescaledb-status >> /var/log/timescaledb-status.log 2>&1
```

### 3. Monitoring Commands

```bash
# Check current status
./deploy-onprem.sh timescaledb-status

# Manual maintenance (if needed)
./deploy-onprem.sh weekly-maintenance

# Move chunks manually (rarely needed)
./deploy-onprem.sh move-chunks
```

## Storage Tier Strategy

### Multi-Tier Data Placement

```
STORAGE TIERS:
├── SSD Hot Storage (/mnt/hdd/postgresql-hot)
│   ├── Recent uncompressed data (< 7 days)
│   ├── Recent compressed data (< 30 days)
│   └── New tables and indexes
│
├── HDD Cold Storage (/mnt/hdd/postgresql-cold)
│   └── Old data (> 30 days, any compression state)
│
└── Container Volume (/var/lib/postgresql/data)
    ├── System catalogs (pg_global)
    ├── Default tablespace (pg_default) - fallback
    └── PostgreSQL configuration files
```

### Intelligent Placement Logic

```sql
-- Hot Data Strategy: Recent uncompressed data on SSD for fast writes
WHEN chunk_age < 7 days AND NOT compressed THEN 'pg_default'

-- Warm Data Strategy: Recent compressed data on SSD for fast queries
WHEN chunk_age < 30 days AND compressed THEN 'pg_default'

-- Cold Data Strategy: Old data goes to HDD for cost-effective storage
ELSE 'pg_default'
```

## Data Lifecycle

### Automatic Data Flow

1. **New Data (0-7 days)**
   - Location: SSD Hot Tablespace
   - State: Uncompressed
   - Purpose: Fast writes, recent queries

2. **Compression Trigger (7 days)**
   - Action: Auto-compress chunks
   - Location: Stay on SSD (warm data)
   - Purpose: Space efficiency + fast queries

3. **Aging Data (30+ days)**
   - Action: Move to HDD Cold Tablespace
   - State: Compressed
   - Purpose: Cost-effective archival

4. **Retention Policies (2-7 years)**
   - Action: Auto-delete old data
   - Tables: Based on compliance requirements
   - Purpose: Data lifecycle management

## Monitoring & Verification

### Status Checks

```bash
# Comprehensive status report
./deploy-onprem.sh timescaledb-status
```

### Key Metrics to Monitor

1. **Chunk Distribution**
   - Chunks in correct tablespaces
   - Compression ratios
   - Age distribution

2. **Active Policies**
   - Compression policies status
   - Retention policies status
   - Background job health

3. **Storage Utilization**
   - SSD vs HDD usage
   - Compression effectiveness
   - Growth trends

### SQL Monitoring Queries

```sql
-- Chunk distribution by tablespace and compression
SELECT
    COALESCE(t.tablespace, 'pg_default') as tablespace,
    CASE WHEN c.is_compressed THEN 'Compressed' ELSE 'Uncompressed' END as compression_status,
    COUNT(*) as chunk_count,
    ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - c.range_end))/86400), 1) as avg_age_days
FROM timescaledb_information.chunks c
LEFT JOIN pg_tables t ON t.schemaname = c.chunk_schema AND t.tablename = c.chunk_name
GROUP BY COALESCE(t.tablespace, 'pg_default'), c.is_compressed
ORDER BY tablespace, compression_status;

-- Active policies
SELECT
    job_id,
    application_name,
    schedule_interval,
    CASE WHEN scheduled THEN 'Active' ELSE 'Inactive' END as status
FROM timescaledb_information.jobs
WHERE application_name LIKE '%Compression%' OR application_name LIKE '%Retention%'
ORDER BY application_name;
```

## Troubleshooting

### Common Issues

1. **Chunks in Wrong Tablespaces**
   ```bash
   # Check status
   ./deploy-onprem.sh timescaledb-status

   # Fix automatically
   ./deploy-onprem.sh weekly-maintenance
   ```

2. **Compression Not Working**
   ```sql
   -- Check compression policies
   SELECT * FROM timescaledb_information.jobs
   WHERE application_name LIKE '%Compression%';

   -- Check uncompressed chunks
   SELECT COUNT(*) FROM timescaledb_information.chunks
   WHERE NOT is_compressed AND range_end < NOW() - INTERVAL '7 days';
   ```

3. **Storage Issues**
   ```bash
   # Check disk usage
   df -h /mnt/hdd /mnt/hdd

   # Check tablespace sizes
   SELECT
       spcname,
       pg_size_pretty(pg_tablespace_size(spcname)) as size
   FROM pg_tablespace
   WHERE spcname IN ('pg_default', 'pg_default');
   ```

### Manual Intervention Scenarios

Only manual intervention is needed when:
- Status shows chunks needing attention
- Major configuration changes required
- Performance troubleshooting needed
- Storage capacity issues

## Performance Benefits

### Write Performance
- New data → SSD (fast writes)
- Uncompressed chunks → SSD (no compression overhead)

### Query Performance
- Recent queries → SSD (hot + warm data)
- Compressed data → Better cache utilization
- Old data → HDD (acceptable for archival queries)

### Storage Efficiency
- Compression → Reduces storage requirements
- Tiered storage → Cost optimization
- Retention policies → Automatic cleanup

## Configuration Files

### Compression Policies
High-volume tables: 7-day compression
- `audit_logs`
- `notifications`
- `notes`
- `comments`
- `force_close_logs`
- `transaction_logs`

History tables: 14-day compression
- `requisition_canvass_histories`
- `requisition_item_histories`
- `requisition_order_histories`
- `requisition_delivery_histories`
- `requisition_payment_histories`
- `requisition_return_histories`
- `non_requisition_histories`
- `invoice_report_histories`
- `delivery_receipt_items_history`

### Retention Policies
- High-volume tables: 2 years
- History tables: 7 years (compliance)

## Best Practices

1. **Monitor Weekly**
   - Review maintenance logs
   - Check storage utilization
   - Verify policy effectiveness

2. **Plan Capacity**
   - Monitor growth trends
   - Plan HDD-only capacity
   - Consider compression ratios

3. **Test Changes**
   - Test configuration changes in staging
   - Monitor performance impact
   - Have rollback procedures

4. **Document Changes**
   - Log configuration modifications
   - Track performance improvements
   - Maintain operational runbooks

## Support

For issues with TimescaleDB automation:
1. Check logs: `/var/log/timescaledb-*.log`
2. Run status check: `./deploy-onprem.sh timescaledb-status`
3. Review this documentation
4. Contact system administrator

---

*This automation ensures your TimescaleDB deployment requires minimal manual intervention while maintaining optimal performance and cost efficiency.*
