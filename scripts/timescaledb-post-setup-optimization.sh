#!/bin/bash
# /opt/prs/prs-deployment/scripts/timescaledb-post-setup-optimization.sh
# Post-setup optimization for TimescaleDB after migration completion
# Run this after the migration 20250628120000-timescaledb-setup.js has completed

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
    echo -e "${BLUE}           TimescaleDB Post-Setup Optimization               ${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

print_info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Check if container is running
check_container() {
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        print_error "PostgreSQL container '$CONTAINER_NAME' is not running"
        exit 1
    fi
    print_success "PostgreSQL container is running"
}

# Check if TimescaleDB extension is installed
check_timescaledb() {
    local ts_version=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT extversion FROM pg_extension WHERE extname='timescaledb';" 2>/dev/null | xargs || echo "")

    if [ -z "$ts_version" ]; then
        print_error "TimescaleDB extension not found"
        exit 1
    fi

    print_success "TimescaleDB extension found (version: $ts_version)"
}

# Verify hypertables from migration
verify_hypertables() {
    print_info "Verifying hypertables created by migration..."

    local hypertable_count=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT count(*) FROM timescaledb_information.hypertables;" | xargs)

    # Expected count based on current setup (original 39 + additional tables from imported data)
    # Original migration: 39 tables (including transaction_logs)
    # Additional imported tables: 9 tables (department_*, items, leaves, etc.)
    local expected_count=48

    if [ "$hypertable_count" -eq $expected_count ]; then
        print_success "All $expected_count hypertables verified (includes additional tables from imported setup)"
    else
        print_warning "Expected $expected_count hypertables, found $hypertable_count"
        print_info "This may indicate missing tables or additional tables from data import"
    fi

    # List hypertables for verification
    echo ""
    print_info "Current hypertables:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT
        hypertable_name,
        num_chunks,
        compression_enabled
    FROM timescaledb_information.hypertables
    ORDER BY hypertable_name;
    "
}

# Apply compression policies based on migration configuration
apply_compression_policies() {
    print_info "Applying compression policies for high-volume tables..."

    # High-volume tables (7-day compression)
    local high_volume_tables=("audit_logs" "notifications" "notes" "comments" "force_close_logs" "transaction_logs")

    for table in "${high_volume_tables[@]}"; do
        print_info "Setting up compression for $table..."
        docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT add_compression_policy('$table', INTERVAL '7 days');
        " 2>/dev/null || print_warning "Compression policy for $table may already exist"
    done

    # History tables (14-day compression)
    local history_tables=("requisition_canvass_histories" "requisition_item_histories" "requisition_order_histories" "requisition_delivery_histories" "requisition_payment_histories" "requisition_return_histories" "non_requisition_histories" "invoice_report_histories" "delivery_receipt_items_history")

    for table in "${history_tables[@]}"; do
        print_info "Setting up compression for $table..."
        docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT add_compression_policy('$table', INTERVAL '14 days');
        " 2>/dev/null || print_warning "Compression policy for $table may already exist"
    done

    print_success "Compression policies applied"
}

# Apply retention policies for data lifecycle management
apply_retention_policies() {
    print_info "Applying retention policies for data lifecycle management..."

    # High-volume tables: 2 year retention
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT add_retention_policy('audit_logs', INTERVAL '2 years');
    SELECT add_retention_policy('notifications', INTERVAL '2 years');
    " 2>/dev/null || print_warning "Some retention policies may already exist"

    # History tables: 7 year retention (compliance)
    local history_tables=("requisition_canvass_histories" "requisition_item_histories" "requisition_order_histories")

    for table in "${history_tables[@]}"; do
        docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT add_retention_policy('$table', INTERVAL '7 years');
        " 2>/dev/null || print_warning "Retention policy for $table may already exist"
    done

    print_success "Retention policies applied"
}

# Optimize PostgreSQL settings for TimescaleDB
optimize_postgresql_settings() {
    print_info "Optimizing PostgreSQL settings for TimescaleDB..."

    # Run each ALTER SYSTEM command separately to avoid transaction block issues
    print_info "Setting TimescaleDB specific settings..."
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER SYSTEM SET timescaledb.max_background_workers = 16;" || print_warning "Failed to set timescaledb.max_background_workers"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER SYSTEM SET shared_preload_libraries = 'timescaledb';" || print_warning "Failed to set shared_preload_libraries"

    print_info "Setting memory optimization settings..."
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER SYSTEM SET shared_buffers = '2GB';" || print_warning "Failed to set shared_buffers"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER SYSTEM SET effective_cache_size = '6GB';" || print_warning "Failed to set effective_cache_size"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER SYSTEM SET work_mem = '32MB';" || print_warning "Failed to set work_mem"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER SYSTEM SET maintenance_work_mem = '512MB';" || print_warning "Failed to set maintenance_work_mem"

    print_info "Setting checkpoint optimization settings..."
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER SYSTEM SET checkpoint_completion_target = 0.9;" || print_warning "Failed to set checkpoint_completion_target"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER SYSTEM SET wal_buffers = '16MB';" || print_warning "Failed to set wal_buffers"

    print_info "Setting connection optimization settings..."
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER SYSTEM SET max_connections = 200;" || print_warning "Failed to set max_connections"

    print_info "Reloading configuration..."
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT pg_reload_conf();" || print_warning "Failed to reload configuration"

    print_success "PostgreSQL settings optimized"
    print_warning "Some settings require a database restart to take effect"
}

