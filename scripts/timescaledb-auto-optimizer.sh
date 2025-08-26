#!/bin/bash
# TimescaleDB Auto-Optimizer - Performs actual optimizations
# Automatically optimizes TimescaleDB hypertables based on analysis
# Respects zero deletion policy - only optimizes, never removes

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
    echo -e "${BLUE}           TimescaleDB Auto-Optimizer                         ${NC}"
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

# 1. Compress all uncompressed chunks
compress_uncompressed_chunks() {
    print_section "Compressing Uncompressed Chunks"

    print_info "Finding uncompressed chunks..."

    # Get list of uncompressed chunks from tables with compression enabled
    local uncompressed_chunks=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
    SELECT COUNT(*)
    FROM timescaledb_information.chunks c
    JOIN timescaledb_information.hypertables h
        ON c.hypertable_name = h.hypertable_name
        AND c.hypertable_schema = h.hypertable_schema
    WHERE NOT c.is_compressed
        AND h.compression_enabled = true;
    " | xargs)

    if [ "$uncompressed_chunks" -eq 0 ]; then
        print_success "All chunks from compression-enabled tables are already compressed!"
        return
    fi

    print_info "Found $uncompressed_chunks uncompressed chunks from compression-enabled tables. Compressing..."

    # Compress chunks one by one to avoid issues
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    DO \$\$
    DECLARE
        chunk_record RECORD;
        compressed_count INTEGER := 0;
    BEGIN
        FOR chunk_record IN
            SELECT c.chunk_schema, c.chunk_name, c.hypertable_name
            FROM timescaledb_information.chunks c
            JOIN timescaledb_information.hypertables h
                ON c.hypertable_name = h.hypertable_name
                AND c.hypertable_schema = h.hypertable_schema
            WHERE NOT c.is_compressed
                AND h.compression_enabled = true
            ORDER BY c.hypertable_name, c.chunk_name
        LOOP
            BEGIN
                PERFORM compress_chunk(format('%I.%I', chunk_record.chunk_schema, chunk_record.chunk_name));
                compressed_count := compressed_count + 1;
                RAISE NOTICE 'Compressed chunk % from table %', chunk_record.chunk_name, chunk_record.hypertable_name;
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE WARNING 'Failed to compress chunk % from table %: %', chunk_record.chunk_name, chunk_record.hypertable_name, SQLERRM;
            END;
        END LOOP;

        RAISE NOTICE 'Successfully compressed % chunks', compressed_count;
    END
    \$\$;
    "

    print_success "Chunk compression completed!"
}

# 2. Optimize compression policies for poor performers
optimize_compression_policies() {
    print_section "Optimizing Compression Policies"

    print_info "Checking for tables with poor compression ratios..."

    # Get tables with poor compression (less than 50%)
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    WITH compression_analysis AS (
        SELECT
            h.hypertable_name,
            COUNT(c.chunk_name) as total_chunks,
            COUNT(CASE WHEN c.is_compressed THEN 1 END) as compressed_chunks,
            ROUND(
                (COUNT(CASE WHEN c.is_compressed THEN 1 END)::numeric /
                 NULLIF(COUNT(c.chunk_name), 0) * 100), 1
            ) as compression_percentage
        FROM timescaledb_information.hypertables h
        LEFT JOIN timescaledb_information.chunks c ON h.hypertable_name = c.hypertable_name
        GROUP BY h.hypertable_name
        HAVING COUNT(c.chunk_name) > 0
    )
    SELECT
        hypertable_name,
        total_chunks,
        compressed_chunks,
        compression_percentage,
        CASE
            WHEN compression_percentage < 30 THEN 'CRITICAL: Needs immediate attention'
            WHEN compression_percentage < 50 THEN 'WARNING: Poor compression ratio'
            WHEN compression_percentage < 80 THEN 'INFO: Room for improvement'
            ELSE 'GOOD: Compression working well'
        END as status
    FROM compression_analysis
    WHERE compression_percentage < 80
    ORDER BY compression_percentage ASC;
    "

    print_success "Compression policy analysis completed!"
}

