-- Unified Documents Materialized View for TimescaleDB Optimization
-- This creates a materialized view that pre-computes the unified document structure
-- reducing the need for complex CTEs in the getAllRequisitionsV2 method

-- ============================================================================
-- DROP EXISTING VIEW IF EXISTS
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS unified_docs_view CASCADE;

-- ============================================================================
-- CREATE UNIFIED DOCUMENTS MATERIALIZED VIEW
-- ============================================================================
CREATE MATERIALIZED VIEW unified_docs_view AS
SELECT
  -- Common fields
  id,
  doc_type,
  ref_number,
  requestor_id,
  company_id,
  project_id,
  department_id,
  updated_at,
  status,
  grouping_id,
  root_status,
  assigned_to_user_id,
  approvers,
  
  -- Additional computed fields for optimization
  EXTRACT(YEAR FROM updated_at) AS year,
  EXTRACT(MONTH FROM updated_at) AS month,
  EXTRACT(WEEK FROM updated_at) AS week,
  DATE_TRUNC('day', updated_at) AS day,
  
  -- Status categories for faster filtering
  CASE 
    WHEN status IN ('cancelled', 'closed') THEN 'inactive'
    WHEN status IN ('rs_draft', 'draft') THEN 'draft'
    ELSE 'active'
  END AS status_category,
  
  -- Document type priority for sorting
  CASE doc_type 
    WHEN 'requisition' THEN 1 
    WHEN 'canvass' THEN 2 
    WHEN 'purchase_order' THEN 3 
    WHEN 'invoice' THEN 4 
    WHEN 'delivery_receipt' THEN 5 
    WHEN 'payment_request' THEN 6 
    WHEN 'non_requisition' THEN 7 
    ELSE 99 
  END AS doc_type_priority

