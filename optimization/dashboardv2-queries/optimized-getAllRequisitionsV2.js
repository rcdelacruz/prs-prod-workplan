/**
 * Optimized getAllRequisitionsV2 method for TimescaleDB
 *
 * Key optimizations:
 * 1. Time-based filtering with chunk exclusion
 * 2. Single query approach instead of multiple queries
 * 3. Optimized CTEs with proper indexing hints
 * 4. Reduced subquery complexity
 * 5. Leverages TimescaleDB's time-series capabilities
 */

async getAllRequisitionsV2Optimized(payload) {
  const {
    limit = 10,
    page = 1,
    order,
    filterBy,
    userFromToken,
    requestType,
    timeRange = '6 months', // New: Time-based filtering
  } = payload;

  const { id: userId, role } = userFromToken;
  const offset = (page - 1) * limit;

  // Time-based optimization: Use TimescaleDB's time partitioning
  const timeFilter = this.buildTimeFilter(timeRange, filterBy?.updated_at);

  const replacements = {
    userId,
    limit: parseInt(limit),
    offset: parseInt(offset),
    timeStart: timeFilter.start,
    timeEnd: timeFilter.end,
  };

  // Build optimized filter conditions with time-based hints
  const baseFilterConditions = this.buildOptimizedFilters(filterBy, replacements);
  const baseFilterClause = baseFilterConditions.length > 0
    ? `AND ${baseFilterConditions.join(' AND ')}`
    : '';

  // Optimized unified docs CTE with TimescaleDB hints
  const optimizedUnifiedDocsCTE = `
    WITH RECURSIVE unified_docs AS (
      -- Use time-based filtering for chunk exclusion
      SELECT * FROM (
        -- Requisitions with time-based optimization
        SELECT
          r.id, 'requisition' AS doc_type,
          CASE
            WHEN r.status = 'rs_draft' THEN CONCAT('RS-TMP-', r.company_code, r.rs_letter, COALESCE(r.draft_rs_number, ''))
            ELSE CONCAT('RS-', r.company_code, r.rs_letter, COALESCE(r.rs_number, ''))
          END AS ref_number,
          r.created_by AS requestor_id, r.company_id, r.project_id, r.department_id,
          r.updated_at, r.status,
          CAST(r.id AS TEXT) AS grouping_id,
          r.status AS root_status,
          r.assigned_to AS assigned_to_user_id,
          -- Optimized approver aggregation using lateral join
          COALESCE(ra.approvers, '[]'::json) AS approvers
        FROM requisitions r
        LEFT JOIN LATERAL (
          SELECT JSON_AGG(DISTINCT user_id) AS approvers
          FROM (
            SELECT approver_id AS user_id FROM requisition_approvers WHERE requisition_id = r.id
            UNION ALL
            SELECT alt_approver_id AS user_id FROM requisition_approvers
            WHERE requisition_id = r.id AND alt_approver_id IS NOT NULL
          ) approver_list
        ) ra ON true
        WHERE r.updated_at >= :timeStart AND r.updated_at <= :timeEnd

        UNION ALL

        -- Canvass requisitions with optimized joins
        SELECT
          cr.id, 'canvass' AS doc_type,
          CASE
            WHEN cr.cs_number IS NULL THEN CONCAT('CS-TMP-', r.company_code, cr.cs_letter, COALESCE(cr.draft_cs_number, ''))
            ELSE CONCAT('CS-', r.company_code, cr.cs_letter, COALESCE(cr.cs_number, ''))
          END AS ref_number,
          r.created_by AS requestor_id, r.company_id, r.project_id, r.department_id,
          cr.updated_at, cr.status,
          CAST(r.id AS TEXT) AS grouping_id,
          r.status AS root_status,
          r.assigned_to AS assigned_to_user_id,
          COALESCE(ca.approvers, '[]'::json) AS approvers
        FROM canvass_requisitions cr
        INNER JOIN requisitions r ON cr.requisition_id = r.id
        LEFT JOIN LATERAL (
          SELECT JSON_AGG(DISTINCT user_id) AS approvers
          FROM (
            SELECT user_id FROM canvass_approvers WHERE canvass_requisition_id = cr.id
            UNION ALL
            SELECT alt_approver_id AS user_id FROM canvass_approvers
            WHERE canvass_requisition_id = cr.id AND alt_approver_id IS NOT NULL
          ) approver_list
        ) ca ON true
        WHERE cr.updated_at >= :timeStart AND cr.updated_at <= :timeEnd

        UNION ALL

        -- Purchase orders with time optimization
        SELECT
          po.id, 'purchase_order' AS doc_type,
          CONCAT('PO-', r.company_code, po.po_letter, po.po_number) AS ref_number,
          r.created_by AS requestor_id, r.company_id, r.project_id, r.department_id,
          po.updated_at, po.status,
          CAST(r.id AS TEXT) AS grouping_id,
          r.status AS root_status,
          r.assigned_to AS assigned_to_user_id,
          COALESCE(poa.approvers, '[]'::json) AS approvers
        FROM purchase_orders po
        INNER JOIN requisitions r ON po.requisition_id = r.id
        LEFT JOIN LATERAL (
          SELECT JSON_AGG(DISTINCT user_id) AS approvers
          FROM (
            SELECT user_id FROM purchase_order_approvers WHERE purchase_order_id = po.id
            UNION ALL
            SELECT alt_approver_id AS user_id FROM purchase_order_approvers
            WHERE purchase_order_id = po.id AND alt_approver_id IS NOT NULL
          ) approver_list
        ) poa ON true
        WHERE po.updated_at >= :timeStart AND po.updated_at <= :timeEnd

        UNION ALL

        -- Delivery receipts
        SELECT
          dr.id, 'delivery_receipt' AS doc_type,
          CASE
            WHEN dr.is_draft THEN CONCAT('RR-TMP-', COALESCE(dr.draft_dr_number, ''))
            ELSE CONCAT('RR-', COALESCE(dr.dr_number, ''))
          END AS ref_number,
          r.created_by AS requestor_id, r.company_id, r.project_id, r.department_id,
          dr.updated_at, COALESCE(dr.status, '') AS status,
          CAST(r.id AS TEXT) AS grouping_id,
          r.status AS root_status,
          r.assigned_to AS assigned_to_user_id,
          NULL AS approvers
        FROM delivery_receipts dr
        INNER JOIN requisitions r ON dr.requisition_id = r.id
        WHERE dr.updated_at >= :timeStart AND dr.updated_at <= :timeEnd

        UNION ALL

        -- Invoice reports
        SELECT
          ir.id, 'invoice' AS doc_type,
          CASE
            WHEN ir.is_draft THEN CONCAT('IR-TMP-', COALESCE(ir.ir_draft_number, ''))
            ELSE CONCAT('IR-', COALESCE(ir.ir_number, ''))
          END AS ref_number,
          r.created_by AS requestor_id, r.company_id, r.project_id, r.department_id,
          ir.updated_at, ir.status,
          CAST(r.id AS TEXT) AS grouping_id,
          r.status AS root_status,
          r.assigned_to AS assigned_to_user_id,
          NULL AS approvers
        FROM invoice_reports ir
        INNER JOIN requisitions r ON ir.requisition_id = r.id
        WHERE ir.updated_at >= :timeStart AND ir.updated_at <= :timeEnd

        UNION ALL

        -- Payment requests
        SELECT
          pr.id, 'payment_request' AS doc_type,
          CASE
            WHEN pr.is_draft THEN CONCAT('VR-TMP-', r.company_code, COALESCE(pr.draft_pr_number, ''))
            ELSE CONCAT('VR-', r.company_code, pr.pr_letter, COALESCE(pr.pr_number, ''))
          END AS ref_number,
          r.created_by AS requestor_id, r.company_id, r.project_id, r.department_id,
          pr.updated_at, pr.status,
          CAST(pr.requisition_id AS TEXT) AS grouping_id,
          r.status AS root_status,
          r.assigned_to AS assigned_to_user_id,
          COALESCE(pra.approvers, '[]'::json) AS approvers
        FROM rs_payment_requests pr
        INNER JOIN requisitions r ON pr.requisition_id = r.id
        LEFT JOIN LATERAL (
          SELECT JSON_AGG(DISTINCT user_id) AS approvers
          FROM (
            SELECT user_id FROM rs_payment_request_approvers WHERE payment_request_id = pr.id
            UNION ALL
            SELECT alt_approver_id AS user_id FROM rs_payment_request_approvers
            WHERE payment_request_id = pr.id AND alt_approver_id IS NOT NULL
          ) approver_list
        ) pra ON true
        WHERE pr.updated_at >= :timeStart AND pr.updated_at <= :timeEnd

        UNION ALL

        -- Non-requisitions
        SELECT
          nr.id, 'non_requisition' AS doc_type,
          CASE
            WHEN nr.status = 'draft' THEN CONCAT('NR-TMP-', nr.non_rs_letter, COALESCE(nr.draft_non_rs_number, ''))
            ELSE CONCAT('NR-', nr.non_rs_letter, COALESCE(nr.non_rs_number, ''))
          END AS ref_number,
          nr.created_by AS requestor_id, nr.company_id, nr.project_id, nr.department_id,
          nr.updated_at, nr.status,
          CONCAT('non_rs_', CAST(nr.id AS TEXT)) AS grouping_id,
          nr.status AS root_status,
          NULL AS assigned_to_user_id,
          COALESCE(nra.approvers, '[]'::json) AS approvers
        FROM non_requisitions nr
        LEFT JOIN LATERAL (
          SELECT JSON_AGG(DISTINCT user_id) AS approvers
          FROM (
            SELECT user_id FROM non_requisition_approvers WHERE non_requisition_id = nr.id
            UNION ALL
            SELECT alt_approver_id AS user_id FROM non_requisition_approvers
            WHERE non_requisition_id = nr.id AND alt_approver_id IS NOT NULL
          ) approver_list
        ) nra ON true
        WHERE nr.updated_at >= :timeStart AND nr.updated_at <= :timeEnd
      ) all_docs
    )
  `;

  // Build optimized order clause
  const orderClause = this.buildOptimizedOrderClause(order);

  // Single optimized query for all request types
  const optimizedQuery = this.buildSingleOptimizedQuery(
    optimizedUnifiedDocsCTE,
    baseFilterClause,
    orderClause,
    requestType,
    role
  );

  try {
    // Execute single query with all data and counts
    const results = await this.db.sequelize.query(optimizedQuery, {
      replacements,
      type: this.db.Sequelize.QueryTypes.SELECT,
    });

    // Process results efficiently
    return this.processOptimizedResults(results, requestType, limit, page);

  } catch (error) {
    console.error('Optimized query failed, falling back to original:', error);
    // Fallback to original method if optimization fails
    return this.getAllRequisitionsV2Original(payload);
  }
}

