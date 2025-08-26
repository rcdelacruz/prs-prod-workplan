#!/bin/bash
# TimescaleDB Health Monitor - Routine optimization checker
# Monitors hypertable effectiveness and suggests optimizations
# Respects zero deletion policy - focuses on optimization only

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
    echo -e "${BLUE}           TimescaleDB Health Monitor                         ${NC}"
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

# Monitor compression effectiveness
check_compression_effectiveness() {
    print_section "Compression Effectiveness"

    echo "📊 Hypertables by compression effectiveness:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT
        h.hypertable_name,
        COUNT(c.chunk_name) as total_chunks,
        COUNT(CASE WHEN c.is_compressed THEN 1 END) as compressed_chunks,
        ROUND(
            (COUNT(CASE WHEN c.is_compressed THEN 1 END)::numeric /
             NULLIF(COUNT(c.chunk_name), 0) * 100), 1
        ) as compression_percentage,
        CASE
            WHEN COUNT(c.chunk_name) = 0 THEN 'NO_DATA'
            WHEN COUNT(CASE WHEN c.is_compressed THEN 1 END)::numeric / COUNT(c.chunk_name) > 0.8 THEN 'EXCELLENT'
            WHEN COUNT(CASE WHEN c.is_compressed THEN 1 END)::numeric / COUNT(c.chunk_name) > 0.5 THEN 'GOOD'
            WHEN COUNT(CASE WHEN c.is_compressed THEN 1 END)::numeric / COUNT(c.chunk_name) > 0.2 THEN 'NEEDS_ATTENTION'
            ELSE 'POOR'
        END as compression_status
    FROM timescaledb_information.hypertables h
    LEFT JOIN timescaledb_information.chunks c ON h.hypertable_name = c.hypertable_name
    GROUP BY h.hypertable_name
    ORDER BY compression_percentage DESC NULLS LAST;
    "
    echo ""
}

# Check chunk distribution
check_chunk_distribution() {
    print_section "Chunk Distribution Analysis"

    echo "📈 Tables that might need chunk interval adjustment:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT
        h.hypertable_name,
        COUNT(c.chunk_name) as chunk_count,
        CASE
            WHEN COUNT(c.chunk_name) = 0 THEN 'OPTIMIZE: Enable data insertion'
            WHEN COUNT(c.chunk_name) = 1 THEN 'MONITOR: Single chunk - may need smaller intervals'
            WHEN COUNT(c.chunk_name) BETWEEN 2 AND 5 THEN 'GOOD: Reasonable chunking'
            WHEN COUNT(c.chunk_name) BETWEEN 6 AND 20 THEN 'EXCELLENT: Optimal chunking'
            WHEN COUNT(c.chunk_name) > 20 THEN 'OPTIMIZE: Consider larger chunk intervals'
            ELSE 'UNKNOWN'
        END as chunk_recommendation
    FROM timescaledb_information.hypertables h
    LEFT JOIN timescaledb_information.chunks c ON h.hypertable_name = c.hypertable_name
    GROUP BY h.hypertable_name
    ORDER BY chunk_count DESC;
    "
    echo ""
}

# Check compression policies
check_compression_policies() {
    print_section "Compression Policy Status"

    echo "🗜️ Compression policy effectiveness:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT
        j.hypertable_name,
        j.schedule_interval,
        j.max_runtime,
        CASE
            WHEN j.schedule_interval = '12:00:00' THEN 'STANDARD: 12-hour compression cycle'
            WHEN j.schedule_interval = '1 day' THEN 'CONSERVATIVE: Daily compression'
            WHEN j.schedule_interval < '12:00:00' THEN 'AGGRESSIVE: Frequent compression'
            ELSE 'CUSTOM: ' || j.schedule_interval
        END as policy_assessment
    FROM timescaledb_information.jobs j
    WHERE j.proc_name = 'policy_compression'
    ORDER BY j.hypertable_name;
    "
    echo ""
}