FROM (
  -- Requisitions
  SELECT
    r.id, 
    'requisition' AS doc_type,
    CASE
      WHEN r.status = 'rs_draft' THEN CONCAT('RS-TMP-', r.company_code, r.rs_letter, COALESCE(r.draft_rs_number, ''))
      ELSE CONCAT('RS-', r.company_code, r.rs_letter, COALESCE(r.rs_number, ''))
    END AS ref_number,
    r.created_by AS requestor_id, 
    r.company_id, 
    r.project_id, 
    r.department_id,
    r.updated_at, 
    r.status,
    CAST(r.id AS TEXT) AS grouping_id,
    r.status AS root_status,
    r.assigned_to AS assigned_to_user_id,
    COALESCE(
      (SELECT JSON_AGG(DISTINCT user_id) 
       FROM (
         SELECT approver_id AS user_id FROM requisition_approvers WHERE requisition_id = r.id
         UNION ALL
         SELECT alt_approver_id AS user_id FROM requisition_approvers 
         WHERE requisition_id = r.id AND alt_approver_id IS NOT NULL
       ) approver_list),
      '[]'::json
    ) AS approvers
  FROM requisitions r
  
  UNION ALL
  
  -- Canvass requisitions
  SELECT
    cr.id, 
    'canvass' AS doc_type,
    CASE
      WHEN cr.cs_number IS NULL THEN CONCAT('CS-TMP-', r.company_code, cr.cs_letter, COALESCE(cr.draft_cs_number, ''))
      ELSE CONCAT('CS-', r.company_code, cr.cs_letter, COALESCE(cr.cs_number, ''))
    END AS ref_number,
    r.created_by AS requestor_id, 
    r.company_id, 
    r.project_id, 
    r.department_id,
    cr.updated_at, 
    cr.status,
    CAST(r.id AS TEXT) AS grouping_id,
    r.status AS root_status,
    r.assigned_to AS assigned_to_user_id,
    COALESCE(
      (SELECT JSON_AGG(DISTINCT user_id) 
       FROM (
         SELECT user_id FROM canvass_approvers WHERE canvass_requisition_id = cr.id
         UNION ALL
         SELECT alt_approver_id AS user_id FROM canvass_approvers 
         WHERE canvass_requisition_id = cr.id AND alt_approver_id IS NOT NULL
       ) approver_list),
      '[]'::json
    ) AS approvers
  FROM canvass_requisitions cr 
  INNER JOIN requisitions r ON cr.requisition_id = r.id
  
  UNION ALL
  
  -- Purchase orders
  SELECT
    po.id, 
    'purchase_order' AS doc_type,
    CONCAT('PO-', r.company_code, po.po_letter, po.po_number) AS ref_number,
    r.created_by AS requestor_id, 
    r.company_id, 
    r.project_id, 
    r.department_id,
    po.updated_at, 
    po.status,
    CAST(r.id AS TEXT) AS grouping_id,
    r.status AS root_status,
    r.assigned_to AS assigned_to_user_id,
    COALESCE(
      (SELECT JSON_AGG(DISTINCT user_id) 
       FROM (
         SELECT user_id FROM purchase_order_approvers WHERE purchase_order_id = po.id
         UNION ALL
         SELECT alt_approver_id AS user_id FROM purchase_order_approvers 
         WHERE purchase_order_id = po.id AND alt_approver_id IS NOT NULL
       ) approver_list),
      '[]'::json
    ) AS approvers
  FROM purchase_orders po 
  INNER JOIN requisitions r ON po.requisition_id = r.id
  
  UNION ALL
  
  -- Delivery receipts
  SELECT
    dr.id, 
    'delivery_receipt' AS doc_type,
    CASE
      WHEN dr.is_draft THEN CONCAT('RR-TMP-', COALESCE(dr.draft_dr_number, ''))
      ELSE CONCAT('RR-', COALESCE(dr.dr_number, ''))
    END AS ref_number,
    r.created_by AS requestor_id, 
    r.company_id, 
    r.project_id, 
    r.department_id,
    dr.updated_at, 
    COALESCE(dr.status, '') AS status,
    CAST(r.id AS TEXT) AS grouping_id,
    r.status AS root_status,
    r.assigned_to AS assigned_to_user_id,
    NULL AS approvers
  FROM delivery_receipts dr 
  INNER JOIN requisitions r ON dr.requisition_id = r.id
  
  UNION ALL
  
  -- Invoice reports
  SELECT
    ir.id, 
    'invoice' AS doc_type,
    CASE
      WHEN ir.is_draft THEN CONCAT('IR-TMP-', COALESCE(ir.ir_draft_number, ''))
      ELSE CONCAT('IR-', COALESCE(ir.ir_number, ''))
    END AS ref_number,
    r.created_by AS requestor_id, 
    r.company_id, 
    r.project_id, 
    r.department_id,
    ir.updated_at, 
    ir.status,
    CAST(r.id AS TEXT) AS grouping_id,
    r.status AS root_status,
    r.assigned_to AS assigned_to_user_id,
    NULL AS approvers
  FROM invoice_reports ir 
  INNER JOIN requisitions r ON ir.requisition_id = r.id
  
  UNION ALL
  
  -- Payment requests
  SELECT
    pr.id, 
    'payment_request' AS doc_type,
    CASE
      WHEN pr.is_draft THEN CONCAT('VR-TMP-', r.company_code, COALESCE(pr.draft_pr_number, ''))
      ELSE CONCAT('VR-', r.company_code, pr.pr_letter, COALESCE(pr.pr_number, ''))
    END AS ref_number,
    r.created_by AS requestor_id, 
    r.company_id, 
    r.project_id, 
    r.department_id,
    pr.updated_at, 
    pr.status,
    CAST(pr.requisition_id AS TEXT) AS grouping_id,
    r.status AS root_status,
    r.assigned_to AS assigned_to_user_id,
    COALESCE(
      (SELECT JSON_AGG(DISTINCT user_id) 
       FROM (
         SELECT user_id FROM rs_payment_request_approvers WHERE payment_request_id = pr.id
         UNION ALL
         SELECT alt_approver_id AS user_id FROM rs_payment_request_approvers 
         WHERE payment_request_id = pr.id AND alt_approver_id IS NOT NULL
       ) approver_list),
      '[]'::json
    ) AS approvers
  FROM rs_payment_requests pr 
  INNER JOIN requisitions r ON pr.requisition_id = r.id
  
  UNION ALL
  
  -- Non-requisitions
  SELECT
    nr.id, 
    'non_requisition' AS doc_type,
    CASE
      WHEN nr.status = 'draft' THEN CONCAT('NR-TMP-', nr.non_rs_letter, COALESCE(nr.draft_non_rs_number, ''))
      ELSE CONCAT('NR-', nr.non_rs_letter, COALESCE(nr.non_rs_number, ''))
    END AS ref_number,
    nr.created_by AS requestor_id, 
    nr.company_id, 
    nr.project_id, 
    nr.department_id,
    nr.updated_at, 
    nr.status,
    CONCAT('non_rs_', CAST(nr.id AS TEXT)) AS grouping_id,
    nr.status AS root_status,
    NULL AS assigned_to_user_id,
    COALESCE(
      (SELECT JSON_AGG(DISTINCT user_id) 
       FROM (
         SELECT user_id FROM non_requisition_approvers WHERE non_requisition_id = nr.id
         UNION ALL
         SELECT alt_approver_id AS user_id FROM non_requisition_approvers 
         WHERE non_requisition_id = nr.id AND alt_approver_id IS NOT NULL
       ) approver_list),
      '[]'::json
    ) AS approvers
  FROM non_requisitions nr
) all_docs;