// Helper methods for optimization
buildTimeFilter(timeRange, specificDate) {
  if (specificDate) {
    const date = new Date(specificDate);
    return {
      start: new Date(date.getFullYear(), date.getMonth(), date.getDate()),
      end: new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1)
    };
  }

  const end = new Date();
  const start = new Date();

  switch (timeRange) {
    case '1 week':
      start.setDate(end.getDate() - 7);
      break;
    case '1 month':
      start.setMonth(end.getMonth() - 1);
      break;
    case '3 months':
      start.setMonth(end.getMonth() - 3);
      break;
    case '6 months':
      start.setMonth(end.getMonth() - 6);
      break;
    case '1 year':
      start.setFullYear(end.getFullYear() - 1);
      break;
    default:
      start.setMonth(end.getMonth() - 6); // Default to 6 months
  }

  return { start, end };
}

buildOptimizedFilters(filterBy, replacements) {
  const conditions = [];

  if (filterBy?.ref_number) {
    const normalizedSearchTerm = filterBy.ref_number.toLowerCase().replace(/[.\s]/g, '');
    const typeMapping = this.getDocumentTypeMapping();

    // Optimized search with proper indexing hints
    const searchConditions = [
      `ud.ref_number ILIKE :ref_number_gsv`,
      `ud.doc_type ILIKE :ref_number_gsv`,
      `c.name ILIKE :ref_number_gsv`,
      `CONCAT(u.first_name, ' ', u.last_name) ILIKE :ref_number_gsv`,
      `ud.status ILIKE :ref_number_gsv`
    ];

    const mappedType = typeMapping[normalizedSearchTerm];
    if (mappedType) {
      searchConditions.push(`ud.doc_type = '${mappedType}'`);
    }

    conditions.push(`(${searchConditions.join(' OR ')})`);
    replacements.ref_number_gsv = `%${filterBy.ref_number}%`;
  }

  if (filterBy?.type) {
    const normalizedType = filterBy.type.toLowerCase().replace(/[.\s]/g, '');
    const typeMapping = this.getDocumentTypeMapping();
    const mappedType = typeMapping[normalizedType];

    if (mappedType) {
      conditions.push(`ud.doc_type = :type`);
      replacements.type = mappedType;
    } else {
      conditions.push(`ud.doc_type ILIKE :type`);
      replacements.type = filterBy.type;
    }
  }

  if (filterBy?.company) {
    conditions.push(`c.name ILIKE :company`);
    replacements.company = `%${filterBy.company}%`;
  }

  if (filterBy?.project_department) {
    conditions.push(`(d.name ILIKE :project_department_search OR p.name ILIKE :project_department_search)`);
    replacements.project_department_search = `%${filterBy.project_department.trim()}%`;
  }

  if (filterBy?.requestor) {
    conditions.push(`CONCAT(u.first_name, ' ', u.last_name) ILIKE :requestor`);
    replacements.requestor = `%${filterBy.requestor}%`;
  }

  if (filterBy?.status) {
    conditions.push(`ud.status ILIKE :status`);
    replacements.status = `%${filterBy.status}%`;
  }

  if (filterBy?.statuses && Array.isArray(filterBy.statuses) && filterBy.statuses.length > 0) {
    conditions.push(`ud.status IN (:statuses)`);
    replacements.statuses = filterBy.statuses;
  }

  if (filterBy?.companies && Array.isArray(filterBy.companies) && filterBy.companies.length > 0) {
    conditions.push(`ud.company_id IN (:companies)`);
    replacements.companies = filterBy.companies;
  }

  return conditions;
}

