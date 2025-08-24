#!/bin/bash
# /opt/prs/prs-deployment/scripts/timescaledb-post-setup-optimization.sh
# Post-setup optimization for TimescaleDB after migration completion
# Run this after the migration 20250628120000-timescaledb-setup.js has completed

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
POSTGRES_USER="${POSTGRES_USER:-prs_user}"
POSTGRES_DB="${POSTGRES_DB:-prs_production}"
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
    local ts_version=$(docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT extversion FROM pg_extension WHERE extname='timescaledb';" 2>/dev/null | xargs || echo "")
    
    if [ -z "$ts_version" ]; then
        print_error "TimescaleDB extension not found"
        exit 1
    fi
    
    print_success "TimescaleDB extension found (version: $ts_version)"
}

# Verify hypertables from migration
verify_hypertables() {
    print_info "Verifying hypertables created by migration..."
    
    local hypertable_count=$(docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT count(*) FROM timescaledb_information.hypertables;" | xargs)
    
    if [ "$hypertable_count" -eq 38 ]; then
        print_success "All 38 hypertables verified"
    else
        print_warning "Expected 38 hypertables, found $hypertable_count"
    fi
    
    # List hypertables for verification
    echo ""
    print_info "Current hypertables:"
    docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
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
    local high_volume_tables=("audit_logs" "notifications" "notes" "comments" "force_close_logs")
    
    for table in "${high_volume_tables[@]}"; do
        print_info "Setting up compression for $table..."
        docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT add_compression_policy('$table', INTERVAL '7 days');
        " 2>/dev/null || print_warning "Compression policy for $table may already exist"
    done
    
    # History tables (14-day compression)
    local history_tables=("requisition_canvass_histories" "requisition_item_histories" "requisition_order_histories" "requisition_delivery_histories" "requisition_payment_histories" "requisition_return_histories" "non_requisition_histories" "invoice_report_histories" "delivery_receipt_items_history")
    
    for table in "${history_tables[@]}"; do
        print_info "Setting up compression for $table..."
        docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT add_compression_policy('$table', INTERVAL '14 days');
        " 2>/dev/null || print_warning "Compression policy for $table may already exist"
    done
    
    print_success "Compression policies applied"
}

# Apply retention policies for data lifecycle management
apply_retention_policies() {
    print_info "Applying retention policies for data lifecycle management..."
    
    # High-volume tables: 2 year retention
    docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT add_retention_policy('audit_logs', INTERVAL '2 years');
    SELECT add_retention_policy('notifications', INTERVAL '2 years');
    " 2>/dev/null || print_warning "Some retention policies may already exist"
    
    # History tables: 7 year retention (compliance)
    local history_tables=("requisition_canvass_histories" "requisition_item_histories" "requisition_order_histories")
    
    for table in "${history_tables[@]}"; do
        docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT add_retention_policy('$table', INTERVAL '7 years');
        " 2>/dev/null || print_warning "Retention policy for $table may already exist"
    done
    
    print_success "Retention policies applied"
}

# Optimize PostgreSQL settings for TimescaleDB
optimize_postgresql_settings() {
    print_info "Optimizing PostgreSQL settings for TimescaleDB..."
    
    docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    -- TimescaleDB specific settings
    ALTER SYSTEM SET timescaledb.max_background_workers = 16;
    ALTER SYSTEM SET shared_preload_libraries = 'timescaledb';
    
    -- Memory optimization for 16GB system
    ALTER SYSTEM SET shared_buffers = '2GB';
    ALTER SYSTEM SET effective_cache_size = '6GB';
    ALTER SYSTEM SET work_mem = '32MB';
    ALTER SYSTEM SET maintenance_work_mem = '512MB';
    
    -- Checkpoint optimization
    ALTER SYSTEM SET checkpoint_completion_target = 0.9;
    ALTER SYSTEM SET wal_buffers = '16MB';
    
    -- Connection optimization
    ALTER SYSTEM SET max_connections = 200;
    
    -- Reload configuration
    SELECT pg_reload_conf();
    "
    
    print_success "PostgreSQL settings optimized"
    print_warning "Some settings require a database restart to take effect"
}

# Create monitoring views for TimescaleDB
create_monitoring_views() {
    print_info "Creating monitoring views for TimescaleDB..."
    
    docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    -- Create view for hypertable status
    CREATE OR REPLACE VIEW timescaledb_status AS
    SELECT 
        h.hypertable_name,
        h.num_chunks,
        h.compression_enabled,
        COALESCE(s.total_chunks, 0) as total_chunks,
        COALESCE(s.number_compressed_chunks, 0) as compressed_chunks,
        COALESCE(ROUND(s.before_compression_total_bytes / 1024 / 1024, 2), 0) as uncompressed_mb,
        COALESCE(ROUND(s.after_compression_total_bytes / 1024 / 1024, 2), 0) as compressed_mb,
        COALESCE(ROUND((s.before_compression_total_bytes - s.after_compression_total_bytes)::numeric / s.before_compression_total_bytes * 100, 2), 0) as compression_ratio
    FROM timescaledb_information.hypertables h
    LEFT JOIN timescaledb_information.compressed_hypertable_stats s ON h.hypertable_name = s.hypertable_name
    ORDER BY h.hypertable_name;
    
    -- Create view for chunk information
    CREATE OR REPLACE VIEW chunk_status AS
    SELECT 
        hypertable_name,
        chunk_name,
        range_start,
        range_end,
        is_compressed,
        chunk_tablespace,
        data_nodes
    FROM timescaledb_information.chunks
    ORDER BY hypertable_name, range_start DESC;
    "
    
    print_success "Monitoring views created"
}

# Run initial compression on existing data
run_initial_compression() {
    print_info "Running initial compression on existing data..."
    
    # Compress chunks older than 7 days for high-volume tables
    docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT compress_chunk(chunk_name)
    FROM timescaledb_information.chunks
    WHERE range_start < NOW() - INTERVAL '7 days'
    AND NOT is_compressed
    AND hypertable_name IN ('audit_logs', 'notifications', 'notes', 'comments', 'force_close_logs')
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
        docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM timescaledb_status;"
        
        echo ""
        echo "Compression Policies:"
        docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM timescaledb_information.compression_settings;"
        
        echo ""
        echo "Retention Policies:"
        docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM timescaledb_information.drop_chunks_policies;"
        
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
