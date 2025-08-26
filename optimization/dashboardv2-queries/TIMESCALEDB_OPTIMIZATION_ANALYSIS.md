# TimescaleDB Optimization Analysis for getAllRequisitionsV2

## Current Implementation Analysis

The `getAllRequisitionsV2` method in `requisitionRepository.js` has several performance bottlenecks that can be optimized for TimescaleDB:

### Performance Issues Identified

1. **Complex CTE with 7 UNION ALL operations** across different document types
2. **Multiple subqueries** for approver aggregation using JSON_AGG
3. **Multiple query executions** (up to 6 separate queries per request)
4. **No time-based filtering** despite TimescaleDB's time-series capabilities
5. **Inefficient sorting** with complex window functions
6. **No materialized views** for common aggregations

### TimescaleDB Optimization Opportunities

#### 1. Time-Based Query Optimization
- Leverage TimescaleDB's time partitioning for `updated_at` filtering
- Use time-bucket functions for date range queries
- Implement time-based indexes for faster filtering

#### 2. Materialized Views (Continuous Aggregates)
- Create continuous aggregates for dashboard summaries
- Pre-compute common document type counts
- Cache user-specific approval counts

#### 3. Index Optimization
- Create composite indexes on (doc_type, updated_at, user_id)
- Implement partial indexes for active documents
- Use TimescaleDB's space-partitioning for user-based queries

#### 4. Query Structure Improvements
- Replace multiple queries with single optimized query
- Use CTEs more efficiently with TimescaleDB features
- Implement proper chunk exclusion

## Recommended Optimizations

### Phase 1: Index Optimization (Immediate Impact)

```sql
-- Time-based composite indexes for each table
CREATE INDEX CONCURRENTLY idx_requisitions_updated_at_status_user 
ON requisitions (updated_at DESC, status, created_by, assigned_to);

CREATE INDEX CONCURRENTLY idx_canvass_requisitions_updated_at_status 
ON canvass_requisitions (updated_at DESC, status, requisition_id);

CREATE INDEX CONCURRENTLY idx_purchase_orders_updated_at_status 
ON purchase_orders (updated_at DESC, status, requisition_id);

-- Partial indexes for active documents
CREATE INDEX CONCURRENTLY idx_requisitions_active_updated_at 
ON requisitions (updated_at DESC, created_by, assigned_to) 
WHERE status NOT IN ('cancelled', 'closed');

-- User-specific indexes for approval queries
CREATE INDEX CONCURRENTLY idx_requisition_approvers_user_time 
ON requisition_approvers (approver_id, alt_approver_id) 
INCLUDE (requisition_id);
```

### Phase 2: Materialized Views (Medium Impact)

```sql
-- Dashboard summary continuous aggregate
CREATE MATERIALIZED VIEW dashboard_summary_hourly
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', updated_at) AS hour,
    doc_type,
    status,
    COUNT(*) as doc_count,
    COUNT(DISTINCT requestor_id) as unique_requestors
FROM unified_docs_view
GROUP BY hour, doc_type, status;

-- User-specific approval summary
CREATE MATERIALIZED VIEW user_approval_summary_daily
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', updated_at) AS day,
    assigned_to_user_id,
    doc_type,
    COUNT(*) as pending_count
FROM unified_docs_view
WHERE status IN ('pending', 'assigning', 'assigned')
GROUP BY day, assigned_to_user_id, doc_type;
```

### Phase 3: Query Restructuring (High Impact)

The main optimization involves:
1. Creating a unified view instead of CTE
2. Using time-based filtering
3. Implementing single-query approach
4. Leveraging TimescaleDB's chunk exclusion

### Phase 4: Caching Strategy

1. **Redis Integration**: Cache frequent queries for 5-15 minutes
2. **Application-level caching**: Cache user permissions and role-based filters
3. **Database-level caching**: Use TimescaleDB's built-in caching

## Implementation Priority

### High Priority (Immediate)
- [ ] Add time-based composite indexes
- [ ] Implement partial indexes for active documents
- [ ] Add query hints for chunk exclusion

### Medium Priority (1-2 weeks)
- [ ] Create unified document view
- [ ] Implement continuous aggregates
- [ ] Add Redis caching layer

### Low Priority (Long-term)
- [ ] Implement space partitioning by company_id
- [ ] Add automated compression policies
- [ ] Create custom aggregation functions

## Expected Performance Improvements

- **Query time reduction**: 60-80% for typical dashboard queries
- **Memory usage**: 40-50% reduction through better indexing
- **Scalability**: Support for 10x more concurrent users
- **Storage efficiency**: 70% compression for historical data

## Monitoring and Metrics

Key metrics to track:
- Query execution time by request type
- Index usage statistics
- Chunk exclusion effectiveness
- Cache hit rates
- Memory usage patterns