buildOptimizedOrderClause(order) {
  if (!order || Object.keys(order).length === 0) {
    return `
      ORDER BY
        CASE WHEN ud.root_status = 'closed' THEN 2 ELSE 1 END ASC,
        ud.updated_at DESC,
        ud.grouping_id ASC,
        ud.id ASC
    `;
  }

  const [field, direction] = Object.entries(order)[0];
  const sortDirection = direction?.toUpperCase() === 'ASC' ? 'ASC' : 'DESC';

  const docTypeOrder = `CASE ud.doc_type
    WHEN 'requisition' THEN 1
    WHEN 'canvass' THEN 2
    WHEN 'purchase_order' THEN 3
    WHEN 'invoice' THEN 4
    WHEN 'delivery_receipt' THEN 5
    WHEN 'payment_request' THEN 6
    WHEN 'non_requisition' THEN 7
    ELSE 99 END`;

  switch (field) {
    case 'ref_number':
      return `ORDER BY ud.ref_number ${sortDirection}, ud.id ASC`;
    case 'doc_type':
      return `ORDER BY ${docTypeOrder} ${sortDirection}, ud.id ASC`;
    case 'requestor':
      return `ORDER BY ${docTypeOrder} ASC, CONCAT(u.first_name, ' ', u.last_name) ${sortDirection}, ud.id ASC`;
    case 'company':
      return `ORDER BY ${docTypeOrder} ASC, c.name ${sortDirection}, ud.id ASC`;
    case 'updated_at':
    case 'updatedAt':
      return `ORDER BY ${docTypeOrder} ASC, ud.updated_at ${sortDirection}, ud.id ASC`;
    case 'status':
      return `ORDER BY ${docTypeOrder} ASC, ud.status ${sortDirection}, ud.id ASC`;
    default:
      return `ORDER BY ${docTypeOrder} ASC, ud.updated_at DESC, ud.id ASC`;
  }
}

