# TimescaleDB Optimization Implementation Guide for getAllRequisitionsV2

## Overview

This guide provides a comprehensive approach to optimizing the `getAllRequisitionsV2` method in the PRS system for TimescaleDB. The optimization focuses on leveraging TimescaleDB's time-series capabilities, reducing query complexity, and improving overall performance.

## Current Performance Issues

### Identified Problems
1. **Complex CTE with 7 UNION ALL operations** - High CPU usage
2. **Multiple separate queries** - Up to 6 queries per request (3 data + 3 count)
3. **Subquery-heavy approver aggregation** - Memory intensive
4. **No time-based filtering** - Poor chunk exclusion
5. **Inefficient sorting** - Complex window functions

### Performance Impact
- Query execution time: 2-5 seconds for large datasets
- Memory usage: High due to complex CTEs
- Database load: Multiple concurrent queries
- Scalability: Poor performance with growing data

## Optimization Strategy

### Phase 1: Index Optimization (Immediate - 1 day)

**Priority: HIGH**
**Expected Impact: 40-60% performance improvement**

```bash
# Run the index optimization script
psql -d prs_production -f timescaledb-optimization-indexes.sql
```

**Key Indexes Created:**
- Time-based composite indexes on all document tables
- Partial indexes for active documents only
- User-specific indexes for approval queries
- Search optimization indexes

### Phase 2: Materialized View Implementation (Medium - 2-3 days)

**Priority: MEDIUM**
**Expected Impact: 60-80% performance improvement**

```bash
# Create the unified documents materialized view
psql -d prs_production -f unified-docs-materialized-view.sql

# Set up automatic refresh (every 5 minutes)
echo "*/5 * * * * psql -d prs_production -c 'SELECT refresh_unified_docs_view();'" | crontab -
```

**Benefits:**
- Pre-computed unified document structure
- Eliminates complex CTE calculations
- Faster filtering and sorting
- Reduced memory usage

### Phase 3: Code Implementation (High - 3-5 days)

**Priority: HIGH**
**Expected Impact: 70-90% performance improvement**

1. **Backup Original Method**
```javascript
// In requisitionRepository.js
async getAllRequisitionsV2Original(payload) {
  // Move current implementation here as fallback
}
```

2. **Implement Optimized Method**
```javascript
// Replace current method with optimized version
// See optimized-getAllRequisitionsV2.js for complete implementation
```

3. **Add Configuration**
```javascript
// Add to config
const OPTIMIZATION_CONFIG = {
  useOptimizedQuery: process.env.USE_OPTIMIZED_QUERY !== 'false',
  timeRangeDefault: '6 months',
  fallbackOnError: true,
  enableCaching: true,
  cacheTimeout: 300 // 5 minutes
};
```

### Phase 4: Caching Layer (Optional - 1-2 days)

**Priority: LOW**
**Expected Impact: Additional 20-30% improvement for repeated queries**

```javascript
// Add Redis caching for frequent queries
const cacheKey = `dashboard:${userId}:${JSON.stringify(filters)}`;
const cachedResult = await redis.get(cacheKey);
if (cachedResult) {
  return JSON.parse(cachedResult);
}
// ... execute query ...
await redis.setex(cacheKey, 300, JSON.stringify(result));
```

## Implementation Steps

### Step 1: Database Optimization

```bash
# 1. Create indexes
psql -d prs_production -f timescaledb-optimization-indexes.sql

# 2. Create materialized view
psql -d prs_production -f unified-docs-materialized-view.sql

# 3. Verify setup
psql -d prs_production -c "
SELECT 
  tablename, 
  indexname, 
  indexdef 
FROM pg_indexes 
WHERE tablename IN ('requisitions', 'canvass_requisitions', 'purchase_orders')
ORDER BY tablename, indexname;
"
```

### Step 2: Code Integration

1. **Add optimized method to RequisitionRepository**
2. **Implement feature flag for gradual rollout**
3. **Add comprehensive error handling**
4. **Include performance monitoring**

### Step 3: Testing and Validation

```javascript
// Performance testing script
const testCases = [
  { requestType: 'my_request', limit: 10, page: 1 },
  { requestType: 'my_approval', limit: 20, page: 1 },
  { requestType: 'all', limit: 50, page: 1 },
];

for (const testCase of testCases) {
  const startTime = Date.now();
  const result = await requisitionRepository.getAllRequisitionsV2(testCase);
  const endTime = Date.now();
  console.log(`Test case: ${JSON.stringify(testCase)}`);
  console.log(`Execution time: ${endTime - startTime}ms`);
  console.log(`Results count: ${result.all.length}`);
}
```

### Step 4: Monitoring and Maintenance

```sql
-- Performance monitoring queries
-- 1. Check query performance
SELECT 
  query,
  calls,
  total_time,
  mean_time,
  rows
FROM pg_stat_statements 
WHERE query LIKE '%unified_docs%' 
ORDER BY total_time DESC;

-- 2. Check index usage
SELECT 
  schemaname,
  tablename,
  indexname,
  idx_scan,
  idx_tup_read
FROM pg_stat_user_indexes 
WHERE tablename LIKE '%requisition%'
ORDER BY idx_scan DESC;

-- 3. Check materialized view freshness
SELECT 
  matviewname,
  ispopulated,
  pg_size_pretty(pg_total_relation_size(matviewname)) as size
FROM pg_matviews 
WHERE matviewname = 'unified_docs_view';
```

## Expected Performance Improvements

### Before Optimization
- Query time: 2-5 seconds
- Memory usage: 200-500MB per query
- Concurrent users: 10-20 without performance degradation
- Database CPU: 60-80% during peak usage

### After Optimization
- Query time: 200-500ms (80-90% improvement)
- Memory usage: 50-100MB per query (70-80% reduction)
- Concurrent users: 50-100 without performance degradation
- Database CPU: 20-40% during peak usage

## Rollback Plan

If issues occur during implementation:

1. **Immediate Rollback**
```javascript
// Set environment variable
process.env.USE_OPTIMIZED_QUERY = 'false';
// Application will use original method
```

2. **Database Rollback**
```sql
-- Drop materialized view if needed
DROP MATERIALIZED VIEW IF EXISTS unified_docs_view;

-- Drop indexes if they cause issues
DROP INDEX IF EXISTS idx_requisitions_updated_at_status_user;
-- ... other indexes
```

3. **Code Rollback**
```bash
# Revert to previous commit
git revert <commit-hash>
```

## Maintenance Schedule

### Daily
- Monitor query performance metrics
- Check materialized view refresh status

### Weekly
- Review index usage statistics
- Analyze slow query logs
- Update compression policies if needed

### Monthly
- Optimize chunk intervals based on data growth
- Review and update indexes based on usage patterns
- Performance testing with production-like data

## Success Metrics

### Performance Metrics
- Query execution time < 500ms for 95% of requests
- Memory usage reduction > 70%
- Database CPU usage < 40% during peak

### Business Metrics
- User satisfaction scores improvement
- Reduced support tickets related to slow dashboard
- Increased concurrent user capacity

### Technical Metrics
- Index hit ratio > 95%
- Chunk exclusion effectiveness > 80%
- Materialized view refresh time < 30 seconds