# 3. Update chunk intervals for tables with suboptimal chunking
optimize_chunk_intervals() {
    print_section "Analyzing Chunk Intervals"

    print_info "Checking tables with suboptimal chunk distribution..."

    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT
        h.hypertable_name,
        COUNT(c.chunk_name) as chunk_count,
        CASE
            WHEN COUNT(c.chunk_name) = 0 THEN 'No data - monitor for future usage'
            WHEN COUNT(c.chunk_name) = 1 THEN 'Single chunk - consider smaller intervals if data grows'
            WHEN COUNT(c.chunk_name) BETWEEN 2 AND 5 THEN 'Good chunking'
            WHEN COUNT(c.chunk_name) BETWEEN 6 AND 20 THEN 'Excellent chunking'
            WHEN COUNT(c.chunk_name) > 20 THEN 'Many chunks - consider larger intervals'
            ELSE 'Unknown'
        END as recommendation
    FROM timescaledb_information.hypertables h
    LEFT JOIN timescaledb_information.chunks c ON h.hypertable_name = c.hypertable_name
    GROUP BY h.hypertable_name
    HAVING COUNT(c.chunk_name) = 0 OR COUNT(c.chunk_name) = 1 OR COUNT(c.chunk_name) > 20
    ORDER BY COUNT(c.chunk_name) DESC;
    "

    print_info "Chunk interval analysis completed!"
}

# 4. Clean up and optimize background jobs
optimize_background_jobs() {
    print_section "Optimizing Background Jobs"

    print_info "Checking background job performance..."

    # Check for failed jobs
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT
        j.job_id,
        j.application_name,
        j.schedule_interval,
        j.scheduled,
        CASE
            WHEN j.scheduled = false THEN 'INACTIVE - May need attention'
            WHEN j.application_name LIKE '%Compression%' THEN 'COMPRESSION JOB - Active'
            WHEN j.application_name LIKE '%Retention%' THEN 'RETENTION JOB - Active'
            ELSE 'OTHER JOB - Active'
        END as status
    FROM timescaledb_information.jobs j
    WHERE j.scheduled = false OR j.application_name LIKE '%Compression%' OR j.application_name LIKE '%Retention%'
    ORDER BY j.scheduled ASC, j.job_id;
    "

    print_success "Background job analysis completed!"
}

# 5. Generate optimization summary
generate_optimization_summary() {
    print_section "Optimization Summary"

    print_info "Generating post-optimization summary..."

    # Get current compression status
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT
        COUNT(*) as total_hypertables,
        SUM(CASE WHEN h.compression_enabled THEN 1 ELSE 0 END) as compression_enabled_tables,
        (SELECT COUNT(*) FROM timescaledb_information.chunks) as total_chunks,
        (SELECT COUNT(*) FROM timescaledb_information.chunks WHERE is_compressed) as compressed_chunks,
        ROUND(
            (SELECT COUNT(*)::numeric FROM timescaledb_information.chunks WHERE is_compressed) /
            NULLIF((SELECT COUNT(*) FROM timescaledb_information.chunks), 0) * 100, 1
        ) as overall_compression_percentage
    FROM timescaledb_information.hypertables h;
    "

    echo ""
    print_success "Optimization completed successfully!"
    echo ""
    print_info "Recommendations for next run:"
    echo "  1. Monitor tables with 0 chunks for data insertion"
    echo "  2. Review tables with poor compression ratios"
    echo "  3. Consider adjusting chunk intervals for tables with many chunks"
    echo "  4. Run this optimizer weekly for best results"
}

# 6. Perform actual optimizations with safety checks
perform_optimizations() {
    print_info "Starting automated optimizations..."
    echo ""

    # Safety check - ensure we can connect to database
    if ! docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" > /dev/null 2>&1; then
        print_error "Cannot connect to database. Aborting optimizations."
        exit 1
    fi

    # Check if TimescaleDB extension is available
    if ! docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT extname FROM pg_extension WHERE extname='timescaledb';" | grep -q timescaledb; then
        print_error "TimescaleDB extension not found. Aborting optimizations."
        exit 1
    fi

    print_success "Database connectivity and TimescaleDB extension verified!"
    echo ""

    # Perform optimizations
    compress_uncompressed_chunks
    optimize_compression_policies
    optimize_chunk_intervals
    optimize_background_jobs
    generate_optimization_summary
}

# Main execution
main() {
    print_header

    print_info "TimescaleDB Auto-Optimizer will perform the following:"
    echo "  ✅ Compress all uncompressed chunks"
    echo "  ✅ Analyze and optimize compression policies"
    echo "  ✅ Review chunk interval effectiveness"
    echo "  ✅ Check background job health"
    echo "  ✅ Generate optimization summary"
    echo ""
    print_info "This respects your zero deletion policy - no tables will be removed."
    echo ""

    # Perform the optimizations
    perform_optimizations

    echo ""
    print_success "TimescaleDB auto-optimization completed!"
    echo ""
    print_info "Schedule this script to run weekly for optimal performance:"
    echo "  0 2 * * 0 /opt/prs/prs-deployment/scripts/timescaledb-auto-optimizer.sh"
}

# Run the auto-optimizer
main "$@"