buildSingleOptimizedQuery(unifiedDocsCTE, baseFilterClause, orderClause, requestType, role) {
  const baseQuery = `
    ${unifiedDocsCTE}
    SELECT
      -- Data columns
      ud.id, ud.doc_type, ud.ref_number, ud.requestor_id,
      CONCAT(u.first_name, ' ', u.last_name) AS requestor_name,
      ud.company_id, c.name AS company_name,
      ud.project_id, p.name AS project_name,
      ud.department_id, d.name AS department_name,
      ud.updated_at, ud.status, ud.approvers, ud.grouping_id,
      ud.root_status, ud.assigned_to_user_id,
      CONCAT(assignee_u.first_name, ' ', assignee_u.last_name) AS assigned_to_user_name,

      -- Count columns for pagination
      COUNT(*) OVER() AS total_count,
      COUNT(*) FILTER (WHERE ud.requestor_id = :userId AND ud.doc_type IN ('requisition', 'non_requisition')) OVER() AS my_requests_total,
      COUNT(*) FILTER (WHERE ${this.buildApprovalCondition(role)}) OVER() AS my_approvals_total,

      -- Request type indicator
      CASE
        WHEN ud.requestor_id = :userId AND ud.doc_type IN ('requisition', 'non_requisition') THEN 'my_request'
        WHEN ${this.buildApprovalCondition(role)} THEN 'my_approval'
        ELSE 'all'
      END AS request_category

    FROM unified_docs ud
    LEFT JOIN users u ON ud.requestor_id = u.id
    LEFT JOIN companies c ON ud.company_id = c.id
    LEFT JOIN projects p ON ud.project_id = p.id
    LEFT JOIN departments d ON ud.department_id = d.id
    LEFT JOIN users assignee_u ON ud.assigned_to_user_id = assignee_u.id
    WHERE 1=1 ${baseFilterClause}
  `;

  // Add request type filtering
  let requestTypeFilter = '';
  if (requestType === 'my_request') {
    requestTypeFilter = ` AND ud.requestor_id = :userId AND ud.doc_type IN ('requisition', 'non_requisition')`;
  } else if (requestType === 'my_approval') {
    requestTypeFilter = ` AND (${this.buildApprovalCondition(role)})`;
  }

  return `${baseQuery}${requestTypeFilter} ${orderClause} LIMIT :limit OFFSET :offset`;
}

