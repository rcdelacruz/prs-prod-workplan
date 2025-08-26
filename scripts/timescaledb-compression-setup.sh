#!/bin/bash
# TimescaleDB Compression Setup Script
# Enables compression and sets up compression policies for TimescaleDB hypertables
# Aligned with /opt/prs/prs-deployment/docs/docs/database/timescaledb.md

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
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
POSTGRES_USER="${POSTGRES_USER:-prs_user}"
POSTGRES_DB="${POSTGRES_DB:-prs_production}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
CONTAINER_NAME="prs-onprem-postgres-timescale"

print_header() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}           TimescaleDB Compression Setup                      ${NC}"
    echo -e "${BLUE}           $(date '+%Y-%m-%d %H:%M:%S')                                    ${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
}

print_section() {
    echo -e "${PURPLE}--- $1 ---${NC}"
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

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Compression policies configuration aligned with documentation
declare -A COMPRESSION_POLICIES=(
    # High-volume tables - compress after 7 days (as per docs)
    ["notifications"]="7 days:HIGH_VOLUME:user_id:created_at DESC"
    ["audit_logs"]="7 days:HIGH_VOLUME:user_id, action:created_at DESC"
    ["histories"]="7 days:HIGH_VOLUME:id:created_at DESC"
    ["comments"]="7 days:HIGH_VOLUME:id:created_at DESC"
    ["transaction_logs"]="7 days:HIGH_VOLUME:user_id, rs_id, level:time DESC"

    # History tables - compress after 14 days (as per docs)
    ["requisition_canvass_histories"]="14 days:HISTORY:id:created_at DESC"
    ["requisition_item_histories"]="14 days:HISTORY:id:created_at DESC"
    ["requisition_order_histories"]="14 days:HISTORY:id:created_at DESC"
    ["requisition_delivery_histories"]="14 days:HISTORY:id:created_at DESC"
    ["requisition_payment_histories"]="14 days:HISTORY:id:created_at DESC"
    ["requisition_return_histories"]="14 days:HISTORY:id:created_at DESC"
    ["non_requisition_histories"]="14 days:HISTORY:id:created_at DESC"
    ["invoice_report_histories"]="14 days:HISTORY:id:created_at DESC"
    ["delivery_receipt_items_history"]="14 days:HISTORY:id:created_at DESC"

    # Business tables - compress after 30 days (as per docs)
    ["requisitions"]="30 days:BUSINESS:department_id, status:created_at DESC"
    ["purchase_orders"]="30 days:BUSINESS:id:created_at DESC"
    ["delivery_receipts"]="30 days:BUSINESS:id:created_at DESC"
    ["delivery_receipt_items"]="30 days:BUSINESS:id:created_at DESC"
    ["attachments"]="30 days:BUSINESS:id:created_at DESC"
    ["notes"]="30 days:BUSINESS:id:created_at DESC"

    # Workflow tables - compress after 60 days
    ["requisition_approvers"]="60 days:WORKFLOW:id:created_at DESC"
    ["requisition_badges"]="60 days:WORKFLOW:id:created_at DESC"
    ["canvass_approvers"]="60 days:WORKFLOW:id:created_at DESC"
    ["canvass_items"]="60 days:WORKFLOW:id:created_at DESC"
    ["canvass_item_suppliers"]="60 days:WORKFLOW:id:created_at DESC"
    ["purchase_order_items"]="60 days:WORKFLOW:id:created_at DESC"
    ["purchase_order_approvers"]="60 days:WORKFLOW:id:created_at DESC"
)

# Check if TimescaleDB is available
check_timescaledb_status() {
    print_info "Checking TimescaleDB status..."

    if ! docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" > /dev/null 2>&1; then
        print_error "Cannot connect to database. Aborting."
        exit 1
    fi

    if ! docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT extname FROM pg_extension WHERE extname='timescaledb';" | grep -q timescaledb; then
        print_error "TimescaleDB extension not found. Aborting."
        exit 1
    fi

    print_success "TimescaleDB extension is available"
}

# Enable compression on a hypertable
enable_compression() {
    local table_name="$1"
    local segment_by="$2"
    local order_by="$3"

    print_info "Enabling compression for $table_name..."

    # Check if table is a hypertable
    local is_hypertable=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
    SELECT EXISTS (
        SELECT FROM timescaledb_information.hypertables
        WHERE hypertable_name = '$table_name' AND hypertable_schema = 'public'
    );
    " | xargs)

    if [ "$is_hypertable" != "t" ]; then
        print_warning "Skipping $table_name - not a hypertable"
        return 1
    fi

    # Check if compression is already enabled
    local compression_exists=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
    SELECT EXISTS (
        SELECT FROM timescaledb_information.compression_settings
        WHERE hypertable_name = '$table_name' AND hypertable_schema = 'public'
    );
    " | xargs)

    if [ "$compression_exists" = "t" ]; then
        print_info "Compression already enabled for $table_name"
        return 0
    fi

    # Enable compression
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    ALTER TABLE $table_name SET (
        timescaledb.compress,
        timescaledb.compress_segmentby = '$segment_by',
        timescaledb.compress_orderby = '$order_by'
    );
    " && print_success "Enabled compression for $table_name" || {
        print_error "Failed to enable compression for $table_name"
        return 1
    }
}

