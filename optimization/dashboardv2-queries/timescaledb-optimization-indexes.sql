-- TimescaleDB Optimization Indexes for getAllRequisitionsV2
-- This script creates optimized indexes for the PRS dashboard queries
-- Run this after TimescaleDB hypertables are set up

-- ============================================================================
-- PHASE 1: TIME-BASED COMPOSITE INDEXES (High Priority)
-- ============================================================================

-- Requisitions table optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_requisitions_updated_at_status_user 
ON requisitions (updated_at DESC, status, created_by, assigned_to)
WHERE updated_at >= NOW() - INTERVAL '1 year';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_requisitions_company_time 
ON requisitions (company_id, updated_at DESC, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_requisitions_project_time 
ON requisitions (project_id, updated_at DESC, status);

-- Canvass requisitions optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_canvass_requisitions_updated_at_status 
ON canvass_requisitions (updated_at DESC, status, requisition_id)
WHERE updated_at >= NOW() - INTERVAL '1 year';

-- Purchase orders optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_purchase_orders_updated_at_status 
ON purchase_orders (updated_at DESC, status, requisition_id)
WHERE updated_at >= NOW() - INTERVAL '1 year';

-- Delivery receipts optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_delivery_receipts_updated_at_status 
ON delivery_receipts (updated_at DESC, status, requisition_id)
WHERE updated_at >= NOW() - INTERVAL '1 year';

-- Invoice reports optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_invoice_reports_updated_at_status 
ON invoice_reports (updated_at DESC, status, requisition_id)
WHERE updated_at >= NOW() - INTERVAL '1 year';

-- Payment requests optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rs_payment_requests_updated_at_status 
ON rs_payment_requests (updated_at DESC, status, requisition_id)
WHERE updated_at >= NOW() - INTERVAL '1 year';

-- Non-requisitions optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_non_requisitions_updated_at_status 
ON non_requisitions (updated_at DESC, status, created_by)
WHERE updated_at >= NOW() - INTERVAL '1 year';

-- ============================================================================
-- PHASE 2: PARTIAL INDEXES FOR ACTIVE DOCUMENTS (High Priority)
-- ============================================================================

-- Active requisitions (exclude closed/cancelled)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_requisitions_active_updated_at 
ON requisitions (updated_at DESC, created_by, assigned_to, company_id) 
WHERE status NOT IN ('cancelled', 'closed', 'rs_draft');

-- Active canvass requisitions
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_canvass_active_updated_at 
ON canvass_requisitions (updated_at DESC, requisition_id) 
WHERE status NOT IN ('cancelled', 'closed');

-- Active purchase orders
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_purchase_orders_active_updated_at 
ON purchase_orders (updated_at DESC, requisition_id) 
WHERE status NOT IN ('cancelled', 'closed');

-- ============================================================================
-- PHASE 3: USER-SPECIFIC INDEXES FOR APPROVAL QUERIES (Medium Priority)
-- ============================================================================

-- Requisition approvers optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_requisition_approvers_user_time 
ON requisition_approvers (approver_id, alt_approver_id) 
INCLUDE (requisition_id);

-- Canvass approvers optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_canvass_approvers_user_time 
ON canvass_approvers (user_id, alt_approver_id) 
INCLUDE (canvass_requisition_id);

-- Purchase order approvers optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_purchase_order_approvers_user_time 
ON purchase_order_approvers (user_id, alt_approver_id) 
INCLUDE (purchase_order_id);

-- Payment request approvers optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rs_payment_request_approvers_user_time 
ON rs_payment_request_approvers (user_id, alt_approver_id) 
INCLUDE (payment_request_id);

-- Non-requisition approvers optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_non_requisition_approvers_user_time 
ON non_requisition_approvers (user_id, alt_approver_id) 
INCLUDE (non_requisition_id);

-- ============================================================================
-- PHASE 4: REFERENCE DATA INDEXES (Medium Priority)
-- ============================================================================

-- Users table optimization for name searches
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_fullname_search 
ON users (first_name, last_name);

-- Companies table optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_companies_name_search 
ON companies (name);

-- Projects table optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_projects_name_search 
ON projects (name);

-- Departments table optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_departments_name_search 
ON departments (name);

-- ============================================================================
-- PHASE 5: COMPOSITE SEARCH INDEXES (Low Priority)
-- ============================================================================

-- Global search optimization for requisitions
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_requisitions_global_search 
ON requisitions (company_code, rs_letter, rs_number, draft_rs_number, status);

-- Global search optimization for canvass
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_canvass_global_search 
ON canvass_requisitions (cs_letter, cs_number, draft_cs_number, status);

-- ============================================================================
-- PHASE 6: TIMESCALEDB SPECIFIC OPTIMIZATIONS
-- ============================================================================

-- Set optimal chunk intervals for better performance
SELECT set_chunk_time_interval('requisitions', INTERVAL '1 month');
SELECT set_chunk_time_interval('canvass_requisitions', INTERVAL '1 month');
SELECT set_chunk_time_interval('purchase_orders', INTERVAL '1 month');
SELECT set_chunk_time_interval('delivery_receipts', INTERVAL '1 month');
SELECT set_chunk_time_interval('invoice_reports', INTERVAL '1 month');
SELECT set_chunk_time_interval('rs_payment_requests', INTERVAL '1 month');
SELECT set_chunk_time_interval('non_requisitions', INTERVAL '1 month');

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Check index usage
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes 
WHERE tablename IN (
    'requisitions', 'canvass_requisitions', 'purchase_orders', 
    'delivery_receipts', 'invoice_reports', 'rs_payment_requests', 
    'non_requisitions'
)
ORDER BY idx_scan DESC;

-- Check hypertable chunk exclusion
SELECT 
    hypertable_name,
    chunk_name,
    range_start,
    range_end
FROM timescaledb_information.chunks 
WHERE hypertable_name IN (
    'requisitions', 'canvass_requisitions', 'purchase_orders', 
    'delivery_receipts', 'invoice_reports', 'rs_payment_requests', 
    'non_requisitions'
)
ORDER BY hypertable_name, range_start DESC
LIMIT 20;

-- Performance monitoring query
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    rows
FROM pg_stat_statements 
WHERE query LIKE '%unified_docs%' 
ORDER BY total_time DESC 
LIMIT 10;