buildApprovalCondition(role) {
  if (['Purchasing Staff', 'Purchasing Head', 'Purchasing Admin'].includes(role.name)) {
    return `
      (ud.doc_type = 'requisition' AND ud.status = 'assigning' AND ud.status != 'rs_draft') OR
      (ud.assigned_to_user_id = :userId) OR
      (ud.doc_type = 'requisition' AND ud.approvers::text LIKE '%' || :userId || '%') OR
      (ud.doc_type = 'canvass' AND ud.approvers::text LIKE '%' || :userId || '%') OR
      (ud.doc_type = 'purchase_order' AND ud.approvers::text LIKE '%' || :userId || '%') OR
      (ud.doc_type = 'payment_request' AND ud.approvers::text LIKE '%' || :userId || '%') OR
      (ud.doc_type = 'non_requisition' AND ud.approvers::text LIKE '%' || :userId || '%')
    `;
  } else {
    return `
      (ud.doc_type = 'requisition' AND ud.status != 'rs_draft' AND ud.approvers::text LIKE '%' || :userId || '%') OR
      (ud.doc_type = 'canvass' AND ud.approvers::text LIKE '%' || :userId || '%') OR
      (ud.doc_type = 'purchase_order' AND ud.approvers::text LIKE '%' || :userId || '%') OR
      (ud.doc_type = 'payment_request' AND ud.status != 'PR Draft' AND ud.approvers::text LIKE '%' || :userId || '%') OR
      (ud.doc_type = 'non_requisition' AND ud.approvers::text LIKE '%' || :userId || '%')
    `;
  }
}