# Add compression policy
add_compression_policy() {
    local table_name="$1"
    local compress_after="$2"

    print_info "Adding compression policy for $table_name (after $compress_after)..."

    # Check if compression policy already exists
    local policy_exists=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
    SELECT EXISTS (
        SELECT FROM timescaledb_information.jobs
        WHERE hypertable_name = '$table_name'
        AND proc_name = 'policy_compression'
    );
    " | xargs)

    if [ "$policy_exists" = "t" ]; then
        print_info "Compression policy already exists for $table_name"
        return 0
    fi

    # Add compression policy
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT add_compression_policy('$table_name', INTERVAL '$compress_after');
    " && print_success "Added compression policy for $table_name (compress after $compress_after)" || {
        print_error "Failed to add compression policy for $table_name"
        return 1
    }
}

# Setup compression for all configured tables
setup_compression_policies() {
    print_section "Setting up compression policies"

    local success_count=0
    local error_count=0
    local skip_count=0

    for table_name in "${!COMPRESSION_POLICIES[@]}"; do
        local config="${COMPRESSION_POLICIES[$table_name]}"
        IFS=':' read -r compress_after priority segment_by order_by <<< "$config"

        print_info "Processing $table_name ($priority priority)..."

        # Enable compression first
        if enable_compression "$table_name" "$segment_by" "$order_by"; then
            # Add compression policy
            if add_compression_policy "$table_name" "$compress_after"; then
                ((success_count++))
            else
                ((error_count++))
            fi
        else
            ((skip_count++))
        fi

        echo ""
    done

    print_section "Compression Setup Summary"
    print_success "Successfully configured: $success_count tables"
    print_warning "Skipped (not hypertables): $skip_count tables"
    print_error "Errors encountered: $error_count tables"

    if [ $error_count -eq 0 ]; then
        print_success "All compression policies configured successfully!"
    fi
}

# Show compression status
show_compression_status() {
    print_section "Compression Status"

    print_info "Tables with compression enabled:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT
        h.hypertable_name,
        h.compression_enabled,
        COALESCE(cs.segmentby, 'none') as segment_by,
        COALESCE(cs.orderby, 'none') as order_by
    FROM timescaledb_information.hypertables h
    LEFT JOIN (
        SELECT
            hypertable_name,
            string_agg(attname, ', ' ORDER BY segmentby_column_index) as segmentby,
            string_agg(attname, ', ' ORDER BY orderby_column_index) as orderby
        FROM timescaledb_information.compression_settings
        WHERE hypertable_schema = 'public'
        GROUP BY hypertable_name
    ) cs ON h.hypertable_name = cs.hypertable_name
    WHERE h.hypertable_schema = 'public'
    ORDER BY h.compression_enabled DESC, h.hypertable_name;
    "

    echo ""
    print_info "Active compression policies:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT
        j.hypertable_name,
        j.schedule_interval,
        j.config->>'compress_after' as compress_after
    FROM timescaledb_information.jobs j
    WHERE j.proc_name = 'policy_compression'
    AND j.hypertable_schema = 'public'
    ORDER BY j.hypertable_name;
    "

    echo ""
    print_info "Chunk compression status:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT
        hypertable_name,
        COUNT(*) as total_chunks,
        COUNT(*) FILTER (WHERE is_compressed = true) as compressed_chunks,
        ROUND(
            (COUNT(*) FILTER (WHERE is_compressed = true)::numeric /
             NULLIF(COUNT(*), 0) * 100), 1
        ) as compression_percentage
    FROM timescaledb_information.chunks
    WHERE hypertable_schema = 'public'
    GROUP BY hypertable_name
    HAVING COUNT(*) > 0
    ORDER BY compression_percentage DESC, total_chunks DESC;
    "
}

# Remove compression policies
remove_compression_policies() {
    print_section "Removing compression policies"

    local success_count=0
    local error_count=0

    for table_name in "${!COMPRESSION_POLICIES[@]}"; do
        print_info "Removing compression policy for $table_name..."

        # Check if compression policy exists
        local policy_exists=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
        SELECT EXISTS (
            SELECT FROM timescaledb_information.jobs
            WHERE hypertable_name = '$table_name'
            AND proc_name = 'policy_compression'
        );
        " | xargs)

        if [ "$policy_exists" = "t" ]; then
            docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
            SELECT remove_compression_policy('$table_name');
            " && {
                print_success "Removed compression policy for $table_name"
                ((success_count++))
            } || {
                print_error "Failed to remove compression policy for $table_name"
                ((error_count++))
            }
        else
            print_info "No compression policy found for $table_name"
        fi
    done

    print_section "Compression Removal Summary"
    print_success "Successfully removed: $success_count policies"
    print_error "Errors encountered: $error_count policies"
}

# Main execution
main() {
    print_header

    local command="${1:-setup}"

    case "$command" in
        "setup")
            print_info "TimescaleDB Compression Setup will:"
            echo "  ✅ Enable compression on hypertables"
            echo "  ✅ Configure compression policies based on table priority"
            echo "  ✅ Align with documentation at docs/database/timescaledb.md"
            echo ""

            check_timescaledb_status
            setup_compression_policies
            ;;
        "status")
            check_timescaledb_status
            show_compression_status
            ;;
        "remove")
            print_warning "This will remove all compression policies!"
            echo "Compression settings on tables will remain, but automatic compression will stop."
            echo ""
            check_timescaledb_status
            remove_compression_policies
            ;;
        *)
            echo "Usage: $0 [setup|status|remove]"
            echo ""
            echo "Commands:"
            echo "  setup   - Enable compression and setup policies (default)"
            echo "  status  - Show current compression status"
            echo "  remove  - Remove all compression policies"
            exit 1
            ;;
    esac

    echo ""
    print_success "TimescaleDB compression management completed!"
}

# Run the script
main "$@"