# Identify optimization opportunities
identify_optimization_opportunities() {
    print_section "Optimization Opportunities"

    echo "🎯 Tables that need optimization attention:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    WITH table_analysis AS (
        SELECT
            h.hypertable_name,
            COUNT(c.chunk_name) as chunk_count,
            COUNT(CASE WHEN c.is_compressed THEN 1 END) as compressed_chunks,
            h.compression_enabled
        FROM timescaledb_information.hypertables h
        LEFT JOIN timescaledb_information.chunks c ON h.hypertable_name = c.hypertable_name
        GROUP BY h.hypertable_name, h.compression_enabled
    )
    SELECT
        hypertable_name,
        chunk_count,
        compressed_chunks,
        compression_enabled,
        CASE
            WHEN chunk_count = 0 THEN 'ACTION: No data - consider data insertion or monitoring'
            WHEN chunk_count = 1 AND compressed_chunks = 0 THEN 'ACTION: Single uncompressed chunk - monitor growth'
            WHEN compression_enabled = false THEN 'ACTION: Enable compression'
            WHEN compressed_chunks = 0 AND chunk_count > 1 THEN 'ACTION: Force initial compression'
            WHEN compressed_chunks::numeric / chunk_count < 0.3 THEN 'ACTION: Improve compression policy'
            WHEN chunk_count > 15 THEN 'REVIEW: Many chunks - consider larger intervals'
            ELSE 'GOOD: No immediate action needed'
        END as optimization_action
    FROM table_analysis
    WHERE chunk_count = 0
       OR compression_enabled = false
       OR compressed_chunks = 0
       OR compressed_chunks::numeric / NULLIF(chunk_count, 0) < 0.5
       OR chunk_count > 15
    ORDER BY
        CASE
            WHEN chunk_count = 0 THEN 1
            WHEN compression_enabled = false THEN 2
            WHEN compressed_chunks = 0 THEN 3
            ELSE 4
        END,
        chunk_count DESC;
    "
    echo ""
}

# Check background job health
check_background_jobs() {
    print_section "Background Job Health"

    echo "⚙️ TimescaleDB background job status:"
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
    SELECT
        j.job_id,
        j.application_name,
        j.schedule_interval,
        j.max_retries,
        CASE
            WHEN j.scheduled = true THEN 'ACTIVE'
            ELSE 'INACTIVE'
        END as status,
        CASE
            WHEN j.application_name LIKE '%Compression%' THEN 'COMPRESSION'
            WHEN j.application_name LIKE '%Retention%' THEN 'RETENTION'
            WHEN j.application_name LIKE '%Telemetry%' THEN 'TELEMETRY'
            ELSE 'OTHER'
        END as job_type
    FROM timescaledb_information.jobs j
    ORDER BY job_type, j.job_id;
    "
    echo ""
}

# Generate actionable recommendations
generate_recommendations() {
    print_section "Actionable Recommendations"

    print_info "Based on the analysis above, here are specific actions you can take:"
    echo ""

    echo "🔧 IMMEDIATE OPTIMIZATIONS:"
    echo "   1. Run compression on uncompressed chunks:"
    echo "      SELECT compress_chunk(chunk_name) FROM timescaledb_information.chunks WHERE NOT is_compressed;"
    echo ""
    echo "   2. Check for tables with no data and monitor their usage"
    echo "   3. Review compression policies for tables with poor compression ratios"
    echo ""

    echo "📊 MONITORING ACTIONS:"
    echo "   1. Set up alerts for tables with 0 chunks that should have data"
    echo "   2. Monitor chunk growth patterns weekly"
    echo "   3. Review compression effectiveness monthly"
    echo ""

    echo "⚡ PERFORMANCE OPTIMIZATIONS:"
    echo "   1. Adjust chunk intervals for tables with too many/few chunks"
    echo "   2. Tune compression settings for tables with poor ratios"
    echo "   3. Consider retention policies for very large tables"
    echo ""

    echo "🎯 FOCUS AREAS (Zero Deletion Policy Compliant):"
    echo "   - Optimize existing hypertables rather than removing them"
    echo "   - Improve compression ratios and policies"
    echo "   - Monitor and tune chunk intervals"
    echo "   - Ensure all tables are being used effectively"
}

# Main execution
main() {
    print_header
    check_compression_effectiveness
    check_chunk_distribution
    check_compression_policies
    identify_optimization_opportunities
    check_background_jobs
    generate_recommendations

    echo ""
    print_success "TimescaleDB health check completed!"
    echo ""
    print_info "Run this script weekly to monitor TimescaleDB health"
    print_info "Focus on optimization rather than removal per zero deletion policy"
}

# Run the health check
main "$@"