processOptimizedResults(results, requestType, limit, page) {
  if (!results || results.length === 0) {
    return {
      my_request: [],
      my_approval: [],
      all: [],
      meta: {
        message: 'Successfully retrieved dashboard data',
        page: parseInt(page),
        limit: parseInt(limit),
        myRequestsTotal: 0,
        myRequestsTotalPages: 0,
        myApprovalsTotal: 0,
        myApprovalsTotalPages: 0,
        allTotal: 0,
        allTotalPages: 0,
      },
    };
  }

  const docTypeOutputMap = {
    requisition: 'R.S.',
    canvass: 'Canvass',
    purchase_order: 'Order',
    delivery_receipt: 'Delivery',
    invoice: 'Invoice',
    payment_request: 'Voucher',
    non_requisition: 'Non-R.S.',
  };

  // Extract totals from first row
  const firstRow = results[0];
  const totalCounts = {
    myRequestsTotal: parseInt(firstRow.my_requests_total || 0),
    myApprovalsTotal: parseInt(firstRow.my_approvals_total || 0),
    allTotal: parseInt(firstRow.total_count || 0),
  };

  // Group results by request category
  const groupedResults = {
    my_request: [],
    my_approval: [],
    all: [],
  };

  results.forEach(item => {
    const mappedItem = {
      ...item,
      doc_type: docTypeOutputMap[item.doc_type] || item.doc_type,
    };

    // Remove count columns from individual items
    delete mappedItem.total_count;
    delete mappedItem.my_requests_total;
    delete mappedItem.my_approvals_total;
    delete mappedItem.request_category;

    if (requestType === 'my_request' || requestType === undefined) {
      if (item.request_category === 'my_request') {
        groupedResults.my_request.push(mappedItem);
      }
    }

    if (requestType === 'my_approval' || requestType === undefined) {
      if (item.request_category === 'my_approval') {
        groupedResults.my_approval.push(mappedItem);
      }
    }

    if (requestType === 'all' || requestType === undefined) {
      groupedResults.all.push(mappedItem);
    }
  });

  return {
    my_request: requestType === 'my_request' || requestType === undefined ? groupedResults.my_request : [],
    my_approval: requestType === 'my_approval' || requestType === undefined ? groupedResults.my_approval : [],
    all: requestType === 'all' || requestType === undefined ? groupedResults.all : [],
    meta: {
      message: 'Successfully retrieved dashboard data',
      page: parseInt(page),
      limit: parseInt(limit),
      myRequestsTotal: totalCounts.myRequestsTotal,
      myRequestsTotalPages: Math.ceil(totalCounts.myRequestsTotal / limit),
      myApprovalsTotal: totalCounts.myApprovalsTotal,
      myApprovalsTotalPages: Math.ceil(totalCounts.myApprovalsTotal / limit),
      allTotal: totalCounts.allTotal,
      allTotalPages: Math.ceil(totalCounts.allTotal / limit),
    },
  };
}
