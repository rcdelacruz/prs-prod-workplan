# TimescaleDB Quick Reference

## Quick Start Commands

### Initial Setup (Run Once)
```bash
# Complete TimescaleDB optimization setup
./deploy-onprem.sh optimize-timescaledb
```

### Production Automation
```bash
# Set up weekly maintenance cron job
echo "0 2 * * 0 /opt/prs/prs-deployment/scripts/deploy-onprem.sh weekly-maintenance" | crontab -
```

### Daily Operations
```bash
# Check status
./deploy-onprem.sh timescaledb-status

# Manual maintenance (if needed)
./deploy-onprem.sh weekly-maintenance

# Move chunks manually (rarely needed)
./deploy-onprem.sh move-chunks
```

## Status Interpretation

### Healthy System Output
```
=== CHUNK DISTRIBUTION ===
 storage | compression_status | chunk_count | avg_age_days
---------+--------------------+-------------+--------------
 HDD (default) | Uncompressed       |          5  |         -2.0
 HDD (default) | Compressed         |         35  |        30.0

=== CHUNK STATUS ===
All chunks use HDD storage (simplified configuration)
```

### Issues to Address
```
=== CHUNK STATUS ===
All chunks use HDD storage (no movement needed)
```

## Common Commands

### Storage Management (HDD-Only)
```bash
# Setup TimescaleDB (HDD-only configuration)
./deploy-onprem.sh timescaledb-setup

# Check storage usage
df -h /mnt/hdd
```

### Monitoring Queries
```sql
-- Chunk distribution (HDD-only)
SELECT
    'HDD (default)' as storage,
    CASE WHEN c.is_compressed THEN 'Compressed' ELSE 'Uncompressed' END as status,
    COUNT(*) as chunks
FROM timescaledb_information.chunks c
GROUP BY c.is_compressed;

-- Active policies
SELECT job_id, application_name, schedule_interval, scheduled
FROM timescaledb_information.jobs
WHERE application_name LIKE '%Compression%' OR application_name LIKE '%Retention%';

-- Compression effectiveness
SELECT
    hypertable_name,
    COUNT(*) as total_chunks,
    COUNT(CASE WHEN is_compressed THEN 1 END) as compressed_chunks,
    ROUND(COUNT(CASE WHEN is_compressed THEN 1 END)::numeric / COUNT(*) * 100, 1) as compression_pct
FROM timescaledb_information.chunks
GROUP BY hypertable_name
ORDER BY hypertable_name;
```

## Troubleshooting

### Problem: Storage Issues
```bash
# Check HDD usage
./deploy-onprem.sh timescaledb-status

# Fix automatically
./deploy-onprem.sh weekly-maintenance
```

### Problem: Low Compression Ratio
```sql
-- Find uncompressed old chunks
SELECT
    hypertable_name,
    chunk_name,
    range_end,
    is_compressed
FROM timescaledb_information.chunks
WHERE NOT is_compressed
AND range_end < NOW() - INTERVAL '7 days'
ORDER BY range_end;
```

### Problem: Storage Full
```bash
# Check disk usage
df -h /mnt/hdd /mnt/hdd

# Check largest tables
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = '_timescaledb_internal'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
"
```

## Maintenance Checklist

### Weekly (Automated)
- Chunk movement optimization
- Compression of eligible chunks
- Background job health check
- Storage utilization review

### Monthly (Manual Review)
- Review maintenance logs
- Check storage growth trends
- Verify retention policy effectiveness
- Plan capacity if needed

### Quarterly (Performance Review)
- Analyze query performance
- Review compression ratios
- Optimize chunk intervals if needed
- Update retention policies if required

## Log Locations

```bash
# Maintenance logs
tail -f /var/log/timescaledb-maintenance.log

# Status logs
tail -f /var/log/timescaledb-status.log

# PostgreSQL logs
docker logs prs-onprem-postgres-timescale
```

## Emergency Procedures

### Database Performance Issues
1. Check current status: `./deploy-onprem.sh timescaledb-status`
2. Review recent maintenance: `tail -100 /var/log/timescaledb-maintenance.log`
3. Check disk space: `df -h /mnt/hdd /mnt/hdd`
4. Run manual maintenance: `./deploy-onprem.sh weekly-maintenance`

### Storage Emergency
1. Check immediate space: `df -h`
2. Identify largest chunks: Use storage troubleshooting query above
3. Force compression: Run auto-optimizer manually
4. Emergency cleanup: Review retention policies

### Automation Failure
1. Check cron job: `crontab -l`
2. Test manual run: `./deploy-onprem.sh weekly-maintenance`
3. Check permissions: Ensure script is executable
4. Review logs: Check for error messages

## Performance Targets

### Healthy Metrics
- **Compression Ratio**: >70% for tables older than 7 days
- **HDD Usage**: <80% of available space
- **Chunk Movement**: <5 chunks needing movement weekly
- **Background Jobs**: All compression/retention jobs active

### Warning Thresholds
- **Compression Ratio**: <50% for old data
- **HDD Usage**: >90% of available space
- **Chunk Movement**: >20 chunks needing movement
- **Background Jobs**: Any critical job inactive

## Additional Resources

- [TimescaleDB Automation Guide](./timescaledb-automation.md)
- [Capacity Planning](./capacity.md)
- [Routine Maintenance](./routine.md)
- [Security Maintenance](./security.md)

---

*Keep this reference handy for daily TimescaleDB operations.*
