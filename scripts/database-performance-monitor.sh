#!/bin/bash
# /opt/prs-deployment/scripts/database-performance-monitor.sh
# Database-specific performance monitoring for PRS on-premises deployment

set -euo pipefail

LOG_FILE="/var/log/prs-db-monitoring.log"
METRICS_FILE="/var/lib/node_exporter/textfile_collector/prs-db-metrics.prom"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/02-docker-configuration/.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

collect_database_metrics() {
    log_message "Collecting database performance metrics"

    # Database connection and activity metrics
    local db_stats=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "
    SELECT
        (SELECT count(*) FROM pg_stat_activity) as total_connections,
        (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') as active_connections,
        (SELECT count(*) FROM pg_stat_activity WHERE state = 'idle') as idle_connections,
        (SELECT round(100.0 * sum(blks_hit) / nullif(sum(blks_hit) + sum(blks_read), 0), 2) FROM pg_stat_database WHERE datname = '${POSTGRES_DB:-prs_production}') as cache_hit_ratio,
        (SELECT pg_database_size('${POSTGRES_DB:-prs_production}')) as database_size,
        (SELECT sum(xact_commit + xact_rollback) FROM pg_stat_database WHERE datname = '${POSTGRES_DB:-prs_production}') as total_transactions;
    " | tr '|' ' ')

    read total_conn active_conn idle_conn cache_hit db_size total_txn <<< "$db_stats"

    # Query performance metrics
    local slow_queries=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "
    SELECT count(*) FROM pg_stat_statements WHERE mean_time > 1000 AND calls > 10;
    " | xargs)

    # Table statistics
    local table_stats=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "
    SELECT
        sum(n_tup_ins) as total_inserts,
        sum(n_tup_upd) as total_updates,
        sum(n_tup_del) as total_deletes,
        sum(n_live_tup) as live_tuples,
        sum(n_dead_tup) as dead_tuples
    FROM pg_stat_user_tables;
    " | tr '|' ' ')

    read total_ins total_upd total_del live_tup dead_tup <<< "$table_stats"

    # TimescaleDB specific metrics
    local ts_stats=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "
    SELECT
        count(*) as total_chunks,
        count(*) FILTER (WHERE is_compressed = true) as compressed_chunks,
        coalesce(round(avg((before_compression_total_bytes::numeric - after_compression_total_bytes::numeric) / before_compression_total_bytes::numeric * 100), 2), 0) as avg_compression_ratio
    FROM timescaledb_information.chunks c
    LEFT JOIN timescaledb_information.compressed_hypertable_stats s ON c.hypertable_name = s.hypertable_name;
    " | tr '|' ' ')

    read total_chunks compressed_chunks avg_compression <<< "$ts_stats"

    # Write metrics to Prometheus format
    mkdir -p "$(dirname "$METRICS_FILE")"
    cat > "$METRICS_FILE" << EOF
# HELP prs_db_connections Database connections
# TYPE prs_db_connections gauge
prs_db_connections{state="total"} ${total_conn:-0}
prs_db_connections{state="active"} ${active_conn:-0}
prs_db_connections{state="idle"} ${idle_conn:-0}

# HELP prs_db_cache_hit_ratio Database cache hit ratio percentage
# TYPE prs_db_cache_hit_ratio gauge
prs_db_cache_hit_ratio ${cache_hit:-0}

# HELP prs_db_size_bytes Database size in bytes
# TYPE prs_db_size_bytes gauge
prs_db_size_bytes ${db_size:-0}

# HELP prs_db_transactions_total Total database transactions
# TYPE prs_db_transactions_total counter
prs_db_transactions_total ${total_txn:-0}

# HELP prs_db_slow_queries Number of slow queries
# TYPE prs_db_slow_queries gauge
prs_db_slow_queries ${slow_queries:-0}

# HELP prs_db_table_operations_total Table operations
# TYPE prs_db_table_operations_total counter
prs_db_table_operations_total{operation="insert"} ${total_ins:-0}
prs_db_table_operations_total{operation="update"} ${total_upd:-0}
prs_db_table_operations_total{operation="delete"} ${total_del:-0}

# HELP prs_db_tuples Table tuples
# TYPE prs_db_tuples gauge
prs_db_tuples{state="live"} ${live_tup:-0}
prs_db_tuples{state="dead"} ${dead_tup:-0}

# HELP prs_timescaledb_chunks TimescaleDB chunks
# TYPE prs_timescaledb_chunks gauge
prs_timescaledb_chunks{state="total"} ${total_chunks:-0}
prs_timescaledb_chunks{state="compressed"} ${compressed_chunks:-0}

# HELP prs_timescaledb_compression_ratio Average compression ratio percentage
# TYPE prs_timescaledb_compression_ratio gauge
prs_timescaledb_compression_ratio ${avg_compression:-0}
EOF

    log_message "Database metrics collected: Connections=${total_conn:-0}, Cache_Hit=${cache_hit:-0}%, Slow_Queries=${slow_queries:-0}"
}

analyze_query_performance() {
    log_message "Analyzing query performance"

    # Get top slow queries
    docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -c "
    SELECT
        left(query, 80) as query_snippet,
        calls,
        round(mean_time::numeric, 2) as avg_time_ms,
        round(total_time::numeric, 2) as total_time_ms,
        round(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0), 2) as hit_percent
    FROM pg_stat_statements
    WHERE calls > 100
    ORDER BY total_time DESC
    LIMIT 10;
    " > /tmp/slow-queries-$(date +%Y%m%d_%H%M%S).log

    # Check for table bloat
    local bloated_tables=$(docker exec prs-onprem-postgres-timescale psql -U "${POSTGRES_USER:-prs_user}" -d "${POSTGRES_DB:-prs_production}" -t -c "
    SELECT count(*) FROM pg_stat_user_tables
    WHERE n_dead_tup > 1000
    AND n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0) > 0.1;
    " | xargs)

    if [ "$bloated_tables" -gt 0 ]; then
        log_message "WARNING: $bloated_tables tables have significant bloat"
    fi
}

main() {
    log_message "Starting database performance monitoring"

    collect_database_metrics
    analyze_query_performance

    log_message "Database performance monitoring completed"
}

main "$@"
