#!/bin/bash
# /opt/prs/prs-deployment/scripts/analyze-hypertable-differences.sh
# Analyze differences between expected and actual hypertables
# This helps understand what was imported from other setups

set -euo pipefail

# Load environment variables
if [ -f "/opt/prs/prs-deployment/02-docker-configuration/.env" ]; then
    set -a
    source /opt/prs/prs-deployment/02-docker-configuration/.env
    set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
POSTGRES_USER="${POSTGRES_USER:-prs_user}"
POSTGRES_DB="${POSTGRES_DB:-prs_production}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
CONTAINER_NAME="prs-onprem-postgres-timescale"

print_header() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}           TimescaleDB Hypertable Analysis                    ${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Expected tables from migration file
EXPECTED_TABLES=(
    "requisitions"
    "purchase_orders"
    "delivery_receipts"
    "force_close_logs"
    "audit_logs"
    "notifications"
    "notes"
    "requisition_badges"
    "requisition_approvers"
    "attachments"
    "histories"
    "requisition_canvass_histories"
    "canvass_item_suppliers"
    "canvass_approvers"
    "requisition_item_histories"
    "requisition_item_lists"
    "canvass_items"
    "purchase_order_items"
    "purchase_order_approvers"
    "non_requisitions"
    "requisition_order_histories"
    "requisition_delivery_histories"
    "requisition_payment_histories"
    "requisition_return_histories"
    "non_requisition_histories"
    "invoice_report_histories"
    "comments"
    "delivery_receipt_items"
    "delivery_receipt_items_history"
    "rs_payment_requests"
    "rs_payment_request_approvers"
    "canvass_requisitions"
    "non_requisition_approvers"
    "non_requisition_items"
    "delivery_receipt_invoices"
    "invoice_reports"
    "gate_passes"
    "purchase_order_cancelled_items"
    "transaction_logs"
)

# Get actual tables from database
get_actual_tables() {
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
    SELECT hypertable_name
    FROM timescaledb_information.hypertables
    ORDER BY hypertable_name;
    " | sed 's/^ *//' | grep -v '^$'
}

analyze_differences() {
    print_header

    print_info "Analyzing hypertable differences between expected and actual setup..."
    echo ""

    # Get actual tables
    local actual_tables=($(get_actual_tables))

    echo "📊 Summary:"
    echo "  Expected tables: ${#EXPECTED_TABLES[@]}"
    echo "  Actual tables: ${#actual_tables[@]}"
    echo "  Difference: $((${#actual_tables[@]} - ${#EXPECTED_TABLES[@]}))"
    echo ""

    # Find extra tables (in actual but not in expected)
    print_info "Extra tables (not in original migration):"
    local extra_count=0
    for table in "${actual_tables[@]}"; do
        if [[ ! " ${EXPECTED_TABLES[@]} " =~ " ${table} " ]]; then
            echo "  + $table"
            ((extra_count++))
        fi
    done

    if [ $extra_count -eq 0 ]; then
        print_success "No extra tables found"
    else
        print_warning "Found $extra_count extra tables"
    fi
    echo ""

    # Find missing tables (in expected but not in actual)
    print_info "Missing tables (expected but not found):"
    local missing_count=0
    for table in "${EXPECTED_TABLES[@]}"; do
        if [[ ! " ${actual_tables[@]} " =~ " ${table} " ]]; then
            echo "  - $table"
            ((missing_count++))
        fi
    done

    if [ $missing_count -eq 0 ]; then
        print_success "No missing tables found"
    else
        print_warning "Found $missing_count missing tables"
    fi
    echo ""

    # Show table categories for extra tables
    if [ $extra_count -gt 0 ]; then
        print_info "Analysis of extra tables:"
        for table in "${actual_tables[@]}"; do
            if [[ ! " ${EXPECTED_TABLES[@]} " =~ " ${table} " ]]; then
                local category="Unknown"
                case $table in
                    *_approval*) category="Approval Workflow" ;;
                    *department*) category="Department Management" ;;
                    *item*) category="Item Management" ;;
                    *supplier*) category="Supplier Management" ;;
                    *transaction*) category="Transaction Logging" ;;
                    *warrant*) category="Warranty Management" ;;
                    *leave*) category="Leave Management" ;;
                    *tom_*) category="TOM System" ;;
                    *ofm_*) category="OFM System" ;;
                esac
                echo "  $table -> $category"
            fi
        done
        echo ""
    fi

    # Recommendations
    print_info "Recommendations:"
    if [ $extra_count -gt 0 ]; then
        echo "  1. Extra tables suggest data was imported from a more comprehensive setup"
        echo "  2. These tables are now optimized with TimescaleDB compression"
        echo "  3. Update documentation to reflect the actual 48-table setup"
        echo "  4. Consider if any extra tables should be excluded from TimescaleDB"
    fi

    if [ $missing_count -gt 0 ]; then
        echo "  1. Missing tables may need to be created if required by your application"
        echo "  2. Check if these tables exist as regular tables (not hypertables)"
        echo "  3. Consider running additional migrations if needed"
    fi

    if [ $extra_count -eq 0 ] && [ $missing_count -eq 0 ]; then
        print_success "Perfect match! Your setup aligns with expectations."
    fi

    echo ""
    print_success "Analysis completed!"
}

# Main execution
analyze_differences "$@"