# Create monitoring views for TimescaleDB
create_monitoring_views() {
    print_info "Creating monitoring views for TimescaleDB..."

    # Drop existing views first to avoid column name conflicts
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    DROP VIEW IF EXISTS timescaledb_status CASCADE;
    DROP VIEW IF EXISTS chunk_status CASCADE;
    " 2>/dev/null || print_warning "Views may not exist yet"

    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    -- Create view for hypertable status
    CREATE VIEW timescaledb_status AS
    SELECT
        h.hypertable_name,
        h.num_chunks,
        h.compression_enabled,
        COUNT(c.chunk_name) as total_chunks,
        COUNT(CASE WHEN c.is_compressed THEN 1 END) as compressed_chunks,
        COALESCE(ROUND(SUM(
            CASE
                WHEN c.chunk_schema IS NOT NULL AND c.chunk_name IS NOT NULL
                THEN pg_total_relation_size(format('%I.%I', c.chunk_schema, c.chunk_name))
                ELSE 0
            END
        ) / 1024 / 1024, 2), 0) as total_size_mb
    FROM timescaledb_information.hypertables h
    LEFT JOIN timescaledb_information.chunks c ON h.hypertable_name = c.hypertable_name
    GROUP BY h.hypertable_name, h.num_chunks, h.compression_enabled
    ORDER BY h.hypertable_name;

    -- Create view for chunk information
    CREATE VIEW chunk_status AS
    SELECT
        hypertable_name,
        chunk_name,
        range_start,
        range_end,
        is_compressed,
        chunk_tablespace,
        chunk_creation_time
    FROM timescaledb_information.chunks
    ORDER BY hypertable_name, range_start DESC;
    "

    print_success "Monitoring views created"
}

# Run initial compression on existing data
run_initial_compression() {
    print_info "Running initial compression on existing data..."

    # Compress chunks older than 7 days for high-volume tables
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT compress_chunk(format('%I.%I', chunk_schema, chunk_name)::regclass)
    FROM timescaledb_information.chunks
    WHERE range_start < NOW() - INTERVAL '7 days'
    AND NOT is_compressed
    AND hypertable_name IN ('audit_logs', 'notifications', 'notes', 'comments', 'force_close_logs', 'transaction_logs')
    LIMIT 50;
    " || print_warning "Some chunks may already be compressed"

    print_success "Initial compression completed"
}

# Generate optimization report
generate_report() {
    print_info "Generating optimization report..."

    local report_file="/tmp/timescaledb-optimization-report-$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "TimescaleDB Post-Setup Optimization Report"
        echo "Generated: $(date)"
        echo "=========================================="
        echo ""

        echo "Hypertable Summary:"
        docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM timescaledb_status;"

        echo ""
        echo "Compression Policies:"
        docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM timescaledb_information.compression_settings;"

        echo ""
        echo "Background Jobs (including retention and compression policies):"
        docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT job_id, application_name, schedule_interval, max_runtime, max_retries, retry_period FROM timescaledb_information.jobs ORDER BY job_id;"

    } > "$report_file"

    print_success "Report generated: $report_file"
}

# Main execution
main() {
    print_header

    log_message "Starting TimescaleDB post-setup optimization"

    check_container
    check_timescaledb
    verify_hypertables
    apply_compression_policies
    apply_retention_policies
    optimize_postgresql_settings
    create_monitoring_views
    run_initial_compression
    generate_report

    echo ""
    print_success "TimescaleDB optimization completed successfully!"
    echo ""
    print_info "Next steps:"
    echo "  1. Monitor compression effectiveness with: SELECT * FROM timescaledb_status;"
    echo "  2. Check chunk status with: SELECT * FROM chunk_status;"
    echo "  3. Run weekly maintenance: ./weekly-maintenance-automation.sh"
    echo "  4. Consider database restart for all settings to take effect"
    echo ""
}

# Run main function
main "$@"