-- ============================================================================
-- CREATE INDEXES ON MATERIALIZED VIEW
-- ============================================================================

-- Primary index on updated_at for time-based queries
CREATE INDEX idx_unified_docs_view_updated_at ON unified_docs_view (updated_at DESC);

-- Composite indexes for common query patterns
CREATE INDEX idx_unified_docs_view_requestor_time ON unified_docs_view (requestor_id, updated_at DESC);
CREATE INDEX idx_unified_docs_view_company_time ON unified_docs_view (company_id, updated_at DESC);
CREATE INDEX idx_unified_docs_view_doc_type_time ON unified_docs_view (doc_type, updated_at DESC);
CREATE INDEX idx_unified_docs_view_status_time ON unified_docs_view (status_category, updated_at DESC);

-- Search indexes
CREATE INDEX idx_unified_docs_view_ref_number ON unified_docs_view (ref_number);
CREATE INDEX idx_unified_docs_view_status ON unified_docs_view (status);

-- Partial indexes for active documents
CREATE INDEX idx_unified_docs_view_active ON unified_docs_view (updated_at DESC, requestor_id, assigned_to_user_id) 
WHERE status_category = 'active';

-- ============================================================================
-- CREATE REFRESH FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION refresh_unified_docs_view()
RETURNS void AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY unified_docs_view;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- SETUP AUTOMATIC REFRESH (Optional - adjust frequency as needed)
-- ============================================================================

-- Create a function to schedule automatic refresh
-- This should be called by a cron job or application scheduler
-- Frequency: Every 5 minutes for real-time updates, or every hour for better performance

-- Example cron job entry (add to postgres user's crontab):
-- */5 * * * * psql -d prs_production -c "SELECT refresh_unified_docs_view();"

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Check materialized view size and performance
SELECT 
  schemaname,
  matviewname,
  hasindexes,
  ispopulated,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||matviewname)) as size
FROM pg_matviews 
WHERE matviewname = 'unified_docs_view';

-- Test query performance
EXPLAIN (ANALYZE, BUFFERS) 
SELECT doc_type, COUNT(*) 
FROM unified_docs_view 
WHERE updated_at >= NOW() - INTERVAL '1 month' 
GROUP BY doc_type;

-- Sample data verification
SELECT 
  doc_type,
  status_category,
  COUNT(*) as count,
  MIN(updated_at) as oldest,
  MAX(updated_at) as newest
FROM unified_docs_view 
GROUP BY doc_type, status_category 
ORDER BY doc_type, status_category;
